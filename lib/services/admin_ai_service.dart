import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/user.dart';

class AdminAIService {
  // Tunatumia Key ile ile iliyopo kwenye VoiceService
  static const String _apiKey = String.fromEnvironment('GCP_API_KEY');

  /// Inachukua URL ya picha na kuituma kwa Gemini ili kuhakiki maudhui
  static Future<Map<String, dynamic>> analyzeDocument({
    required String imageUrl,
    required String docType, // 'LICENSE', 'INSURANCE', 'ID'
    required UserModel driver,
  }) async {
    try {
      // 1. Fetch image bytes
      final imgResponse = await http.get(Uri.parse(imageUrl));
      if (imgResponse.statusCode != 200) throw "Could not download image";
      final bytes = imgResponse.bodyBytes;

      // 2. Setup Gemini
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      
      final prompt = """
      You are an automated document verification assistant for a taxi app named 'STA RIDE'.
      Analyze this $docType image.
      The driver's registered name is: '${driver.name}'.
      
      Tasks:
      1. Extract the Full Name on the document.
      2. Extract the Expiry Date (if visible).
      3. Compare the name on the document with the registered name.
      4. Determine if the document appears valid and authentic.
      
      Return ONLY a JSON object with these keys: 
      'extractedName', 'expiryDate', 'nameMatch' (boolean), 'isValid' (boolean), 'summary' (short string).
      """;

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ])
      ];

      final response = await model.generateContent(content);
      final responseText = response.text?.trim() ?? "{}";
      
      // Kusafisha JSON (Gemini mara nyingi huweka ```json ... ```)
      final cleanJson = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      return json.decode(cleanJson);
    } catch (e) {
      print("AI Verification Error: $e");
      return {
        'error': e.toString(),
        'isValid': false,
        'summary': "Verification failed or timed out."
      };
    }
  }
}
