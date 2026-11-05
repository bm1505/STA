import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';

class AdminAIService {
  /// Sends document bytes to the authenticated STA server function.
  /// Gemini credentials remain in Supabase Function secrets.
  static Future<Map<String, dynamic>> analyzeDocument({
    required String imageUrl,
    required String docType,
    required UserModel driver,
  }) async {
    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
        throw ArgumentError('Invalid document image URL.');
      }

      final imageResponse = await http.get(uri).timeout(const Duration(seconds: 20));
      if (imageResponse.statusCode != 200 || imageResponse.bodyBytes.isEmpty) {
        throw StateError('Could not download the document image.');
      }
      if (imageResponse.bodyBytes.length > 8 * 1024 * 1024) {
        throw StateError('Document image exceeds the 8 MB limit.');
      }

      final path = uri.path.toLowerCase();
      final mimeType = path.endsWith('.png')
          ? 'image/png'
          : path.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';

      final response = await Supabase.instance.client.functions.invoke(
        'sta-ai',
        body: {
          'action': 'document_review',
          'docType': docType,
          'registeredName': driver.name,
          'mimeType': mimeType,
          'imageBase64': base64Encode(imageResponse.bodyBytes),
        },
      );

      if (response.status != 200 || response.data is! Map) {
        throw StateError('Document verification service is unavailable.');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } catch (error) {
      return {
        'error': error.toString(),
        'isValid': false,
        'summary': 'Verification failed. Please review the document manually.',
      };
    }
  }
}
