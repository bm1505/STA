import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:sta/services/database_service.dart';
import 'package:sta/models/user.dart';
import 'package:sta/models/vehicle.dart';
import 'package:sta/providers/ride_provider.dart';
import 'package:sta/services/sound_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

enum DriverRideStatus {
  idle,
  pickingUp,
  arrived,
  tripInProgress,
  waitingForPayment
}

class DriverRideProvider extends ChangeNotifier {
  StreamSubscription? _requestsSubscription;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _currentRideSubscription;
  UserModel? _user;
  DriverRideStatus _status = DriverRideStatus.idle;
  Map<String, dynamic>? _currentRideData;
  ll.LatLng? _currentLocation;
  double _currentBearing = 0;
  ChatMessage? _lastMessage;
  double _walletBalance = 0.0;
  StreamSubscription? _walletSubscription;
  static const double DEBT_THRESHOLD = -20000.0;

  double _tripDistance = 0.0;
  int _tripSeconds = 0;
  Timer? _tripTimer;
  String? _paymentStatus;

  UserModel? get user => _user;
  DriverRideStatus get status => _status;
  Map<String, dynamic>? get currentRideData => _currentRideData;
  double get tripDistance => _tripDistance;
  int get tripSeconds => _tripSeconds;
  ll.LatLng? get currentLocation => _currentLocation;
  double get walletBalance => _walletBalance;
  bool get isBlocked => _walletBalance < DEBT_THRESHOLD;

  double get distanceToPickup {
    if (_currentLocation == null || pickupLatLng == null) return 0.0;
    return Geolocator.distanceBetween(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          pickupLatLng!.latitude,
          pickupLatLng!.longitude,
        ) /
        1000;
  }

  double get distanceToDestination {
    if (_currentLocation == null || dropoffLatLng == null) return 0.0;
    return Geolocator.distanceBetween(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          dropoffLatLng!.latitude,
          dropoffLatLng!.longitude,
        ) /
        1000;
  }

  double get currentFare => _calculateCurrentFare();
  ChatMessage? get lastMessage => _lastMessage;
  String? get paymentStatus => _paymentStatus;

  double _calculateCurrentFare() {
    if (_currentRideData != null && _currentRideData!.containsKey('fare')) {
      double base = (_currentRideData!['fare'] as num).toDouble();
      if (_status != DriverRideStatus.tripInProgress &&
          _status != DriverRideStatus.waitingForPayment) {
        return base;
      }
      double kmRate = 1000.0;
      double minRate = 150.0;
      double distanceKm = _tripDistance / 1000;
      double durationMin = _tripSeconds / 60;
      double total = base + (distanceKm * kmRate) + (durationMin * minRate);
      return (total / 100).round() * 100.0;
    }
    return 3000.0; // Fallback
  }

