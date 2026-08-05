import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:sta/models/ride.dart';
import 'package:sta/models/vehicle.dart';
import 'package:sta/models/user.dart'; // ADDED
import 'package:sta/services/sound_service.dart';
import 'dart:async';

class ChatMessage {
  final String senderId;
  final String senderName;
  final String message;
  final DateTime? timestamp;

  ChatMessage({
    required this.senderId,
    required this.senderName,
    required this.message,
    this.timestamp,
  });
}

class RideProvider extends ChangeNotifier {
  StreamSubscription? _rideSubscription;
  StreamSubscription? _chatSubscription;
  Ride? _currentRide;
  bool _isLoading = false;
  String? _error;
  ll.LatLng? _driverLocation;
  double _driverBearing = 0;
  UserModel? _driverDetails; // CHANGED from Map
  Map<String, ll.LatLng> _nearbyDrivers = {};
  String? _userId;
  bool _isDriverFound = false;
  ChatMessage? _lastMessage; // CHANGED from Map

  StreamSubscription? _nearbyDriversSubscription;

  Ride? get currentRide => _currentRide;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ll.LatLng? get driverLocation => _driverLocation;
  double get driverBearing => _driverBearing;
  UserModel? get driverInfo => _driverDetails;
  Map<String, ll.LatLng> get nearbyDrivers => _nearbyDrivers;
  bool get isDriverFound => _isDriverFound;
  ChatMessage? get lastMessage => _lastMessage;

  RideProvider();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void initializeConnection(String userId) {
    _userId = userId;
  }

