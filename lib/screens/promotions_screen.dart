import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/localization_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../utils/theme.dart';

class PromotionsScreen extends StatelessWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    final Color accentGold = AppTheme.primaryGold;

    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          LocalizationService.translate('promotions', lang),
          style: GoogleFonts.poppins(color: accentGold, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 80, color: accentGold.withValues(alpha: 0.5)),
            const SizedBox(height: 20),
            Text(
              lang == 'Kiswahili' ? "Hakuna ofa kwa sasa" : "No active promotions",
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                lang == 'Kiswahili' 
                  ? "Endelea kutumia STA RIDE kupata ofa na punguzo la bei kwenye safari zako."
                  : "Keep using STA RIDE to receive exclusive offers and discounts on your rides.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
