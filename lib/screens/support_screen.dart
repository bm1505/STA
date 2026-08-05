import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/localization_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../utils/theme.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

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
          LocalizationService.translate('customer_support', lang),
          style: GoogleFonts.poppins(
              color: accentGold, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildSupportOption(
              context,
              Icons.chat_bubble_outline,
              lang == 'Kiswahili' ? "Zungumza Nasi" : "Live Chat",
              lang == 'Kiswahili'
                  ? "Ongea na timu yetu sasa hivi"
                  : "Speak to our team now",
              isDark,
              () => Navigator.pushNamed(context, '/chat', arguments: {
                'receiverId': 'admin_support',
                'receiverName': 'STA Support',
                'senderId': auth.currentUser?.id ?? '',
                'senderName': auth.currentUser?.name ?? 'User',
              }),
            ),
            const SizedBox(height: 15),
            _buildSupportOption(
              context,
              Icons.email_outlined,
              lang == 'Kiswahili' ? "Tuma Barua Pepe" : "Email Support",
              "support@staride.co.tz",
              isDark,
              () {},
            ),
            const SizedBox(height: 15),
            _buildSupportOption(
              context,
              Icons.phone_in_talk_outlined,
              lang == 'Kiswahili' ? "Tupigie" : "Call Us",
              "+255 742 642 009",
              isDark,
              () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportOption(BuildContext context, IconData icon, String title,
      String subtitle, bool isDark, VoidCallback onTap) {
    return Card(
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGold.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.primaryGold, size: 24),
        ),
        title: Text(title,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
        trailing: Icon(Icons.arrow_forward_ios,
            color: isDark ? Colors.white24 : Colors.black26, size: 16),
        onTap: onTap,
      ),
    );
  }
}