  void updateLocation(Position position, String userId, bool isOnline) {
    _currentLocation = ll.LatLng(position.latitude, position.longitude);
    _currentBearing = position.heading;

    if (_status != DriverRideStatus.idle && _currentRideData != null) {
      FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(_currentRideData!['rideId'].toString())
          .update({
        'driverLat': position.latitude,
        'driverLng': position.longitude,
        'driverBearing': position.heading,
      }).catchError((e) => debugPrint("❌ Error location update: $e"));
    }

    if (isOnline) {
      final String? authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid != null) {
        if (isBlocked) {
          // If blocked, remove from online pool immediately
          FirebaseFirestore.instance.collection('drivers_online').doc(authUid).delete();
          FirebaseFirestore.instance.collection('drivers').doc(authUid).set({'isOnline': false}, SetOptions(merge: true));
        } else {
          // Sync online status to both collections
          FirebaseFirestore.instance.collection('drivers_online').doc(authUid).set({
            'id': authUid,
            'lat': position.latitude,
            'lng': position.longitude,
            'status': _status == DriverRideStatus.idle ? 'idle' : 'busy',
            'vehicleType': Vehicle.getStandardizedType(_user?.vehicleType ?? 'Car'),
            'region': _user?.region,
            'city': _user?.city,
            'lastUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          FirebaseFirestore.instance.collection('drivers').doc(authUid).set({
            'isOnline': true,
            'lastUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    }
    notifyListeners();
  }

  ll.LatLng? get pickupLatLng {
    if (_currentRideData == null || _currentRideData!['pickup'] == null) return null;
    var p = _currentRideData!['pickup'];
    if (p is String) p = json.decode(p);
    return ll.LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
  }

  ll.LatLng? get dropoffLatLng {
    if (_currentRideData == null || _currentRideData!['dropoff'] == null) return null;
    var d = _currentRideData!['dropoff'];
    if (d is String) d = json.decode(d);
    return ll.LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
  }

  final _rideRequestController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get rideRequestStream => _rideRequestController.stream;

  void init(UserModel user) {
    if (_user?.id == user.id && _requestsSubscription != null) return;
    _user = user;
    
    // Anza kufuatilia wallet balance kwa umakini zaidi
    _walletSubscription?.cancel();
    _walletSubscription = DatabaseService.instance.getWalletStream(user.id).listen((wallet) {
      if (wallet != null) {
        final double oldBalance = _walletBalance;
        _walletBalance = (wallet['balance'] as num?)?.toDouble() ?? 0.0;
        
        // Ikiwa amevuka threshold sasa hivi na yupo online, mtoe online
        if (_walletBalance < DEBT_THRESHOLD && oldBalance >= DEBT_THRESHOLD) {
          final String? authUid = FirebaseAuth.instance.currentUser?.uid;
          if (authUid != null) {
            FirebaseFirestore.instance.collection('drivers_online').doc(authUid).delete();
            FirebaseFirestore.instance.collection('drivers').doc(authUid).set({'isOnline': false}, SetOptions(merge: true));
          }
        }
        notifyListeners();
      }
    }, onError: (e) => debugPrint("Wallet subscription error: $e"));

    if (user.isVerified && !isBlocked) {
      updateStatus(user.id, 'idle', _currentLocation, user.vehicleType ?? 'Car', 
          region: user.region, city: user.city);
    }
    _listenForNewRequests(user);
  }

  void _listenForNewRequests(UserModel driver) {
    _requestsSubscription?.cancel();
    final String standardizedType = Vehicle.getStandardizedType(driver.vehicleType ?? 'Car');
    final DateTime listenerStartTime = DateTime.now();

    _requestsSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', isEqualTo: 'requesting')
        .where('vehicleType', isEqualTo: standardizedType)
        .snapshots()
        .listen((snapshot) {
      final now = DateTime.now();
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;
          final String rideId = change.doc.id;
          
          DateTime? rideTime;
          if (data['createdAt'] is Timestamp) {
            rideTime = (data['createdAt'] as Timestamp).toDate();
          } else {
            final int? idTs = int.tryParse(rideId);
            if (idTs != null && idTs > 1000000000000) rideTime = DateTime.fromMillisecondsSinceEpoch(idTs);
          }

          if (rideTime == null || rideTime.isBefore(listenerStartTime.subtract(const Duration(seconds: 5)))) continue;
          if (rideTime.isAfter(now.add(const Duration(seconds: 60)))) continue;
          if (driver.region != null && data['region'] != null && data['region'] != driver.region) continue;

          if (_status == DriverRideStatus.idle) {
            final mutableData = Map<String, dynamic>.from(data);
            mutableData['rideId'] = rideId;
            SoundService.playNewRequest();
            _rideRequestController.add(mutableData);
          }
        }
      }
    });
  }

  Future<bool> acceptRide(Map<String, dynamic> data, UserModel driverProfile) async {
    if (isBlocked) return false;
    
    // MUHIMU KWA SIMU NDOGO (A04): Zima sauti zote mara moja kutoa nafasi ya RAM
    SoundService.stopAll();

    final String? rideId = data['rideId']?.toString();
    final String? riderId = data['riderId']?.toString();
    
    if (rideId == null || rideId.isEmpty) {
      debugPrint("❌ Error: rideId is null or empty");
      return false;
    }

    final rideRef = FirebaseFirestore.instance.collection('ride_requests').doc(rideId);
    final String? authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) return false;

    try {
      bool success = await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(rideRef);
        if (!snapshot.exists) return false;
        
        final rideData = snapshot.data() as Map<String, dynamic>;
        if (rideData['status'] != 'requesting') return false;

        transaction.update(rideRef, {
          'status': 'accepted',
          'driverId': authUid,
          'driverName': driverProfile.name,
          'driverPhone': driverProfile.phoneNumber,
          'driverImage': driverProfile.profileImageUrl ?? '',
          'carModel': driverProfile.carModel ?? '',
          'carPlate': driverProfile.carPlate ?? '',
          'carColor': driverProfile.carColor ?? 'BLUE',
          'driverRating': driverProfile.rating,
          'driverLat': _currentLocation?.latitude,
          'driverLng': _currentLocation?.longitude,
          'driverBearing': _currentBearing,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
        return true;
      }, timeout: const Duration(seconds: 8));

      if (success) {
        // 1. Play sound
        SoundService.playDriverAccepted();

        // 2. Hifadhi data lakini USIBADILI status bado (UI isirebuild sasa hivi)
        _currentRideData = Map<String, dynamic>.from(data);
        _currentRideData!['rideId'] = rideId;
        
        // 3. Ipe simu muda wa kurekodi transaction ya Firestore (500ms)
        await Future.delayed(const Duration(milliseconds: 500));
        
        // 4. Sasa badili status (Hapa ndipo Map itaanza kuonekana)
        _status = DriverRideStatus.pickingUp;
        notifyListeners();

        // 5. Tawanya kazi nyingine za nyuma (Background tasks)
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (_status != DriverRideStatus.idle && authUid != null) {
            FirebaseFirestore.instance.collection('drivers_online').doc(authUid)
                .update({'status': 'busy'})
                .catchError((e) => debugPrint("Error updating online status: $e"));
          }
        });

        Future.delayed(const Duration(milliseconds: 2000), () {
          if (_status != DriverRideStatus.idle && rideId.isNotEmpty) {
            _listenToCurrentRide(rideId);
          }
        });
        
        return true;
      }
      return false;
    } catch (e) { 
      debugPrint("❌ AcceptRide Transaction Error: $e");
      return false; 
    }
  }

  void _listenToCurrentRide(String rideId) {
    _currentRideSubscription?.cancel();
    _currentRideSubscription = FirebaseFirestore.instance.collection('ride_requests').doc(rideId).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['status'] == 'cancelled') {
          _resetRide();
        } else {
          // Sawazisha data za safari na zile za Firestore (pamoja na fare/paymentMethod)
          _currentRideData = data;
          _currentRideData!['rideId'] = snapshot.id;
          notifyListeners();
        }
      } else {
        _resetRide();
      }
    });
  }

  void updateRideStatus(DriverRideStatus newStatus) async {
    _status = newStatus;
    if (_currentRideData == null) return;
    String statusStr = 'accepted';
    if (newStatus == DriverRideStatus.arrived) {
      statusStr = 'arrived';
      SoundService.playDriverArrived();
    }
    if (newStatus == DriverRideStatus.tripInProgress) { 
      statusStr = 'picked_up'; 
      _startTripCounters(); 
      SoundService.playTripStarted();
    }
    try {
      await FirebaseFirestore.instance.collection('ride_requests').doc(_currentRideData!['rideId'].toString())
          .update({'status': statusStr, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {}
    notifyListeners();
  }

  void _startTripCounters() {
    _tripSeconds = 0;
    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_status == DriverRideStatus.tripInProgress) { _tripSeconds++; notifyListeners(); } else t.cancel();
    });
  }

  Future<void> completeRide({required double fare, required double distance, required double duration}) async {
    if (_currentRideData == null) return;
    await FirebaseFirestore.instance.collection('ride_requests').doc(_currentRideData!['rideId'].toString()).update({
      'status': 'completed', 'fare': fare, 'distance': distance, 'duration': duration, 'paymentStatus': 'pending', 'completedAt': FieldValue.serverTimestamp(),
    });
    _status = DriverRideStatus.waitingForPayment;
    notifyListeners();
  }

  Future<void> confirmPaymentReceived() async {
    if (_currentRideData == null || _user == null) {
      _resetRide();
      return;
    }

    try {
      SoundService.playPaymentSuccess();
      final String? rideId = _currentRideData!['rideId']?.toString();
      
      if (rideId != null && rideId.isNotEmpty) {
        // 1. Sasisha hali ya malipo kwenye ride_requests
        await FirebaseFirestore.instance.collection('ride_requests').doc(rideId).update({
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'status': 'completed_paid',
        });

        // 2. Rekodi safari kwenye mfumo wa fedha (80/20 logic ipo ndani ya recordTrip)
        final tripData = Map<String, dynamic>.from(_currentRideData!);
        tripData['id'] = rideId;
        tripData['status'] = 'paid';
        tripData['paymentStatus'] = 'paid';
        
        await DatabaseService.instance.recordTrip(tripData);
        
        // 3. Ongeza takwimu za dereva
        await DatabaseService.instance.incrementDriverRides(_user!.id);
      }
    } catch (e) {
      debugPrint("❌ Error confirming payment: $e");
    } finally {
      _resetRide();
    }
  }

  Future<void> cancelRideByDriver(String reason) async {
    if (_currentRideData == null) return;
    await FirebaseFirestore.instance.collection('ride_requests').doc(_currentRideData!['rideId'].toString()).update({
      'status': 'cancelled', 'cancelledBy': 'driver', 'cancellationReason': reason,
    });
    _resetRide();
  }

  void _listenToMessages(String riderId) {
    if (_user == null) return;
    List<String> ids = [_user!.id, riderId]; ids.sort();
    final chatId = ids.join('_');
    _chatSubscription?.cancel();
    _chatSubscription = FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages')
        .where('timestamp', isGreaterThan: Timestamp.now()).orderBy('timestamp', descending: true).snapshots().listen((snap) {
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          if (data['senderId'] != _user!.id) {
            _lastMessage = ChatMessage(senderId: data['senderId'] ?? '', senderName: data['senderName'] ?? 'Rider', message: data['message'] ?? '', timestamp: (data['timestamp'] as Timestamp?)?.toDate());
            notifyListeners();
          }
        }
      }
    });
  }

  void clearLastMessage() { _lastMessage = null; notifyListeners(); }

  void sendSos(String userId, ll.LatLng? location) {
    FirebaseFirestore.instance.collection('sos_alerts').add({
      'rideId': _currentRideData?['rideId'] ?? 'no_active_ride',
      'userId': userId,
      'role': 'driver',
      'location': {'lat': location?.latitude, 'lng': location?.longitude},
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active', // Added for Admin Real-time Tracking
    });
  }

  void _resetRide() {
    _status = DriverRideStatus.idle;
    final String? authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null) FirebaseFirestore.instance.collection('drivers_online').doc(authUid).update({'status': 'idle'});
    _currentRideData = null; _tripTimer?.cancel(); _chatSubscription?.cancel(); _currentRideSubscription?.cancel();
    _tripDistance = 0.0; _tripSeconds = 0; notifyListeners();
  }

  void _startLocationService() async {
    try {
      final service = FlutterBackgroundService();
      bool isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
      }
    } catch (e) {
      debugPrint("Error starting background service: $e");
    }
  }

  void updateStatus(String userId, String status, ll.LatLng? location, String vehicleType, {String? region, String? city}) {
    final String docId = FirebaseAuth.instance.currentUser?.uid ?? userId;
    
    if (status != 'offline' && isBlocked) {
      FirebaseFirestore.instance.collection('drivers_online').doc(docId).delete();
      FirebaseFirestore.instance.collection('drivers').doc(docId).set({'isOnline': false}, SetOptions(merge: true));
      return;
    }

    if (status == 'offline') {
      FirebaseFirestore.instance.collection('drivers_online').doc(docId).delete();
      FirebaseFirestore.instance.collection('drivers').doc(docId).set({'isOnline': false}, SetOptions(merge: true));
    } else {
      // Washa background service dereva anapokuwa online
      _startLocationService();

      FirebaseFirestore.instance.collection('drivers_online').doc(docId).set({
        'id': docId, 
        'status': status, 
        'lat': location?.latitude, 
        'lng': location?.longitude,
        'vehicleType': Vehicle.getStandardizedType(vehicleType), 
        'region': region, 
        'city': city, 
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Update drivers collection as well
      FirebaseFirestore.instance.collection('drivers').doc(docId).set({
        'isOnline': true,
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  @override
  void dispose() {
    _tripTimer?.cancel(); _requestsSubscription?.cancel(); _chatSubscription?.cancel();
    _walletSubscription?.cancel();
    _currentRideSubscription?.cancel(); _rideRequestController.close(); super.dispose();
  }
}
