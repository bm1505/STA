import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OtpService {
  static String? _lastGeneratedOtp;

  static String? get lastOtp => _lastGeneratedOtp;

  static String generateOtp([String? email]) {
    final random = Random();
    String otp = "";
    for (int i = 0; i < 6; i++) {
      otp += random.nextInt(10).toString();
    }
    _lastGeneratedOtp = otp;

    print("\n\n******************************************");
    print("🔐 STA RIDE OTP: $otp");
    if (email != null) print("📧 FOR EMAIL: $email");
    print("******************************************\n\n");

    return otp;
  }

  static Future<bool> sendEmailOtp(String email, String name) async {
    final String cleanEmail = email.trim().toLowerCase();
    String otp = generateOtp(cleanEmail);

    try {
      // HAKIKISHA HIZI KEYS NI SAHIHI KUTOKA EMAILJS DASHBOARD
      const String serviceId = 'service_b0uqz7v'; 
      const String templateId = 'template_zmrlbmi'; 
      const String publicKey = '7HH6fJ19XQs5LFzPK'; 

      final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
      
      final response = await http.post(
        url,
        headers: {
          'origin': 'http://localhost',
          'Content-Type': 'application/json'
        },
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {
            'email': cleanEmail, // Kwenye template tumia {{email}}
            'to_name': name,     // Kwenye template tumia {{to_name}}
            'passcode': otp,    // Kwenye template tumia {{passcode}}
            'time': '15 minutes',
            'project_name': 'STA RIDE',
          }
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ OTP IMETUMWA KWENDA: $cleanEmail");
        return true;
      } else {
        debugPrint("❌ EMAILJS ERROR: ${response.statusCode} - ${response.body}");
        // Hata ikifeli, tutarudisha true ili uweze kutumia namba ya terminal
        return true; 
      }
    } catch (e) {
      debugPrint("⚠️ OTP EXCEPTION: $e");
      return true; // Ruhusu aendelee na namba ya terminal
    }
  }

  static bool verifyOtp(String inputOtp) {
    if (_lastGeneratedOtp == null) return false;
    String cleanedInput = inputOtp.replaceAll(' ', '').trim();
    return cleanedInput == _lastGeneratedOtp;
  }
}
