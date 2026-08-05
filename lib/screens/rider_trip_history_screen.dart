import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../utils/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'receipt_screen.dart';

class RiderTripHistoryScreen extends StatefulWidget {
  final String riderId;
  const RiderTripHistoryScreen({super.key, required this.riderId});

  @override
  State<RiderTripHistoryScreen> createState() => _RiderTripHistoryScreenState();
}

class _RiderTripHistoryScreenState extends State<RiderTripHistoryScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      // Jaribu kutumia widget.riderId kwanza, ikiwa tupu tumia auth.currentUser?.id
      final effectiveRiderId = widget.riderId.isNotEmpty ? widget.riderId : auth.currentUser?.id;
      
      debugPrint("🔍 Loading trips for Rider ID: $effectiveRiderId");
      
      final trips = await DatabaseService.instance.getAllTrips(
        riderId: effectiveRiderId,
      );
      
      // Sort newest to oldest
      trips.sort((a, b) {
        DateTime dtA, dtB;
        var tsA = a['timestamp'];
        var tsB = b['timestamp'];

        if (tsA is Timestamp) dtA = tsA.toDate();
        else if (tsA is String) dtA = DateTime.parse(tsA);
        else dtA = DateTime.now();

        if (tsB is Timestamp) dtB = tsB.toDate();
        else if (tsB is String) dtB = DateTime.parse(tsB);
        else dtB = DateTime.now();

        return dtB.compareTo(dtA);
      });

      debugPrint("✅ Found ${trips.length} trips");
      
      setState(() {
        _trips = trips;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error in _loadHistory: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final lang = authProvider.language;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(LocalizationService.translate('my_trips', lang),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryGold,
                letterSpacing: 1.5)),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: AppTheme.primaryGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppTheme.primaryGold,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold))
            : _trips.isEmpty
                ? Stack(
                    children: [
                      ListView(), // Hii inaruhusu pull-to-refresh kufanya kazi hata kama list ni tupu
                      _buildEmptyState(lang),
                    ],
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                    itemCount: _trips.length,
                    itemBuilder: (context, index) {
                      final trip = _trips[index];
                      return _buildTripCard(trip, lang);
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState(String lang) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history,
              size: 80,
              color: Theme.of(context).disabledColor.withValues(alpha: 0.1)),
          const SizedBox(height: 15),
          Text(LocalizationService.translate('no_trips_found', lang),
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(LocalizationService.translate('trip_history_empty_desc', lang),
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white38,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  String _formatAddress(dynamic data) {
    if (data == null) return "Unknown Location";
    if (data is String) return data;
    if (data is Map) {
      return data['name'] ?? data['address'] ?? data['text'] ?? "Unknown Location";
    }
    return data.toString();
  }

  Widget _buildTripCard(Map<String, dynamic> trip, String lang) {
    DateTime dt;
    var ts = trip['timestamp'];
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.parse(ts);
    } else {
      dt = DateTime.now();
    }
    String formattedDate = DateFormat('MMM d, yyyy • hh:mm a').format(dt);
    String status = trip['status']?.toString().toUpperCase() ?? 'PENDING';
    
    // Angalia kama imelipwa kwa njia yoyote ile
    bool isPaid = status == 'PAID' || 
                 status == 'COMPLETED_PAID' || 
                 trip['paymentStatus']?.toString().toLowerCase() == 'paid' ||
                 trip['payment_status']?.toString().toLowerCase() == 'paid';

    // Kama tayari imelipwa lakini status bado ni COMPLETED, tuonyeshe PAID
    String displayStatus = (isPaid && status == 'COMPLETED') ? 'PAID' : status;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formattedDate,
                      style: GoogleFonts.poppins(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (isPaid || status == 'COMPLETED')
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      displayStatus,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: (isPaid || status == 'COMPLETED')
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "TZS ${NumberFormat('#,###').format(trip['fare'] ?? 0)}",
                    style: GoogleFonts.poppins(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isPaid ? Icons.check_circle : Icons.pending,
                        size: 14,
                        color: isPaid ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPaid
                            ? LocalizationService.translate('paid_caps', lang)
                            : LocalizationService.translate('unpaid_caps', lang),
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isPaid ? Colors.greenAccent : Colors.orangeAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(color: Colors.white12, height: 1),
          ),
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 10, color: AppTheme.primaryGold),
                  Container(width: 2, height: 30, color: Colors.white10),
                  const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatAddress(trip['pickup']),
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 20),
                    Text(_formatAddress(trip['dropoff']),
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (!isPaid && status == 'COMPLETED') ...[
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: () async {
                // TODO: Implement payment logic
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: Colors.black,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.black, width: 2)),
              ),
              child: Text(LocalizationService.translate('pay_now', lang),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(color: Colors.white10, height: 1),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person,
                    size: 16, color: AppTheme.primaryGold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "${LocalizationService.translate('driver', lang)}: ${trip['driverName'] ?? LocalizationService.translate('sta_driver', lang)}",
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white60),
                ),
              ),
              if (isPaid || status == 'COMPLETED')
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReceiptScreen(tripData: trip),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long,
                      color: AppTheme.primaryGold, size: 16),
                  label: Text(
                    LocalizationService.translate('receipt_caps', lang),
                    style: GoogleFonts.poppins(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