  void findNearbyDrivers(
      {required double lat,
      required double lng,
      String? vehicleType,
      String? region}) {
    _nearbyDriversSubscription?.cancel();
    var query = FirebaseFirestore.instance
        .collection('drivers_online')
        .where('status', isEqualTo: 'idle');

    if (vehicleType != null && vehicleType != 'All') {
      final String standardizedType = Vehicle.getStandardizedType(vehicleType);
      query = query.where('vehicleType', isEqualTo: standardizedType);
    }

    // Chujio la mkoa
    if (region != null && region.isNotEmpty) {
      query = query.where('region', isEqualTo: region);
    }

    _nearbyDriversSubscription = query.snapshots().listen(
      (snapshot) {
        Map<String, ll.LatLng> drivers = {};
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['lat'] != null && data['lng'] != null) {
            drivers[doc.id] = ll.LatLng(
              (data['lat'] as num).toDouble(),
              (data['lng'] as num).toDouble(),
            );
          }
        }
        _nearbyDrivers = drivers;
        notifyListeners();
      },
      onError: (error) {
        debugPrint("Drivers Stream Error (Safe Skip): $error");
      },
    );
  }

  Future<bool> requestRide({
    required String userId,
    required String riderName,
    required String riderPhone,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    String? region,
    String? city,
    String vehicleType = 'Car',
    double fare = 0.0,
    bool femaleOnly = false,
    String? pickupImage,
    String? riderImage,
    bool isGuestRide = false,
    String? guestName,
    String? guestPhone,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final rideId = DateTime.now().millisecondsSinceEpoch.toString();
      final standardVehicleType = Vehicle.getStandardizedType(vehicleType);

      // HAKIKISHA: Tunatumia userId kutoka Firebase Auth moja kwa moja kama inawezekana
      final String effectiveUserId = userId.isEmpty ? (_userId ?? '') : userId;

      if (effectiveUserId.isEmpty) {
        throw Exception("Mtumiaji hayatambulika. Tafadhali login tena.");
      }

      final rideData = {
        'id': rideId,
        'riderId': effectiveUserId,
        'riderName': riderName,
        'riderPhone': riderPhone,
        'riderImage': riderImage ?? '',
        'pickup': {'lat': pickupLat, 'lng': pickupLng},
        'dropoff': {'lat': dropoffLat, 'lng': dropoffLng},
        'pickupAddress': pickupAddress,
        'dropoffAddress': dropoffAddress,
        'region': region ?? "Arusha",
        'city': city ?? "Arusha",
        'vehicleType': standardVehicleType,
        'status': 'requesting',
        'fare': fare,
        'femaleOnly': femaleOnly,
        'pickupImage': pickupImage,
        'isGuestRide': isGuestRide,
        'guestName': guestName,
        'guestPhone': guestPhone,
        'createdAt': FieldValue.serverTimestamp(),
        'userId': effectiveUserId, // Muhimu kwa rules
      };

      await FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(rideId)
          .set(rideData);

      _currentRide = Ride(
        id: rideId,
        passengerId: effectiveUserId,
        driverId: '',
        pickupLocation: Location(
            latitude: pickupLat, longitude: pickupLng, address: pickupAddress),
        dropoffLocation: Location(
            latitude: dropoffLat,
            longitude: dropoffLng,
            address: dropoffAddress),
        fare: fare,
        distance: 0.0,
        duration: 0,
        vehicleType: vehicleType,
        status: RideStatus.requesting,
        createdAt: DateTime.now(),
        paymentMethod: PaymentMethod.cash,
        isGuestRide: isGuestRide,
        guestName: guestName,
        guestPhone: guestPhone,
      );

      _listenToRide(rideId);
      _setLoading(false);
      return true;
    } catch (e) {
      _error = e.toString();
      _setLoading(false);
      return false;
    }
  }

  void _listenToRide(String rideId) {
    _rideSubscription?.cancel();
    _rideSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(rideId)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          final status = data['status'];

          if (data['driverLat'] != null && data['driverLng'] != null) {
            double lat = (data['driverLat'] as num).toDouble();
            double lng = (data['driverLng'] as num).toDouble();
            
            if (lat.isFinite && lng.isFinite) {
              _driverLocation = ll.LatLng(lat, lng);
              _driverBearing = (data['driverBearing'] as num?)?.toDouble() ?? 0.0;
            }
          }

          if (status == 'accepted' && !_isDriverFound) {
            _isDriverFound = true;
            SoundService.playDriverAccepted();
            SoundService.playDriverAccepted();

            _driverDetails = UserModel(
              id: data['driverId'] ?? '',
              name: data['driverName'] ?? 'Driver',
              email: '',
              phoneNumber: data['driverPhone'] ?? '',
              profileImageUrl:
                  data['driverImage'] ?? data['driverProfileImage'] ?? '',
              role: UserRole.driver,
              rating: (data['driverRating'] as num?)?.toDouble() ?? 5.0,
              driverLevel: data['driverLevel'] ?? 'Bronze',
              carModel: data['carModel'] ?? 'Vehicle',
              carPlate: data['carPlate'] ?? '',
              carColor: data['carColor'] ?? 'BLUE',
              createdAt: DateTime.now(),
            );

            _currentRide = _currentRide?.copyWith(
                status: RideStatus.accepted,
                driverId: data['driverId'],
                vehicleType: data['vehicleType']);

            _listenToMessages(data['driverId']);
          } else if (status == 'accepted' || status == 'picked_up') {
            _currentRide = _currentRide?.copyWith(
                status: status == 'picked_up'
                    ? RideStatus.inProgress
                    : RideStatus.accepted);
          } else if (status == 'arrived') {
            _currentRide = _currentRide?.copyWith(status: RideStatus.arrived);
            SoundService.playDriverArrived();
          } else if (status == 'started') {
            _currentRide = _currentRide?.copyWith(status: RideStatus.inProgress);
            SoundService.playTripStarted();
          } else if (status == 'completed') {
            _currentRide = _currentRide?.copyWith(
              status: RideStatus.completed,
              fare: (data['fare'] as num?)?.toDouble(),
              distance: (data['distance'] as num?)?.toDouble(),
              paymentStatus: data['paymentStatus'],
            );
            SoundService.playPaymentSuccess();
          } else if (status == 'cancelled') {
            clearRide();
          }
          notifyListeners();
        }
      },
      onError: (e) => debugPrint("Ride Stream Error: $e"),
    );
  }

  Future<void> startRide() async {
    if (_currentRide != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(_currentRide!.id)
            .update({'status': 'started'});
      } catch (e) {
        debugPrint("Start Ride Error: $e");
      }
    }
  }

  Future<void> cancelRide() async {
    if (_currentRide != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(_currentRide!.id)
            .update({'status': 'cancelled'});
        clearRide();
      } catch (e) {
        debugPrint("Cancel Error: $e");
      }
    }
  }

  Future<void> sendMessage(
      String receiverId, String message, String senderName) async {
    if (_userId == null) return;
    List<String> ids = [_userId!, receiverId];
    ids.sort();
    final chatId = ids.join('_');

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': _userId,
        'receiverId': receiverId,
        'message': message,
        'senderName': senderName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Chat Error: $e");
    }
  }

  void _listenToMessages(String driverId) {
    if (_userId == null) return;
    List<String> ids = [_userId!, driverId];
    ids.sort();
    final chatId = ids.join('_');

    final startTime = Timestamp.now();

    _chatSubscription?.cancel();
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('timestamp', isGreaterThan: startTime)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          if (data['senderId'] != _userId) {
            _lastMessage = ChatMessage(
              senderId: data['senderId'] ?? '',
              senderName: data['senderName'] ?? 'Driver',
              message: data['message'] ?? '',
              timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
            );
            notifyListeners();
          }
        }
      }
    });
  }

  void clearLastMessage() {
    _lastMessage = null;
    notifyListeners();
  }

  void sendSos(String userId, ll.LatLng? location) {
    if (_currentRide != null) {
      FirebaseFirestore.instance.collection('sos_alerts').add({
        'rideId': _currentRide!.id,
        'userId': userId,
        'role': 'rider',
        'location': {'lat': location?.latitude, 'lng': location?.longitude},
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active', // Added for Admin Real-time Tracking
      });
      debugPrint("🆘 SOS Alert sent to Firestore");
    }
  }

  Future<void> updatePaymentStatus(String status) async {
    if (_currentRide != null) {
      try {
        await FirebaseFirestore.instance
            .collection('ride_requests')
            .doc(_currentRide!.id)
            .update({'paymentStatus': status});
      } catch (e) {
        debugPrint("Payment Update Error: $e");
      }
    }
  }

  Future<void> submitRating({
    required String rideId,
    required String targetId,
    required int rating,
    required String comment,
    required String role,
    String? riderName,
    String? driverId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('ratings').add({
        'rideId': rideId,
        'rating': rating,
        'comment': comment,
        'fromRole': role,
        'targetId': targetId,
        'riderName': riderName,
        'driverId': driverId ?? (role == 'rider' ? targetId : null),
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update target's overall rating
      final String collection = role == 'driver' ? 'riders' : 'drivers';
      final docRef =
          FirebaseFirestore.instance.collection(collection).doc(targetId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (snapshot.exists) {
          final data = snapshot.data()!;
          double currentRating = (data['rating'] as num?)?.toDouble() ?? 5.0;
          int totalRides = (data['totalRides'] as int?) ?? 1;

          double newRating =
              ((currentRating * totalRides) + rating) / (totalRides + 1);

          transaction.update(docRef, {
            'rating': newRating,
            'totalRides': totalRides + 1,
          });
        }
      });
    } catch (e) {
      debugPrint("Rating Error: $e");
    }
  }

  void clearRide() {
    _currentRide = null;
    _driverLocation = null;
    _driverDetails = null;
    _isDriverFound = false;
    _rideSubscription?.cancel();
    _chatSubscription?.cancel(); // ADDED
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _chatSubscription?.cancel();
    _nearbyDriversSubscription?.cancel();
    super.dispose();
  }
}
