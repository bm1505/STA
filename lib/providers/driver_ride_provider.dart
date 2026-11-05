import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sta/services/database_service.dart';
import 'package:sta/models/user.dart';
import 'package:sta/models/vehicle.dart';
import 'package:sta/providers/ride_provider.dart';
import 'package:sta/services/sound_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

enum DriverRideStatus { idle, pickingUp, arrived, tripInProgress, waitingForPayment }

class DriverRideProvider extends ChangeNotifier {
  SupabaseClient get _db => Supabase.instance.client;
  StreamSubscription? _requestsSubscription;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _currentRideSubscription;
  StreamSubscription? _walletSubscription;
  StreamSubscription? _backgroundLocationSubscription;
  UserModel? _user;
  DriverRideStatus _status = DriverRideStatus.idle;
  Map<String, dynamic>? _currentRideData;
  ll.LatLng? _currentLocation;
  double _currentBearing = 0;
  ChatMessage? _lastMessage;
  double _walletBalance = 0;
  static const double DEBT_THRESHOLD = -20000;
  double _tripDistance = 0;
  ll.LatLng? _lastTripLocation;
  int _tripSeconds = 0;
  Timer? _tripTimer;
  String? _paymentStatus;
  final _rideRequestController = StreamController<Map<String, dynamic>>.broadcast();

  UserModel? get user => _user;
  DriverRideStatus get status => _status;
  Map<String, dynamic>? get currentRideData => _currentRideData;
  double get tripDistance => _tripDistance;
  int get tripSeconds => _tripSeconds;
  ll.LatLng? get currentLocation => _currentLocation;
  double get walletBalance => _walletBalance;
  bool get isBlocked => _walletBalance < DEBT_THRESHOLD;
  ChatMessage? get lastMessage => _lastMessage;
  String? get paymentStatus => _paymentStatus;
  Stream<Map<String, dynamic>> get rideRequestStream => _rideRequestController.stream;

  double get distanceToPickup {
    final p = pickupLatLng;
    if (_currentLocation == null || p == null) return 0;
    return Geolocator.distanceBetween(_currentLocation!.latitude,_currentLocation!.longitude,p.latitude,p.longitude)/1000;
  }
  double get distanceToDestination {
    final p = dropoffLatLng;
    if (_currentLocation == null || p == null) return 0;
    return Geolocator.distanceBetween(_currentLocation!.latitude,_currentLocation!.longitude,p.latitude,p.longitude)/1000;
  }
  double get currentFare => _calculateCurrentFare();

  double _calculateCurrentFare() =>
      (_currentRideData?['final_fare'] as num?)?.toDouble() ??
      (_currentRideData?['estimated_fare'] as num?)?.toDouble() ??
      0.0;

  ll.LatLng? _point(dynamic lat, dynamic lng) {
    if (lat == null || lng == null) return null;
    return ll.LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }
  ll.LatLng? get pickupLatLng => _point(_currentRideData?['pickup_latitude'], _currentRideData?['pickup_longitude']);
  ll.LatLng? get dropoffLatLng => _point(_currentRideData?['dropoff_latitude'], _currentRideData?['dropoff_longitude']);

