import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

class AdminDashboardFragment extends StatefulWidget {
  const AdminDashboardFragment({super.key});

  @override
  State<AdminDashboardFragment> createState() => _AdminDashboardFragmentState();
}

class _AdminDashboardFragmentState extends State<AdminDashboardFragment> {
  final Map<String, dynamic> _stats = {
    'drivers': 0,
    'riders': 0,
    'totalFare': 0.0,
    'totalCommissions': 0.0,
    'totalTrips': 0
  };
  bool _isLoading = true;

  final List<FlSpot> _revenueSpots = [];

  @override
  void initState() {
    super.initState();
    _initDashboardStreams();
  }

  void _initDashboardStreams() {
    // Real-time chart and stats updates
    FirebaseFirestore.instance.collection('trips').snapshots().listen((_) {
      if (mounted) {
        _loadDashboardData();
        setState(() {}); // Trigger stats stream map
      }
    });

    // Trigger UI update when users change
    FirebaseFirestore.instance.collection('drivers').snapshots().listen((_) {
      if (mounted) setState(() {});
    });
    
    FirebaseFirestore.instance.collection('riders').snapshots().listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadDashboardData() async {
    try {
      // Fetch data for the last 7 days
      final now = DateTime.now();
      final lastWeek = now.subtract(const Duration(days: 7));
      
      final tripsQuery = await FirebaseFirestore.instance
          .collection('trips')
          .where('createdAt', isGreaterThan: Timestamp.fromDate(lastWeek))
          .get();

      Map<int, double> dailyRevenue = {};
      // Initialize with 0 for last 7 days
      for (int i = 0; i <= 6; i++) {
        dailyRevenue[i] = 0.0;
      }

      for (var doc in tripsQuery.docs) {
        final data = doc.data();
        final fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
        final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? now;
        
        // Calculate days ago
        final difference = now.difference(timestamp).inDays;
        if (difference >= 0 && difference <= 6) {
          // index 6 is today, 0 is 6 days ago
          int index = 6 - difference;
          dailyRevenue[index] = (dailyRevenue[index] ?? 0) + fare;
        }
      }

      if (mounted) {
        setState(() {
          _revenueSpots.clear();
          dailyRevenue.forEach((day, revenue) {
            _revenueSpots.add(FlSpot(day.toDouble(), revenue / 1000)); // Revenue in thousands for better scaling
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading chart data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Stream<Map<String, dynamic>> _getStatsStream() {
    // Using a combined approach - this will re-run whenever trips change
    // And our listeners in initState will force a rebuild when drivers/riders change
    return FirebaseFirestore.instance
        .collection('trips')
        .snapshots()
        .asyncMap((tripsSnapshot) async {
      final driversSnapshot =
          await FirebaseFirestore.instance.collection('drivers').get();
      final ridersSnapshot =
          await FirebaseFirestore.instance.collection('riders').get();
      final activeTripsSnap = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('status', whereIn: ['accepted', 'arrived', 'inProgress'])
          .get();

      double totalFare = 0;
      double todayFare = 0;
      DateTime now = DateTime.now();
      DateTime startOfToday = DateTime(now.year, now.month, now.day);

      for (var doc in tripsSnapshot.docs) {
        double fare = (doc.data()['fare'] as num?)?.toDouble() ?? 0.0;
        totalFare += fare;
        
        // Calculate Today's Fare
        Timestamp? ts = doc.data()['createdAt'] as Timestamp?;
        if (ts != null && ts.toDate().isAfter(startOfToday)) {
          todayFare += fare;
        }
      }

      // Fetch Actual Commissions from transactions
      final commissionsSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('type', isEqualTo: 'commission')
          .get();
      
      double totalComm = 0;
      double todayComm = 0;
      for (var doc in commissionsSnap.docs) {
        double amt = (doc.data()['amount'] as num?)?.toDouble() ?? 0.0;
        totalComm += amt;
        Timestamp? ts = doc.data()['timestamp'] as Timestamp?;
        if (ts != null && ts.toDate().isAfter(startOfToday)) {
          todayComm += amt;
        }
      }

      return {
        'drivers': driversSnapshot.size,
        'riders': ridersSnapshot.size,
        'totalTrips': tripsSnapshot.size,
        'activeTrips': activeTripsSnap.size,
        'totalFare': totalFare,
        'todayFare': todayFare,
        'totalCommissions': totalComm,
        'todayCommissions': todayComm,
      };
    });
  }

  Stream<List<UserModel>> _getRecentUsersStream() {
    // Combine riders and drivers for recent activity, triggered by either
    return FirebaseFirestore.instance
        .collection('drivers')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .asyncMap((driverSnap) async {
      final riderSnap = await FirebaseFirestore.instance
          .collection('riders')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      List<UserModel> users = [];
      users.addAll(driverSnap.docs
          .map((d) => UserModel.fromJson({...d.data(), 'id': d.id})));
      users.addAll(riderSnap.docs
          .map((d) => UserModel.fromJson({...d.data(), 'id': d.id})));

      // Sort by createdAt descending
      users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return users.take(8).toList();
    });
  }

  Stream<List<UserModel>> _getPendingDriversStream() {
    return FirebaseFirestore.instance
        .collection('drivers')
        .where('verificationStatus', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isTablet = size.width < 1100;

    return StreamBuilder<Map<String, dynamic>>(
      stream: _getStatsStream(),
      builder: (context, statsSnapshot) {
        return StreamBuilder<List<UserModel>>(
            stream: _getRecentUsersStream(),
            builder: (context, usersSnapshot) {
              return StreamBuilder<List<UserModel>>(
                  stream: _getPendingDriversStream(),
                  builder: (context, pendingSnapshot) {
                    if (statsSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        _isLoading) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.adminPrimary));
                    }

                    _isLoading =
                        false; // Once we have data, we're not "loading" initial state
                    final stats = statsSnapshot.data ?? _stats;
                    final recentUsers = usersSnapshot.data ?? [];
                    final pendingDrivers = pendingSnapshot.data ?? [];

                    return SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 15 : 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 30),
                          _buildStatCards(isMobile, isTablet, stats),
                          const SizedBox(height: 30),
                          if (isMobile || isTablet) ...[
                            _buildRevenueChart(),
                            const SizedBox(height: 20),
                            _buildRecentActivity(recentUsers),
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: _buildRevenueChart()),
                                const SizedBox(width: 30),
                                Expanded(
                                    flex: 1,
                                    child: _buildRecentActivity(recentUsers)),
                              ],
                            ),
                          const SizedBox(height: 30),
                          _buildVerificationQueue(isMobile, pendingDrivers),
                        ],
                      ),
                    );
                  });
            });
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "System Overview",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          "Real-time analytics and performance metrics",
          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildStatCards(
      bool isMobile, bool isTablet, Map<String, dynamic> stats) {
    final activeTrips = stats['activeTrips'] ?? 0;
    final todayComm = (stats['todayCommissions'] as num?)?.toDouble() ?? 0.0;
    final fare = (stats['totalFare'] as num?)?.toDouble() ?? 0.0;
    final riders = stats['riders'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 1 : (isTablet ? 2 : 4),
      crossAxisSpacing: 25,
      mainAxisSpacing: 25,
      childAspectRatio: isMobile ? 2.2 : 1.5,
      children: [
        _buildStatCard("Today's Earnings", 
            "TZS ${NumberFormat('#,###').format(todayComm)}", 
            Icons.account_balance_wallet_outlined, 
            const Color(0xFF10B981), // Emerald
            "+12.5%"),
        _buildStatCard("Active Rides", 
            activeTrips.toString(),
            Icons.local_taxi_outlined, 
            AppTheme.adminPrimary,
            "Live Now"),
        _buildStatCard(
            "Total Riders",
            riders.toString(),
            Icons.people_outline_rounded,
            const Color(0xFF3B82F6), // Blue
            "+4.2%"),
        _buildStatCard(
            "Gross Revenue",
            "TZS ${NumberFormat('#,###').format(fare)}",
            Icons.analytics_outlined,
            const Color(0xFFF59E0B), // Amber
            "+18.1%"),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color, String trend) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: trend.startsWith('+') ? Colors.green.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trend,
                  style: GoogleFonts.inter(
                    color: trend.startsWith('+') ? Colors.green : Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.robotoMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: AppTheme.adminMuted, 
                  fontSize: 10, 
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0)),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                  Text("Revenue Analytics",
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  Text("Weekly performance trends",
                      style: GoogleFonts.inter(color: AppTheme.adminMuted, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text("Last 7 Days", style: TextStyle(color: Colors.white70, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: _revenueSpots.isEmpty 
              ? const Center(child: Text("Loading data...", style: TextStyle(color: Colors.white24)))
              : LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => const Color(0xFF1E293B),
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        return LineTooltipItem(
                          'TZS ${NumberFormat('#,###').format(touchedSpot.y * 1000)}',
                          GoogleFonts.robotoMono(
                            color: AppTheme.adminPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.white.withValues(alpha: 0.05), strokeWidth: 1)),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 35,
                          getTitlesWidget: (value, meta) {
                            final now = DateTime.now();
                            final date = now.subtract(Duration(days: 6 - value.toInt()));
                            final dayName = DateFormat('EEE').format(date).toUpperCase();
                            return Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Text(dayName,
                                  style: GoogleFonts.inter(
                                      color: AppTheme.adminMuted, fontSize: 9, fontWeight: FontWeight.bold)),
                            );
                          })),
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}K',
                              style: GoogleFonts.robotoMono(
                                  color: AppTheme.adminMuted, fontSize: 10));
                        },
                      )),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _revenueSpots,
                    isCurved: true,
                    curveSmoothness: 0.4,
                    color: AppTheme.adminPrimary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: AppTheme.adminBg,
                        strokeWidth: 2,
                        strokeColor: AppTheme.adminPrimary,
                      ),
                    ),
                    belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.adminPrimary.withValues(alpha: 0.2),
                            AppTheme.adminPrimary.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(List<UserModel> recentUsers) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("System Activity",
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
          const SizedBox(height: 25),
          Expanded(
            child: ListView.separated(
              itemCount: recentUsers.length,
              separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.03), height: 20),
              itemBuilder: (context, index) {
                final user = recentUsers[index];
                final isDriver = user.role == UserRole.driver;
                return Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: (isDriver ? AppTheme.adminPrimary : AppTheme.adminSecondary).withValues(alpha: 0.1),
                      radius: 18,
                      child: Icon(
                        isDriver ? Icons.drive_eta_rounded : Icons.person_rounded, 
                        size: 16, 
                        color: isDriver ? AppTheme.adminPrimary : AppTheme.adminSecondary
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name.isNotEmpty ? user.name : "New User",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                          Text(
                              isDriver ? "Registered as Driver" : "Joined as Rider",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppTheme.adminMuted)),
                        ],
                      ),
                    ),
                    Text(
                      "Just now",
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.adminMuted),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationQueue(
      bool isMobile, List<UserModel> pendingDrivers) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                  Text("Verification Queue",
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                  Text("${pendingDrivers.length} drivers awaiting approval",
                      style: GoogleFonts.inter(color: AppTheme.adminMuted, fontSize: 12)),
                ],
              ),
              ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text("View All Queue")),
            ],
          ),
          const SizedBox(height: 25),
          if (pendingDrivers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.verified_user_outlined, size: 48, color: AppTheme.adminMuted.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text("Queue is empty", style: TextStyle(color: AppTheme.adminMuted)),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pendingDrivers.length > 5 ? 5 : pendingDrivers.length,
              itemBuilder: (context, index) {
                final driver = pendingDrivers[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.adminPrimary.withValues(alpha: 0.1),
                        child: Text(driver.name.isNotEmpty ? driver.name[0] : '?', 
                          style: const TextStyle(color: AppTheme.adminPrimary, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.name.isNotEmpty ? driver.name : 'Unknown Driver',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text("Plate: ${driver.carPlate ?? 'N/A'} • ${driver.carModel ?? 'Generic'}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppTheme.adminMuted, fontSize: 11)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _approveDriver(driver.id, driver.name),
                        style: TextButton.styleFrom(
                          backgroundColor: AppTheme.adminPrimary.withValues(alpha: 0.1),
                          foregroundColor: AppTheme.adminPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("REVIEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMobileVerificationCard(UserModel driver) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withValues(alpha: 0.05),
      child: ListTile(
        title: Text(driver.name.isNotEmpty ? driver.name : 'Unknown',
            style: const TextStyle(color: Colors.white)),
        subtitle: Text(driver.carPlate ?? 'N/A',
            style: const TextStyle(color: Colors.white54)),
        trailing: TextButton(
          onPressed: () => _approveDriver(
              driver.id, driver.name.isNotEmpty ? driver.name : 'Driver'),
          child: const Text("Review",
              style: TextStyle(color: AppTheme.adminPrimary)),
        ),
      ),
    );
  }

  Future<void> _approveDriver(dynamic id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Approve Driver?"),
        content: Text("Are you sure you want to verify $name?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("APPROVE")),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      await DatabaseService.instance
          .updateDriverVerification(id.toString(), true);
      _loadDashboardData();
    }
  }

  TableRow _buildTableRow(List<String> cells,
      {bool isHeader = false, String? id, String? name}) {
    return TableRow(
      children: [
        ...cells.getRange(0, 3).map((cell) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Text(
                cell,
                style: GoogleFonts.poppins(
                  color: isHeader ? Colors.white54 : Colors.white,
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: (isHeader || id == null)
              ? Text(
                  cells[3],
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                )
              : InkWell(
                  onTap: () => _approveDriver(id, name ?? "Driver"),
                  child: Text(
                    cells[3],
                    style: GoogleFonts.poppins(
                      color: AppTheme.adminPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
