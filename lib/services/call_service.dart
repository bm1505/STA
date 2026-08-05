import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CallService {
  static const String appId = "39c388815a804bc58a43fd527c7b0b73";
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<bool> handlePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.phone,
    ].request();
    return statuses[Permission.microphone] == PermissionStatus.granted;
  }

  static Future<void> updateCallStatus(String rideId, String? status,
      {String? callerName, String? callerId}) async {
    if (status == null) {
      await _firestore
          .collection('ride_requests')
          .doc(rideId)
          .update({'activeCall': FieldValue.delete()});
    } else {
      await _firestore.collection('ride_requests').doc(rideId).update({
        'activeCall': {
          'status': status,
          'callerName': callerName,
          'callerId': callerId,
          'timestamp': FieldValue.serverTimestamp(),
        }
      });
    }
  }

  static Stream<DocumentSnapshot> listenToCall(String rideId) {
    return _firestore.collection('ride_requests').doc(rideId).snapshots();
  }
}
