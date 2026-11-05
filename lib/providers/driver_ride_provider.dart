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

  double _calculateCurrentFare() {
    final base = (_currentRideData?['estimated_fare'] as num?)?.toDouble() ??
        (_currentRideData?['final_fare'] as num?)?.toDouble() ?? 3000;
    if (_status != DriverRideStatus.tripInProgress &&
        _status != DriverRideStatus.waitingForPayment) return base;
    final total = base + (_tripDistance / 1000 * 1000) + (_tripSeconds / 60 * 150);
    return (total / 100).round() * 100.0;
  }

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
      userId: userId,
      isOnline: true,
    );
  }

  void _persistLocation({
    required double latitude,
    required double longitude,
    required double heading,
    required String userId,
    required bool isOnline,
  }) {
    _currentLocation = ll.LatLng(latitude, longitude);
    _currentBearing = heading;
    final driverId = _db.auth.currentUser?.id;
    if (driverId == null || driverId != userId) return;
    if (_currentRideData != null) {
      _db.from('ride_requests').update({
        'driver_latitude': latitude,
        'driver_longitude': longitude,
        'driver_heading': heading,
      }).eq('id', _currentRideData!['id'].toString()).then((_) {});
    }
    if (isOnline && !isBlocked) {
      _db.from('driver_locations').upsert({
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'heading': heading,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      }).then((_) {});
      _db.from('driver_profiles').update({
        'is_online': true,
        'availability_status': _status == DriverRideStatus.idle ? 'idle' : 'on_trip',
        'vehicle_type': Vehicle.getStandardizedType(_user?.vehicleType ?? 'Car'),
        'region': _user?.region,
        'city': _user?.city,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', driverId).then((_) {});
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
    final vehicle = Vehicle.getStandardizedType(driver.vehicleType ?? 'Car');
    final start = DateTime.now().toUtc();
    _requestsSubscription = _db.from('ride_requests').stream(primaryKey: ['id'])
      .eq('status', 'requesting').listen((rows) {
        for (final row in rows) {
          if (row['vehicle_type'] != vehicle) continue;
          final created = DateTime.tryParse(row['created_at'] ?? '');
          if (created == null || created.isBefore(start.subtract(const Duration(seconds: 5)))) continue;
          if (driver.region != null && row['ride_data'] is Map &&
              row['ride_data']['region'] != null &&
              row['ride_data']['region'] != driver.region) continue;
          if (_status == DriverRideStatus.idle && !isBlocked) {
            final data = Map<String, dynamic>.from(row);
            data['rideId'] = row['id'];
            SoundService.playNewRequest();
            _rideRequestController.add(data);
          }
        }
      }, onError: (e) => debugPrint('Ride request stream error: $e'));
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
    _status = newStatus;
    if (_currentRideData == null) return;
    var value = 'accepted';
    if (newStatus == DriverRideStatus.arrived) { value = 'driver_arrived'; SoundService.playDriverArrived(); }
    if (newStatus == DriverRideStatus.tripInProgress) { value = 'in_progress'; _startTripCounters(); SoundService.playTripStarted(); }
    try {
      await _db.rpc('sta_set_ride_status', params: {'p_ride_id': _currentRideData!['id'], 'p_status': value});
    } catch (e) { debugPrint('Ride status update failed: $e'); }
    notifyListeners();
  }

  void _startTripCounters() {
    _tripSeconds = 0; _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_status == DriverRideStatus.tripInProgress) { _tripSeconds++; notifyListeners(); }
      else { timer.cancel(); }
    });
  }

  Future<void> completeRide({required double fare, required double distance, required double duration}) async {
    if (_currentRideData == null) return;
    await _db.rpc('sta_set_ride_status', params: {
      'p_ride_id': _currentRideData!['id'], 'p_status': 'completed',
      'p_fare': fare, 'p_distance_meters': distance,
      'p_duration_seconds': duration.round(), 'p_payment_status': 'pending',
    });
    _status = DriverRideStatus.waitingForPayment;
    notifyListeners();
  }

  Future<void> confirmPaymentReceived() async {
    if (_currentRideData == null || _user == null) { _resetRide(); return; }
    try {
      SoundService.playPaymentSuccess();
      final trip = Map<String, dynamic>.from(_currentRideData!);
      trip['id'] = _currentRideData!['id'];
      trip['driverId'] = _user!.id;
      trip['fare'] = _currentRideData!['final_fare'];
      trip['paymentStatus'] = 'paid';
      trip['status'] = 'paid';
      await _db.rpc('sta_set_ride_status', params: {
        'p_ride_id': _currentRideData!['id'], 'p_status': 'completed',
        'p_payment_status': 'paid',
      });
      await DatabaseService.instance.recordTrip(trip);
      await DatabaseService.instance.incrementDriverRides(_user!.id);
    } catch (e) { debugPrint('Payment confirmation failed: $e'); }
    finally { _resetRide(); }
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
    if (id != null) {
      _db.from('driver_profiles').update({'availability_status': 'idle'}).eq('user_id', id).then((_) {});
    }
    _currentRideData = null; _tripTimer?.cancel(); _chatSubscription?.cancel();
    _currentRideSubscription?.cancel(); _tripDistance = 0; _tripSeconds = 0;
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
      _db.from('driver_profiles').update({
        'is_online': false, 'availability_status': 'offline',
      }).eq('user_id', id).then((_) {});
      _db.from('driver_locations').delete().eq('driver_id', id).then((_) {});
      return;
    }
    _startLocationService();
    _db.from('driver_profiles').upsert({
      'user_id': id, 'is_online': true, 'availability_status': status,
      'vehicle_type': Vehicle.getStandardizedType(vehicleType),
      'verification_status': _user?.isVerified == true ? 'verified' : 'pending',
      'region': region, 'city': city,
    }).then((_) {});
    if (location != null) {
      _db.from('driver_locations').upsert({
        'driver_id': id, 'latitude': location.latitude, 'longitude': location.longitude,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      }).then((_) {});
    }
  }

  @override
  void dispose() {
    _tripTimer?.cancel(); _requestsSubscription?.cancel(); _chatSubscription?.cancel();
    _walletSubscription?.cancel(); _currentRideSubscription?.cancel();
    _backgroundLocationSubscription?.cancel();
    _rideRequestController.close(); super.dispose();
  }
}
