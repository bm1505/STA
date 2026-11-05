import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sta/models/ride.dart';
import 'package:sta/models/vehicle.dart';
import 'package:sta/models/user.dart';
import 'package:sta/services/sound_service.dart';

class ChatMessage {
  final String senderId;
  final String senderName;
  final String message;
  final DateTime? timestamp;
  ChatMessage({required this.senderId, required this.senderName,
    required this.message, this.timestamp});
}

class RideProvider extends ChangeNotifier {
  SupabaseClient get _db => Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _rideSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _chatSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _nearbyDriversSubscription;
  Ride? _currentRide;
  bool _isLoading = false;
  String? _error;
  ll.LatLng? _driverLocation;
  double _driverBearing = 0;
  UserModel? _driverDetails;
  Map<String, ll.LatLng> _nearbyDrivers = {};
  String? _userId;
  bool _isDriverFound = false;
  ChatMessage? _lastMessage;

  Ride? get currentRide => _currentRide;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ll.LatLng? get driverLocation => _driverLocation;
  double get driverBearing => _driverBearing;
  UserModel? get driverInfo => _driverDetails;
  Map<String, ll.LatLng> get nearbyDrivers => _nearbyDrivers;
  bool get isDriverFound => _isDriverFound;
  ChatMessage? get lastMessage => _lastMessage;

  void _setLoading(bool value) { _isLoading = value; notifyListeners(); }
  void initializeConnection(String userId) { _userId = userId; }

  Future<void> findNearbyDrivers({required double lat, required double lng,
    String? vehicleType, String? region}) async {
    await _nearbyDriversSubscription?.cancel();
    try {
      final rows = await _db.rpc('sta_nearby_drivers_v2', params: {
        'p_latitude': lat, 'p_longitude': lng,
        'p_vehicle_type': vehicleType == null || vehicleType == 'All'
            ? null : Vehicle.getStandardizedType(vehicleType),
        'p_region': region,
        'p_radius_meters': 15000,
      });
      _nearbyDrivers = {
        for (final row in (rows as List))
          if (row['driver_id'] != null && row['latitude'] != null && row['longitude'] != null)
            row['driver_id'].toString(): ll.LatLng(
              (row['latitude'] as num).toDouble(),
              (row['longitude'] as num).toDouble(),
            )
      };
      notifyListeners();
    } catch (e) {
      debugPrint('Nearby driver lookup failed: $e');
    }
  }

