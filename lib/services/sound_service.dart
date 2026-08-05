import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _messagePlayer = AudioPlayer();

  // Local Asset Paths - Using full path from pubspec
  static const String _newRequestSound = "assets/sounds/new_request.mp3"; 
  static const String _acceptedSound = "assets/sounds/accepted.mp3";
  static const String _arrivedSound = "assets/sounds/arrived.mp3";
  static const String _completedSound = "assets/sounds/completed.mp3";
  static const String _messageSound = "assets/sounds/message.mp3";
  static const String _ringtoneSound = "assets/sounds/ringtone.mp3";
  static const String _tripStartedSound = "assets/sounds/trip_started.mp3";
  static const String _paymentSuccessSound = "assets/sounds/payment_success.mp3";
  static const String _ringbackSound = "assets/sounds/ringback.mp3";

  static Future<void> initialize() async {
    try {
      await _player.setVolume(1.0);
      await _messagePlayer.setVolume(1.0);
    } catch (e) {
      debugPrint("Sound Init Error: $e");
    }
  }

  static void playNewRequest() {
    try {
      _player.play(AssetSource(_newRequestSound.replaceFirst('assets/', '')), mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playDriverAccepted() {
    try {
      stopAll();
      _player.play(AssetSource(_acceptedSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playDriverArrived() {
    try {
      stopAll();
      _player.play(AssetSource(_arrivedSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playTripCompleted() {
    try {
      stopAll();
      _player.play(AssetSource(_completedSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playTripStarted() {
    try {
      stopAll();
      _player.play(AssetSource(_tripStartedSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playPaymentSuccess() {
    try {
      stopAll();
      _player.play(AssetSource(_paymentSuccessSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void playMessageReceived() {
    try {
      _messagePlayer.play(AssetSource(_messageSound.replaceFirst('assets/', '')), mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static Future<void> playRingtone() async {
    try {
      stopAll();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(_ringtoneSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static Future<void> playRingback() async {
    try {
      stopAll();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource(_ringbackSound.replaceFirst('assets/', '')));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  static void stopAll() {
    try {
      _player.stop();
      _player.setReleaseMode(ReleaseMode.release);
    } catch (e) {
      debugPrint("Error stopping sound: $e");
    }
  }
}
