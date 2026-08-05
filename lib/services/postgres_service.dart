import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PostgresService {
  static final PostgresService instance = PostgresService._();
  PostgresService._();

  Future<String> uploadFile(String userId, String type, Uint8List bytes) async {
    try {
      // IP YA EMULATOR: 10.0.2.2 inaunganisha Emulator na Localhost ya PC yako
      // IP YA SIMU HALISI: Lazima uweke IP ya PC yako (mfano 192.168.1.105)
      String host = "10.0.2.2"; 
      
      if (kIsWeb) {
        host = "localhost";
      }
      
      final url = Uri.parse('http://$host:3000/upload');

      debugPrint('--- BRIDGE UPLOAD: $userId ($type) to $host ---');
      final response = await http.post(
        url,
        headers: {
          'x-user-id': userId,
          'x-file-type': type,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        debugPrint('✅ Picha Imepakiwa Postgres!');
        return "pg://$userId/$type";
      } else {
        debugPrint('❌ Imeshindikana kupakia: Status ${response.statusCode}');
        return "";
      }
    } catch (e) {
      debugPrint('❌ Error ya Mtandao: $e');
      return "";
    }
  }

  Future<void> initializeDB() async {
    // Logic ya kuanzisha DB kama ipo
  }
}
