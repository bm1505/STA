import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:latlong2/latlong.dart';

class VoiceService {
  static final SpeechToText _speech = SpeechToText();

  static const String _apiKey =
      String.fromEnvironment('GCP_API_KEY');

  static Future<Map<String, dynamic>?> listenAndGetLocation() async {
    try {
      bool available = await _speech.initialize(
        onError: (error) => print('Speech Error: $error'),
        onStatus: (status) => print('Speech Status: $status'),
      );
      if (!available) {
        print("Speech recognition not available");
        return null;
      }

      String recognizedText = "";
      bool isListening = true;

      await _speech.listen(
        onResult: (result) {
          recognizedText = result.recognizedWords;
          if (result.finalResult) {
            isListening = false;
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
        ),
      );

      // Subiri mpaka iache kusikiliza au ifike timeout
      int retry = 0;
      while (isListening && retry < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        retry++;
      }
      await _speech.stop();

      if (recognizedText.isEmpty) {
        print("No text recognized");
        return null;
      }

      print("Recognized: $recognizedText");

      // Sasa tunamtumia Gemini kuelewa "Nia" (Intent)
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      final prompt = [
        Content.text("User Input: '$recognizedText'\n"
            "Context: Taxi booking app in Tanzania (focused on Dar es Salaam, Arusha, Dodoma, Mwanza).\n"
            "Task: Extract the specific destination or landmark the user wants to go to.\n"
            "Instructions:\n"
            "1. If the user mentions a landmark (e.g., 'Mlimani City', 'Clock Tower'), extract it.\n"
            "2. If they mention a city, include it (e.g., 'Mlimani City, Dar es Salaam').\n"
            "3. If no clear destination is found, return ONLY the word 'null'.\n"
            "4. Be smart with Swahili: 'Naenda Posta' -> 'Posta, Dar es Salaam', 'Nipeleke uwanja wa ndege' -> 'Julius Nyerere International Airport'.\n"
            "Output: Return ONLY the extracted destination name.")
      ];

      final response = await model.generateContent(prompt).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException("Gemini timeout"),
          );

      String? destination = response.text?.trim();
      // Ondoa markdown formatting kama Gemini akiamua kuweka
      destination = destination?.replaceAll('```', '').replaceAll('`', '');
      print("AI Extracted Destination: $destination");

      if (destination != null && destination.toLowerCase() != "null") {
        // Tunatumia Photon API badala ya geocoding package (ambayo haifanyi kazi web)
        return await _forwardGeocode(destination);
      }
    } catch (e) {
      print("Voice AI Error: $e");
      // Ondoa Mock Data hapa ili kuruhusu kazi halisi
      // Ikiwa kuna kosa, tunarudisha null ili App ionyeshe ujumbe wa kosa kwa mtumiaji
      return null;
    } finally {
      await _speech.stop();
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _forwardGeocode(String address) async {
    try {
      // Tunatumia Photon API na upendeleo wa eneo la Tanzania (lat ~ -6, lon ~ 35)
      // Arusha: -3.37, 36.68 | Dar: -6.79, 39.20
      // Tunatumia eneo la katikati au lile la mtumiaji ikiwa linapatikana.
      final url = Uri.parse(
          'https://photon.komoot.io/api/?q=${Uri.encodeComponent(address)}&limit=3&lat=-6.79&lon=39.20');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          // Tafuta matokeo yaliyo ndani ya Tanzania kwanza
          var features = data['features'] as List;
          var tzFeature = features.firstWhere(
            (f) => f['properties']['countrycode'] == 'TZ',
            orElse: () => features[0],
          );

          final coords = tzFeature['geometry']['coordinates'];
          final props = tzFeature['properties'];
          
          // Tengeneza jina zuri la anwani
          String displayName = props['name'] ?? address;
          if (props['city'] != null) displayName += ", ${props['city']}";
          else if (props['state'] != null) displayName += ", ${props['state']}";

          return {
            'name': displayName,
            'location': LatLng(coords[1], coords[0]),
          };
        }
      }
    } catch (e) {
      print("Forward Geocode Error: $e");
    }
    return null;
  }
}