  void updateLocation(Position position, String userId, bool isOnline) {
    _persistLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      heading: position.heading,
      speedMps: position.speed,
      userId: userId,
      isOnline: isOnline,
    );
  }

  void _handleBackgroundLocation(Map<String, dynamic> event) {
    final latitude = (event['latitude'] as num?)?.toDouble();
    final longitude = (event['longitude'] as num?)?.toDouble();
    final heading = (event['bearing'] as num?)?.toDouble() ?? 0;
    final userId = _db.auth.currentUser?.id;
    if (latitude == null || longitude == null || userId == null) return;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return;
    _persistLocation(
      latitude: latitude,
      longitude: longitude,
      heading: heading,
      speedMps: (event['speed'] as num?)?.toDouble() ?? 0,
      userId: userId,
      isOnline: true,
    );
  }

  void _persistLocation({
    required double latitude,
    required double longitude,
    required double heading,
    double speedMps = 0,
    required String userId,
    required bool isOnline,
  }) {
    final nextLocation = ll.LatLng(latitude, longitude);
    if (_status == DriverRideStatus.tripInProgress) {
      final previous = _lastTripLocation;
      if (previous != null) {
        final deltaMeters = Geolocator.distanceBetween(
          previous.latitude, previous.longitude,
          nextLocation.latitude, nextLocation.longitude,
        );
        // Ignore GPS jitter and impossible jumps; count only plausible movement.
        if (deltaMeters >= 5 && deltaMeters <= 500) {
          _tripDistance += deltaMeters;
        }
      }
      _lastTripLocation = nextLocation;
    }
    _currentLocation = nextLocation;
    _currentBearing = heading;
    final driverId = _db.auth.currentUser?.id;
    if (driverId == null || driverId != userId) return;
    if (isOnline && !isBlocked) {
      _db.rpc('sta_update_driver_location', params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_heading': heading >= 0 && heading < 360 ? heading : null,
        'p_speed_mps': speedMps >= 0 ? speedMps : null,
      }).then((_) {}).catchError((error) {
        debugPrint('Secure driver location update failed: $error');
      });
    } else {
      updateStatus(userId, 'offline', _currentLocation, _user?.vehicleType ?? 'Car');
    }
    notifyListeners();
  }

  void init(UserModel user) {
    if (_user?.id == user.id && _requestsSubscription != null) return;
    _user = user;
    _walletSubscription?.cancel();
    _walletSubscription = DatabaseService.instance.getWalletStream(user.id).listen((wallet) {
      _walletBalance = (wallet?['balance'] as num?)?.toDouble() ?? 0;
      if (isBlocked) updateStatus(user.id, 'offline', _currentLocation, user.vehicleType ?? 'Car');
      notifyListeners();
    }, onError: (e) => debugPrint('Wallet subscription error: $e'));
    if (user.isVerified && !isBlocked) {
      updateStatus(user.id, 'idle', _currentLocation, user.vehicleType ?? 'Car', region: user.region, city: user.city);
    }
    _listenForNewRequests(user);
  }

  void _listenForNewRequests(UserModel driver) {
    _requestsSubscription?.cancel();
    final start = DateTime.now().toUtc();
    final offeredRideIds = <String>{};
    _requestsSubscription = _db.from('ride_requests').stream(primaryKey: ['id'])
      .eq('status', 'requesting').listen((rows) async {
        final visibleIds = rows.map((row) => row['id'].toString()).toSet();
        offeredRideIds.removeWhere((id) => !visibleIds.contains(id));
        for (final row in rows) {
          final rideId = row['id']?.toString();
          if (rideId == null || offeredRideIds.contains(rideId)) continue;
          final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
          if (created == null || created.isBefore(start.subtract(const Duration(seconds: 5)))) continue;
          if (row['vehicle_type'] != Vehicle.getStandardizedType(driver.vehicleType ?? 'Car')) continue;
          if (_status != DriverRideStatus.idle || isBlocked || !driver.isVerified) continue;
          final rideData = row['ride_data'] is Map
              ? Map<String, dynamic>.from(row['ride_data'] as Map)
              : <String, dynamic>{};
          if (driver.region != null && rideData['region'] != null &&
              rideData['region'] != driver.region) continue;
          try {
            final matches = await _db.rpc('sta_nearby_drivers_v2', params: {
              'p_latitude': row['pickup_latitude'],
              'p_longitude': row['pickup_longitude'],
              'p_vehicle_type': row['vehicle_type'],
              'p_region': driver.region,
              'p_radius_meters': 15000,
            }) as List;
            final isMatched = matches.any((match) =>
                match is Map && match['driver_id']?.toString() == driver.id);
            if (!isMatched || _status != DriverRideStatus.idle || isBlocked) continue;
            offeredRideIds.add(rideId);
            final data = Map<String, dynamic>.from(row);
            data['rideId'] = rideId;
            SoundService.playNewRequest();
            _rideRequestController.add(data);
          } catch (error) {
            debugPrint('Smart driver matching failed for ride $rideId: $error');
          }
        }
      }, onError: (error) => debugPrint('Ride request stream error: $error'));
  }

  Future<bool> acceptRide(Map<String, dynamic> data, UserModel driverProfile) async {
    if (isBlocked) return false;
    SoundService.stopAll();
    final rideId = (data['rideId'] ?? data['id'])?.toString();
    if (rideId == null || rideId.isEmpty || _db.auth.currentUser == null) return false;
    try {
      final accepted = await _db.rpc('sta_accept_ride', params: {'p_ride_id': rideId});
      _currentRideData = Map<String, dynamic>.from(accepted as Map);
      _currentRideData!['id'] = rideId;
      final extra = _currentRideData!['ride_data'] is Map
          ? Map<String, dynamic>.from(_currentRideData!['ride_data']) : <String, dynamic>{};
      extra.addAll({
        'driverName': driverProfile.name, 'driverPhone': driverProfile.phoneNumber,
        'driverImage': driverProfile.profileImageUrl ?? '',
        'carModel': driverProfile.carModel ?? '', 'carPlate': driverProfile.carPlate ?? '',
        'carColor': driverProfile.carColor ?? 'BLUE', 'driverRating': driverProfile.rating,
      });
      _currentRideData!['ride_data'] = extra;
      _status = DriverRideStatus.pickingUp;
      SoundService.playDriverAccepted();
      await _listenToCurrentRide(rideId);
      _listenToMessages(_currentRideData!['rider_id']?.toString() ?? '');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Supabase ride acceptance failed: $e');
      return false;
    }
  }

  Future<void> _listenToCurrentRide(String rideId) async {
    await _currentRideSubscription?.cancel();
    _currentRideSubscription = _db.from('ride_requests').stream(primaryKey: ['id'])
      .eq('id', rideId).listen((rows) {
        if (rows.isEmpty || rows.first['status'] == 'cancelled') { _resetRide(); return; }
        _currentRideData = Map<String, dynamic>.from(rows.first);
        switch (_currentRideData!['status']) {
          case 'accepted': _status = DriverRideStatus.pickingUp; break;
          case 'driver_arrived': _status = DriverRideStatus.arrived; break;
          case 'in_progress': _status = DriverRideStatus.tripInProgress; break;
          case 'completed': _status = DriverRideStatus.waitingForPayment; break;
        }
        _paymentStatus = _currentRideData!['payment_status'];
        notifyListeners();
      }, onError: (e) => debugPrint('Current ride stream error: $e'));
  }

  Future<void> updateRideStatus(DriverRideStatus newStatus) async {
    if (_currentRideData == null) return;
    var value = 'accepted';
    if (newStatus == DriverRideStatus.arrived) value = 'driver_arrived';
    if (newStatus == DriverRideStatus.tripInProgress) value = 'in_progress';
    try {
      await _db.rpc('sta_set_ride_status', params: {
        'p_ride_id': _currentRideData!['id'],
        'p_status': value,
      });
      _status = newStatus;
      if (newStatus == DriverRideStatus.arrived) SoundService.playDriverArrived();
      if (newStatus == DriverRideStatus.tripInProgress) {
        _startTripCounters();
        SoundService.playTripStarted();
      }
    } catch (e) {
      debugPrint('Ride status update failed: $e');
      return;
    }
    notifyListeners();
  }

  void _startTripCounters() {
    _tripDistance = 0;
    _lastTripLocation = _currentLocation;
    _tripSeconds = 0;
    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_status == DriverRideStatus.tripInProgress) {
        _tripSeconds++;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> completeRide({required double fare, required double distance, required double duration}) async {
    if (_currentRideData == null) return;
    try {
      await _db.rpc('sta_set_ride_status', params: {
        'p_ride_id': _currentRideData!['id'],
        'p_status': 'completed',
        'p_fare': fare,
        'p_distance_meters': distance,
        'p_duration_seconds': duration.round(),
        'p_payment_status': 'pending',
      });
      _status = DriverRideStatus.waitingForPayment;
      notifyListeners();
    } catch (error) {
      debugPrint('Ride completion failed: $error');
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> confirmPaymentReceived() async {
    if (_currentRideData == null || _user == null) return;
    try {
      await _db.rpc('sta_set_ride_status', params: {
        'p_ride_id': _currentRideData!['id'],
        'p_status': 'completed',
        'p_payment_status': 'paid',
      });
      SoundService.playPaymentSuccess();
      _resetRide();
    } catch (error) {
      debugPrint('Payment confirmation failed: $error');
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> cancelRideByDriver(String reason) async {
    if (_currentRideData == null) return;
    await _db.rpc('sta_set_ride_status', params: {
      'p_ride_id': _currentRideData!['id'], 'p_status': 'cancelled',
      'p_cancellation_reason': reason,
    });
    _resetRide();
  }

  Future<void> _listenToMessages(String riderId) async {
    final driverId = _db.auth.currentUser?.id;
    if (driverId == null || riderId.isEmpty) return;
    final ids = [driverId, riderId]..sort();
    await _chatSubscription?.cancel();
    _chatSubscription = _db.from('chat_messages').stream(primaryKey: ['id'])
      .eq('chat_id', ids.join('_')).listen((rows) {
        if (rows.isEmpty) return;
        final row = rows.last;
        if (row['sender_id'] != driverId) {
          _lastMessage = ChatMessage(
            senderId: row['sender_id'] ?? '', senderName: row['sender_name'] ?? 'Rider',
            message: row['message'] ?? '', timestamp: DateTime.tryParse(row['created_at'] ?? ''),
          );
          notifyListeners();
        }
      });
  }

  void clearLastMessage() { _lastMessage = null; notifyListeners(); }

  Future<void> sendSos(String userId, ll.LatLng? location) async {
    if (location == null) return;
    await _db.from('sos_alerts').insert({
      'ride_id': _currentRideData?['id'], 'user_id': userId, 'role': 'driver',
      'latitude': location.latitude, 'longitude': location.longitude, 'status': 'active',
    });
  }

  void _resetRide() {
    _status = DriverRideStatus.idle;
    final id = _db.auth.currentUser?.id;
    if (id != null && _user?.isVerified == true && !isBlocked) {
      _db.rpc('sta_set_driver_presence', params: {
        'p_status': 'idle',
        'p_vehicle_type': Vehicle.getStandardizedType(_user?.vehicleType ?? 'Car'),
        'p_region': _user?.region,
        'p_city': _user?.city,
      }).then((_) {}).catchError((error) {
        debugPrint('Driver idle update failed: $error');
      });
    }
    _currentRideData = null; _tripTimer?.cancel(); _chatSubscription?.cancel();
    _currentRideSubscription?.cancel(); _tripDistance = 0; _lastTripLocation = null; _tripSeconds = 0;
    notifyListeners();
  }

  Future<void> _startLocationService() async {
    try {
      final service = FlutterBackgroundService();
      await _backgroundLocationSubscription?.cancel();
      _backgroundLocationSubscription = service.on('update').listen((event) {
        if (event == null || _user == null || isBlocked) return;
        _handleBackgroundLocation(Map<String, dynamic>.from(event));
      });
      if (!await service.isRunning()) {
        await service.startService();
      }
    } catch (e) {
      debugPrint('Background location service failed: $e');
    }
  }

  Future<void> _stopLocationService() async {
    await _backgroundLocationSubscription?.cancel();
    _backgroundLocationSubscription = null;
    FlutterBackgroundService().invoke('stopService');
  }

  void updateStatus(String userId, String status, ll.LatLng? location, String vehicleType, {String? region, String? city}) {
    final id = _db.auth.currentUser?.id;
    if (id == null) return;
    if (status == 'offline' || isBlocked) {
      _stopLocationService();
      _db.rpc('sta_set_driver_presence', params: {
        'p_status': 'offline',
        'p_vehicle_type': Vehicle.getStandardizedType(vehicleType),
        'p_region': region,
        'p_city': city,
      }).then((_) {}).catchError((error) {
        debugPrint('Driver offline update failed: $error');
      });
      return;
    }

    if (_user?.isVerified != true) {
      debugPrint('Unverified driver cannot go online.');
      return;
    }

    _startLocationService();
    final presenceStatus = status == 'on_trip' ? 'on_trip' : 'idle';
    _db.rpc('sta_set_driver_presence', params: {
      'p_status': presenceStatus,
      'p_vehicle_type': Vehicle.getStandardizedType(vehicleType),
      'p_region': region,
      'p_city': city,
    }).then((_) {}).catchError((error) {
      debugPrint('Driver presence update failed: $error');
    });
  }

  @override
  void dispose() {
    _tripTimer?.cancel(); _requestsSubscription?.cancel(); _chatSubscription?.cancel();
    _walletSubscription?.cancel(); _currentRideSubscription?.cancel();
    _backgroundLocationSubscription?.cancel();
    _rideRequestController.close(); super.dispose();
  }
}
