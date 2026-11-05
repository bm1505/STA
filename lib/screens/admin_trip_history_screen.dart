import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';
import 'package:intl/intl.dart';

class AdminTripHistoryScreen extends StatefulWidget {
  const AdminTripHistoryScreen({super.key});

  @override
  State<AdminTripHistoryScreen> createState() => _AdminTripHistoryScreenState();
}

class _AdminTripHistoryScreenState extends State<AdminTripHistoryScreen> {
  List<Map<String, dynamic>> _allTrips = [];
  bool _isLoading = true;
  String _selectedStatus = 'ALL';
  String _selectedTimeFrame = 'ALL'; // TODAY, WEEK, MONTH, YEAR, ALL

  @override
  void initState() {
    super.initState();
    _fetchTrips();
  }

  Future<void> _fetchTrips() async {
    setState(() => _isLoading = true);
    try {
      final trips = await DatabaseService.instance.getAllTrips(adminView: true);
      trips.sort((left, right) {
        final leftDate = DateTime.tryParse(left['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = DateTime.tryParse(right['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });
      if (mounted) {
        setState(() {
          _allTrips = trips;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching trips: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTrips {
    return _allTrips.where((trip) {
      // 1. Status Filter
      bool matchesStatus = _selectedStatus == 'ALL' || 
          (trip['status'] ?? '').toString().toUpperCase() == _selectedStatus;
      
      // 2. Time Filter
      bool matchesTime = true;
      if (_selectedTimeFrame != 'ALL') {
        final dynamic ts = trip['timestamp'];
        if (ts != null) {
          DateTime date;
          if (ts is DateTime) date = ts;
          else if (ts is String) date = DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0);
          else date = DateTime.fromMillisecondsSinceEpoch(0);

          final now = DateTime.now();
          if (_selectedTimeFrame == 'TODAY') {
            matchesTime = date.year == now.year && date.month == now.month && date.day == now.day;
          } else if (_selectedTimeFrame == 'WEEK') {
            matchesTime = now.difference(date).inDays <= 7;
          } else if (_selectedTimeFrame == 'MONTH') {
            matchesTime = date.year == now.year && date.month == now.month;
          } else if (_selectedTimeFrame == 'YEAR') {
            matchesTime = date.year == now.year;
          }
        }
      }
      return matchesStatus && matchesTime;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTrips;
    
    return Scaffold(
      backgroundColor: AppTheme.adminBg,
      appBar: AppBar(
        title: Text('REPORTS & ANALYTICS',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        backgroundColor: AppTheme.adminSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.adminPrimary),
            onPressed: _fetchTrips,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.adminPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTimeSelector(),
                      const SizedBox(height: 20),
                      _buildRevenueCards(filtered),
                      const SizedBox(height: 30),
                      _buildStatusFilters(),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Trip Logs (${filtered.length})",
                              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          if (_selectedStatus != 'ALL' || _selectedTimeFrame != 'ALL')
                            TextButton(
                              onPressed: () => setState(() { _selectedStatus = 'ALL'; _selectedTimeFrame = 'ALL'; }),
                              child: const Text("Clear Filters", style: TextStyle(color: AppTheme.adminPrimary)),
                            )
                        ],
                      ),
                      const SizedBox(height: 15),
                      filtered.isEmpty ? _buildEmptyState() : _buildTripsTable(filtered),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTimeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['TODAY', 'WEEK', 'MONTH', 'YEAR', 'ALL'].map((time) {
          bool isSelected = _selectedTimeFrame == time;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(time, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white70)),
              selected: isSelected,
              selectedColor: AppTheme.adminPrimary,
              backgroundColor: Colors.white10,
              onSelected: (val) => setState(() => _selectedTimeFrame = time),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRevenueCards(List<Map<String, dynamic>> trips) {
    double gross = trips.fold(0.0, (sum, item) => sum + (item['fare'] ?? 0.0));
    double comm = trips.fold(0.0, (sum, item) => sum + (item['commission'] ?? 0.0));
    
    return Row(
      children: [
        _buildRevenueCard("NET REVENUE", comm, AppTheme.adminPrimary, Icons.account_balance_wallet),
        const SizedBox(width: 20),
        _buildRevenueCard("GROSS SALES", gross, Colors.white, Icons.analytics),
      ],
    );
  }

  Widget _buildRevenueCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: AppTheme.adminSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 10),
                Text(title, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              "TZS ${NumberFormat('#,###').format(amount)}",
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    return Row(
      children: [
        _statusBtn("ALL", Colors.grey),
        _statusBtn("COMPLETED", Colors.green),
        _statusBtn("REQUESTING", Colors.orange),
        _statusBtn("CANCELLED", Colors.red),
      ],
    );
  }

  Widget _statusBtn(String label, Color color) {
    bool isSelected = _selectedStatus == label;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => setState(() => _selectedStatus = label),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.2) : AppTheme.adminSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? color : Colors.white10),
            ),
            child: Center(
              child: Text(label, style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold
              )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTripsTable(List<Map<String, dynamic>> trips) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: trips.length,
        separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
        itemBuilder: (context, index) {
          final trip = trips[index];
          final status = (trip['status'] ?? 'unknown').toString().toUpperCase();
          final String driverName = trip['driverName'] ?? 'Awaiting Driver...';
          
          Color statusColor;
          switch (status) {
            case 'COMPLETED': statusColor = Colors.greenAccent; break;
            case 'REQUESTING': statusColor = Colors.orangeAccent; break;
            case 'CANCELLED': statusColor = Colors.redAccent; break;
            default: statusColor = AppTheme.adminMuted;
          }

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(status == 'COMPLETED' ? Icons.check : Icons.motorcycle, color: statusColor, size: 18),
            ),
            title: Row(
              children: [
                Expanded(child: Text(trip['riderName'] ?? 'Rider', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14))),
                const Icon(Icons.arrow_right_alt, size: 16, color: Colors.white24),
                Expanded(child: Text(driverName, style: TextStyle(color: driverName.contains('Awaiting') ? Colors.orangeAccent : Colors.white70, fontSize: 13))),
              ],
            ),
            subtitle: Text("Fare: TZS ${NumberFormat('#,###').format(trip['fare'] ?? 0)} | $status", 
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_formatTimestamp(trip['timestamp']), style: const TextStyle(color: Colors.white24, fontSize: 10)),
                if (status == 'COMPLETED')
                  Text("+${NumberFormat('#,###').format(trip['commission'] ?? 0)}", 
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime date;
    if (timestamp is DateTime) date = timestamp;
    else if (timestamp is String) date = DateTime.tryParse(timestamp) ?? DateTime.fromMillisecondsSinceEpoch(0);
    else return '';
    return DateFormat('MMM d, HH:mm').format(date);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50.0),
        child: Column(
          children: [
            Icon(Icons.history_toggle_off, size: 64, color: Colors.white.withValues(alpha: 0.05)),
            const SizedBox(height: 16),
            const Text("No trips match your filters", style: TextStyle(color: Colors.white24)),
          ],
        ),
      ),
    );
  }
}
