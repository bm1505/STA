import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../utils/theme.dart';
import 'package:intl/intl.dart';

class DriverTripHistoryScreen extends StatefulWidget {
  final String driverId;
  const DriverTripHistoryScreen({super.key, required this.driverId});

  @override
  State<DriverTripHistoryScreen> createState() =>
      _DriverTripHistoryScreenState();
}

class _DriverTripHistoryScreenState extends State<DriverTripHistoryScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;
  double _totalEarnings = 0.0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final trips = await DatabaseService.instance
        .getAllTrips(driverId: auth.currentUser?.id);
    
    // Sort newest to oldest
    trips.sort((a, b) {
      DateTime dtA, dtB;
      
      dtA = DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      dtB = DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      
      return dtB.compareTo(dtA);
    });

    double earnings = 0.0;
    for (var trip in trips) {
      String status = (trip['status'] ?? '').toString().toUpperCase();
      if (status == 'COMPLETED' || status == 'PAID') {
        earnings += (trip['fare'] as num).toDouble();
      }
    }
    setState(() {
      _trips = trips;
      _totalEarnings = earnings;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final lang = authProvider.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        title: Text(LocalizationService.translate('my_earnings', lang),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryGold,
                letterSpacing: 1.5)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppTheme.primaryGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildEarningsHeader(lang),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _trips.isEmpty
                    ? _buildEmptyState(lang, isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        itemCount: _trips.length,
                        itemBuilder: (context, index) {
                          final trip = _trips[index];
                          return _buildTripCard(trip, lang, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsHeader(String lang) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 40),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF7A4B13), Color(0xFF4B2E0B)],
          center: Alignment.center,
          radius: 1.5,
        ),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
        border: Border(
          bottom: BorderSide(color: Colors.black, width: 3),
          left: BorderSide(color: Colors.black, width: 3),
          right: BorderSide(color: Colors.black, width: 3),
        ),
      ),
      child: Column(
        children: [
          Text(LocalizationService.translate('total_earnings', lang),
              style: GoogleFonts.poppins(
                  color: AppTheme.primaryGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Text(
            "TZS ${NumberFormat('#,###').format(_totalEarnings)}",
            style: GoogleFonts.poppins(
                fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppTheme.primaryGold, width: 2),
            ),
            child: Text(
              LocalizationService.translate('completed_trips', lang)
                  .replaceFirst('{count}', _trips.length.toString()),
              style: GoogleFonts.poppins(
                  color: AppTheme.primaryGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String lang, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.drive_eta,
              size: 80,
              color: isDark ? Colors.white10 : Colors.black12),
          const SizedBox(height: 15),
          Text(LocalizationService.translate('no_trips_found', lang),
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black54,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip, String lang, bool isDark) {
    DateTime dt;
    dt = DateTime.tryParse(trip['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    String formattedDate = DateFormat('MMM d, hh:mm a').format(dt);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2B2B) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.black : Colors.grey.shade200, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.greenAccent, width: 1),
            ),
            child: const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 24),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    (trip['isGuestRide'] == true &&
                            trip['guestName'] != null &&
                            trip['guestName'].toString().isNotEmpty)
                        ? "${trip['guestName']} (${LocalizationService.translate('guest', lang)})"
                        : "${LocalizationService.translate('rider', lang)}: ${trip['riderName'] ?? LocalizationService.translate('sta_user', lang)}",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(formattedDate,
                    style: GoogleFonts.poppins(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Text(
            "TZS ${NumberFormat('#,###').format(trip['fare'])}",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryGold,
                fontSize: 16),
          ),
        ],
      ),
    );
  }
}
