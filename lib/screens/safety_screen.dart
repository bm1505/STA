import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/localization_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../utils/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  Future<void> _makeEmergencyCall() async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: '112',
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentGold = AppTheme.primaryGold;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundCharcoal : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          LocalizationService.translate('safety_center', lang),
          style: GoogleFonts.poppins(
              color: accentGold, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(isDark ? 0.1 : 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                        color: Colors.red.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.gpp_maybe, color: Colors.redAccent, size: 60),
                  const SizedBox(height: 15),
                  Text(
                    LocalizationService.translate('emergency_sos', lang),
                    style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.red.shade900,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    LocalizationService.translate('sos_desc', lang),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _makeEmergencyCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text(
                        LocalizationService.translate('send_sos', lang),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            _buildSafetyTip(
              Icons.share_location,
              lang == 'Kiswahili' ? "Shiriki Safari Yako" : "Share Your Trip",
              lang == 'Kiswahili'
                  ? "Wajulishe watu wako wa karibu mahali ulipo kwa wakati halisi."
                  : "Let your loved ones know your real-time location.",
              isDark,
            ),
            _buildSafetyTip(
              Icons.verified_user,
              lang == 'Kiswahili' ? "Madereva Waliohakikiwa" : "Verified Drivers",
              lang == 'Kiswahili'
                  ? "Madereva wetu wote wanapitia uhakiki mkali wa nyaraka na usalama."
                  : "All our drivers undergo rigorous document and safety verification.",
              isDark,
            ),
            _buildSafetyTip(
              Icons.support,
              lang == 'Kiswahili' ? "Msaada wa 24/7" : "24/7 Support",
              lang == 'Kiswahili'
                  ? "Timu yetu ya usalama inapatikana muda wote kusaidia dharura yoyote."
                  : "Our safety team is available at all times to assist with any emergencies.",
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyTip(
      IconData icon, String title, String description, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryGold, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 5),
                Text(description,
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
