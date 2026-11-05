import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VoiceService {
  static final SpeechToText _speech = SpeechToText();

  static Future<Map<String, dynamic>?> listenAndGetLocation() async {
    try {
      final available = await _speech.initialize(
        onError: (error) => print('Speech Error: $error'),
        onStatus: (status) => print('Speech Status: $status'),
      );
      if (!available) return null;

      var recognizedText = '';
      var isListening = true;
      await _speech.listen(
        onResult: (result) {
          recognizedText = result.recognizedWords;
          if (result.finalResult) isListening = false;
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
        ),
      );

      var retry = 0;
      while (isListening && retry < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        retry++;
      }
      await _speech.stop();
      if (recognizedText.trim().isEmpty) return null;

      final response = await Supabase.instance.client.functions.invoke(
        'sta-ai',
        body: {'action': 'destination_intent', 'text': recognizedText.trim()},
      );
      if (response.status != 200 || response.data is! Map) return null;
      final destination = (response.data['destination'] as String?)?.trim();
      if (destination == null || destination.isEmpty) return null;
      return _forwardGeocode(destination);
    } catch (e) {
      print('Voice AI Error: $e');
      return null;
    } finally {
      await _speech.stop();
    }
  }

  static Future<Map<String, dynamic>?> _forwardGeocode(String address) async {
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(address)}&limit=3&lat=-6.79&lon=39.20',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data['features'] is! List || (data['features'] as List).isEmpty) return null;

      final features = data['features'] as List;
      final feature = features.firstWhere(
        (item) => item['properties']?['countrycode'] == 'TZ',
        orElse: () => features.first,
      );
      final coordinates = feature['geometry']?['coordinates'];
      if (coordinates is! List || coordinates.length < 2) return null;
      final properties = feature['properties'] as Map? ?? {};
      final name = (properties['name'] as String?) ?? address;
      final city = properties['city'] ?? properties['state'];
      return {
        'name': city == null ? name : '$name, $city',
        'location': LatLng(
          (coordinates[1] as num).toDouble(),
          (coordinates[0] as num).toDouble(),
        ),
      };
    } catch (e) {
      print('Forward Geocode Error: $e');
      return null;
    }
  }
}
