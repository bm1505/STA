import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart'; // Kwa kDebugMode au kIsWeb
import 'package:exif/exif.dart';

class VisualPositioningService {
  // UPDATE: Tumeweka key mpya uliyotuma
  static const String _apiKey =
      String.fromEnvironment('GCP_API_KEY');

  static Future<Map<String, dynamic>?> detectLocationFromCamera() async {
    final XFile? xFile = await _pickImage();
    if (xFile == null) return null;

    try {
      final imageBytes = await xFile.readAsBytes();

      // JARIBIO 1: Angalia EXIF metadata kwa GPS
      final Map<String, IfdTag> exifData = await readExifFromBytes(imageBytes);
      if (exifData.containsKey('GPS GPSLatitude') &&
          exifData.containsKey('GPS GPSLongitude')) {
        final double? lat = _convertTagToDouble(exifData['GPS GPSLatitude']);
        final double? lon = _convertTagToDouble(exifData['GPS GPSLongitude']);
        final String? latRef = exifData['GPS GPSLatitudeRef']?.printable;
        final String? lonRef = exifData['GPS GPSLongitudeRef']?.printable;

        if (lat != null && lon != null) {
          final finalLat = (latRef == 'S') ? -lat : lat;
          final finalLon = (lonRef == 'W') ? -lon : lon;
          print("Visual EXIF GPS found: $finalLat, $finalLon");
          return await _reverseGeocode(finalLat, finalLon);
        }
      }

      // JARIBIO 2: Tumia Gemini AI kama metadata haipo
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);

      // Prompt ili kupata jina la sehemu
      final prompt = TextPart(
          "Identify the specific landmark or building in this image. "
          "The user is in Tanzania, so consider local names in Swahili or English. "
          "Return ONLY the name and city (e.g., 'Mlimani City Mall, Dar es Salaam'). "
          "If you don't know the exact place, return 'null'.");

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ]);

      String? resultText = response.text?.trim();
      print("Visual AI Result: $resultText");

      if (resultText != null && resultText.toLowerCase() != "null") {
        return await _forwardGeocode(resultText);
      }
      return null;
    } catch (e) {
      print("Visual AI Error: $e");
      // Ondoa Mock Data hapa ili kuruhusu kazi halisi
      // Ikiwa kuna kosa (kama API key au mtandao), tunarudisha null
      return null;
    }
  }

  static Future<XFile?> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    // Source: camera inafanya kazi mobile, kwenye web inafungua file selector au webcam
    return await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
  }

  static Future<Map<String, dynamic>?> _forwardGeocode(String address) async {
    try {
      final url = Uri.parse(
          'https://photon.komoot.io/api/?q=${Uri.encodeComponent(address)}&limit=1&lat=-3.37&lon=36.68');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final coords = feature['geometry']['coordinates'];
          final name = feature['properties']['name'] ?? address;

          return {
            'name': name,
            'location': LatLng(coords[1], coords[0]),
          };
        }
      }
    } catch (e) {
      print("Forward Geocode Error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _reverseGeocode(
      double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://photon.komoot.io/reverse?lon=$lon&lat=$lat');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final name = feature['properties']['name'] ?? "Unknown Location";
          return {
            'name': name,
            'location': LatLng(lat, lon),
          };
        }
      }
    } catch (e) {
      print("Reverse Geocode Error: $e");
    }
    return {
      'name': 'GPS Location ($lat, $lon)',
      'location': LatLng(lat, lon),
    };
  }

  static double? _convertTagToDouble(IfdTag? tag) {
    if (tag == null || tag.values == null) return null;
    final List values = tag.values.toList();
    if (values.length != 3) return null;

    double d = values[0].toDouble();
    double m = values[1].toDouble();
    double s = values[2].toDouble();

    return d + (m / 60.0) + (s / 3600.0);
  }
}