  Future<bool> requestRide({
    required String userId, required String riderName, required String riderPhone,
    required double pickupLat, required double pickupLng, required String pickupAddress,
    required double dropoffLat, required double dropoffLng, required String dropoffAddress,
    required double distanceMeters, required int durationSeconds,
    String? region, String? city, String vehicleType = 'Car',
    bool femaleOnly = false, String? pickupImage, String? riderImage,
    bool isGuestRide = false, String? guestName, String? guestPhone,
  }) async {
    _setLoading(true); _error = null;
    try {
      final effectiveUserId = userId.isEmpty ? (_userId ?? '') : userId;
      if (effectiveUserId.isEmpty || _db.auth.currentUser?.id != effectiveUserId) {
        throw Exception('Mtumiaji hayatambuliki. Tafadhali ingia tena.');
      }
      if (distanceMeters <= 0 || durationSeconds <= 0) {
        throw StateError('Njia na muda wa safari lazima vikadiriwe kabla ya kuomba safari.');
      }
      final result = await _db.rpc('sta_create_ride_request', params: {
        'p_pickup_latitude': pickupLat,
        'p_pickup_longitude': pickupLng,
        'p_pickup_label': pickupAddress,
        'p_dropoff_latitude': dropoffLat,
        'p_dropoff_longitude': dropoffLng,
        'p_dropoff_label': dropoffAddress,
        'p_vehicle_type': Vehicle.getStandardizedType(vehicleType),
        'p_distance_meters': distanceMeters,
        'p_duration_seconds': durationSeconds,
        'p_ride_data': {
          'riderImage': riderImage,
          'region': region == null || region.trim().isEmpty ? null : region.trim(),
          'city': city == null || city.trim().isEmpty ? null : city.trim(),
          'femaleOnly': femaleOnly, 'pickupImage': pickupImage,
          'isGuestRide': isGuestRide, 'guestName': guestName, 'guestPhone': guestPhone,
        },
      });
      if (result is! Map) throw StateError('Server did not return the created ride.');
      final row = Map<String, dynamic>.from(result);
      final id = row['id'].toString();
      final serverFare = (row['estimated_fare'] as num?)?.toDouble();
      if (serverFare == null || serverFare <= 0) {
        throw StateError('Server did not return a valid fare estimate.');
      }
      _currentRide = Ride(
        id: id, passengerId: effectiveUserId, driverId: '',
        pickupLocation: Location(latitude: pickupLat, longitude: pickupLng, address: pickupAddress),
        dropoffLocation: Location(latitude: dropoffLat, longitude: dropoffLng, address: dropoffAddress),
        fare: serverFare, distance: distanceMeters / 1000, duration: (durationSeconds / 60).round(), vehicleType: vehicleType,
        status: RideStatus.requesting, createdAt: DateTime.parse(row['created_at'].toString()),
        paymentMethod: PaymentMethod.cash, isGuestRide: isGuestRide,
        guestName: guestName, guestPhone: guestPhone,
      );
      _listenToRide(id);
      await findNearbyDrivers(
        lat: pickupLat,
        lng: pickupLng,
        vehicleType: vehicleType,
        region: region == null || region.trim().isEmpty ? null : region.trim(),
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _error = e.toString(); _setLoading(false); return false;
    }
  }

  void _listenToRide(String rideId) {
    _rideSubscription?.cancel();
    _rideSubscription = _db.from('ride_requests').stream(primaryKey: ['id'])
      .eq('id', rideId).listen((rows) {
        if (rows.isEmpty) { clearRide(); return; }
        final data = rows.first;
        final extra = data['ride_data'] is Map
            ? Map<String, dynamic>.from(data['ride_data']) : <String, dynamic>{};
        final status = data['status'];
        final lat = data['driver_latitude'];
        final lng = data['driver_longitude'];
        if (lat != null && lng != null) {
          _driverLocation = ll.LatLng((lat as num).toDouble(), (lng as num).toDouble());
          _driverBearing = (data['driver_heading'] as num?)?.toDouble() ?? 0;
        }
        if (data['driver_id'] != null && !_isDriverFound) {
          _isDriverFound = true;
          _driverDetails = UserModel(
            id: data['driver_id'].toString(),
            name: extra['driverName'] ?? 'Driver', email: '',
            phoneNumber: extra['driverPhone'] ?? '',
            profileImageUrl: extra['driverImage'] ?? '',
            role: UserRole.driver,
            rating: (extra['driverRating'] as num?)?.toDouble() ?? 5,
            carModel: extra['carModel'] ?? 'Vehicle',
            carPlate: extra['carPlate'] ?? '',
            carColor: extra['carColor'] ?? 'BLUE',
            createdAt: DateTime.now(),
          );
          SoundService.playDriverAccepted();
          _listenToMessages(data['driver_id'].toString());
        }
        final mappedStatus = switch (status) {
          'requesting' => RideStatus.requesting,
          'accepted' => RideStatus.accepted,
          'driver_arrived' => RideStatus.arrived,
          'in_progress' => RideStatus.inProgress,
          'completed' => RideStatus.completed,
          'cancelled' => RideStatus.cancelled,
          _ => _currentRide?.status ?? RideStatus.requesting,
        };
        _currentRide = _currentRide?.copyWith(
          status: mappedStatus, driverId: data['driver_id']?.toString(),
          fare: (data['final_fare'] as num?)?.toDouble() ??
              (data['estimated_fare'] as num?)?.toDouble(),
          paymentStatus: data['payment_status'],
        );
        if (status == 'driver_arrived') SoundService.playDriverArrived();
        if (status == 'in_progress') SoundService.playTripStarted();
        if (status == 'completed') SoundService.playPaymentSuccess();
        if (status == 'cancelled') { clearRide(); return; }
        notifyListeners();
      }, onError: (e) => debugPrint('Ride realtime error: $e'));
  }

  // Ride status transitions are controlled by the assigned driver through sta_set_ride_status.
  Future<void> startRide() async {
    debugPrint('Only the assigned driver can start a ride.');
  }

  Future<void> cancelRide() async {
    if (_currentRide == null) return;
    try {
      await _db.rpc('sta_set_ride_status', params: {'p_ride_id': _currentRide!.id, 'p_status': 'cancelled'});
      clearRide();
    } catch (e) { debugPrint('Cancel ride failed: $e'); }
  }

  Future<void> sendMessage(String receiverId, String message, String senderName) async {
    if (_userId == null) return;
    final ids = [_userId!, receiverId]..sort();
    try {
      await _db.from('chat_messages').insert({
        'chat_id': ids.join('_'), 'sender_id': _userId,
        'receiver_id': receiverId, 'sender_name': senderName, 'message': message,
      });
    } catch (e) { debugPrint('Chat send failed: $e'); }
  }

  void _listenToMessages(String driverId) {
    if (_userId == null) return;
    final ids = [_userId!, driverId]..sort();
    final chatId = ids.join('_');
    _chatSubscription?.cancel();
    _chatSubscription = _db.from('chat_messages').stream(primaryKey: ['id'])
      .eq('chat_id', chatId).listen((rows) {
        if (rows.isEmpty) return;
        final sorted = [...rows]..sort((a,b) => (DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970)).compareTo(DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970)));
        final data = sorted.last;
        if (data['sender_id'] != _userId) {
          _lastMessage = ChatMessage(
            senderId: data['sender_id'] ?? '', senderName: data['sender_name'] ?? 'Driver',
            message: data['message'] ?? '',
            timestamp: DateTime.tryParse(data['created_at'] ?? ''),
          );
          notifyListeners();
        }
      });
  }

  void clearLastMessage() { _lastMessage = null; notifyListeners(); }

  Future<void> sendSos(String userId, ll.LatLng? location) async {
    if (location == null) return;
    await _db.from('sos_alerts').insert({
      'ride_id': _currentRide?.id, 'user_id': userId, 'role': 'rider',
      'latitude': location.latitude, 'longitude': location.longitude,
      'status': 'active',
    });
  }

  Future<void> updatePaymentStatus(String status) async {
    if (_currentRide == null) return;
    await _db.rpc('sta_set_ride_status', params: {'p_ride_id': _currentRide!.id, 'p_status': 'completed', 'p_payment_status': status});
  }

  Future<void> submitRating({
    required String rideId, required String targetId, required int rating,
    required String comment, required String role, String? riderName, String? driverId,
  }) async {
    await _db.from('ride_ratings').insert({
      'ride_id': rideId, 'target_user_id': targetId, 'rating': rating,
      'comment': comment, 'from_role': role, 'rider_name': riderName,
      'driver_id': driverId,
    });
  }

  void clearRide() {
    _currentRide = null; _driverLocation = null; _driverDetails = null;
    _isDriverFound = false; _rideSubscription?.cancel(); _chatSubscription?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel(); _chatSubscription?.cancel();
    _nearbyDriversSubscription?.cancel(); super.dispose();
  }
}
