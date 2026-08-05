import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../utils/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentGold = AppTheme.primaryGold;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocalizationService.translate('about_sta', lang),
          style: GoogleFonts.poppins(
            color: accentGold,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Logo and App Name
            Center(
              child: Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: accentGold,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: accentGold.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  size: 80,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "STA RIDE",
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
                letterSpacing: 5,
              ),
            ),
            Text(
              "${LocalizationService.translate('version', lang)} 1.0.0",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                LocalizationService.translate('about_desc', lang),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: isDark ? Colors.white70 : Colors.black87,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 50),
            _buildSectionTitle(LocalizationService.translate('follow_us', lang), accentGold),
            const SizedBox(height: 20),
            _buildSocialLinks(lang, isDark, accentGold),
            const SizedBox(height: 60),
            Text(
              "© 2024 Smart Transport App Ltd.",
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color accentGold) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: accentGold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildSocialLinks(String lang, bool isDark, Color accentGold) {
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      alignment: WrapAlignment.center,
      children: [
        _socialIcon(Icons.language, LocalizationService.translate('website', lang), () => _launchUrl('https://staride.co.tz'), isDark, accentGold),
        _socialIcon(Icons.facebook, LocalizationService.translate('facebook', lang), () => _launchUrl('https://facebook.com/staridetz'), isDark, accentGold),
        _socialIcon(Icons.camera_alt, LocalizationService.translate('instagram', lang), () => _launchUrl('https://instagram.com/staridetz'), isDark, accentGold),
        _socialIcon(Icons.close, LocalizationService.translate('twitter', lang), () => _launchUrl('https://twitter.com/staridetz'), isDark, accentGold),
      ],
    );
  }

  Widget _socialIcon(IconData icon, String label, VoidCallback onTap, bool isDark, Color accentGold) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Icon(icon, color: accentGold, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
