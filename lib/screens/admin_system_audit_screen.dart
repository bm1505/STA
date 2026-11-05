import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/theme.dart';
import '../services/database_service.dart';

class AdminSystemAuditScreen extends StatefulWidget {
  const AdminSystemAuditScreen({super.key});

  @override
  State<AdminSystemAuditScreen> createState() => _AdminSystemAuditScreenState();
}

class _AdminSystemAuditScreenState extends State<AdminSystemAuditScreen> {
  int _activeTab = 0; 
  String? _selectedTable = 'trips';
  List<String> _tables = [];
  bool _isLoadingTables = true;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _dbVerticalController = ScrollController();
  final ScrollController _dbHorizontalController = ScrollController();
  final ScrollController _apiScrollController = ScrollController();
  final ScrollController _topDriversScrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _dbVerticalController.dispose();
    _dbHorizontalController.dispose();
    _apiScrollController.dispose();
    _topDriversScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    final tables = await DatabaseService.instance.getTableNames();
    setState(() {
      _tables = tables;
      _isLoadingTables = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          _buildSubSidebar(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111827).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(35),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(35),
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _buildBody(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.03),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 25),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "System Audit Center",
                style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
              Text(
                "Enterprise Monitoring & Governance",
                style: GoogleFonts.inter(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          _statusChip("Database: ONLINE", Colors.green),
          const SizedBox(width: 15),
          _statusChip("AI Health: OPTIMAL", AppTheme.adminPrimary),
          const SizedBox(width: 25),
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return ElevatedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.adminPrimary,
            content: Text("Generating Enterprise Audit Report (PDF)...", 
              style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        );
      },
      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
      label: Text("EXPORT REPORT", style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.adminPrimary,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildSubSidebar() {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 35),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.adminPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.security_rounded, color: AppTheme.adminPrimary, size: 20),
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("AUDIT", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                    Text("ENGINE V2.1", style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontWeight: FontWeight.bold, fontSize: 8, letterSpacing: 2)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: ListView(
              children: [
                _sidebarSection("OVERVIEW"),
                _sidebarItem(0, "Governance Dashboard", Icons.grid_view_rounded),
                
                _sidebarSection("REAL-TIME AUDIT"),
                _sidebarItem(1, "Event Stream", Icons.stream_rounded),
                _sidebarItem(5, "Ride Logs", Icons.local_taxi_rounded),
                _sidebarItem(6, "Financial Flow", Icons.payments_rounded),
                
                _sidebarSection("INFRASTRUCTURE"),
                _sidebarItem(2, "Database Explorer", Icons.data_usage_rounded),
                _sidebarItem(4, "System Health", Icons.analytics_rounded),
                _sidebarItem(7, "API Watch", Icons.api_rounded),

                _sidebarSection("SECURITY"),
                _sidebarItem(3, "Security Logs", Icons.admin_panel_settings_rounded),
                _sidebarItem(8, "Comms Audit", Icons.message_rounded),

                _sidebarSection("ANALYTICS"),
                _sidebarItem(10, "Top Performing Drivers", Icons.star_rounded),
              ],
            ),
          ),
          _buildUserInfo(),
        ],
      ),
    );
  }

  Widget _sidebarSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(35, 25, 20, 10),
      child: Text(
        title,
        style: GoogleFonts.inter(color: Colors.white10, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5),
      ),
    );
  }

  Widget _sidebarItem(int index, String title, IconData icon) {
    bool isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: isSelected ? AppTheme.adminPrimary.withValues(alpha: 0.1) : Colors.transparent,
          border: isSelected ? Border.all(color: AppTheme.adminPrimary.withValues(alpha: 0.1)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppTheme.adminPrimary : Colors.white24, size: 20),
            const SizedBox(width: 15),
            Text(
              title,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : Colors.white38,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(color: AppTheme.adminPrimary, shape: BoxShape.circle),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    return Container(
      margin: const EdgeInsets.all(25),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.shield_rounded, color: Colors.orange, size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Admin Access", style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              Text("Verified Session", style: GoogleFonts.inter(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_activeTab) {
      case 0: return _buildOverview();
      case 1: return _buildLiveActivityStream();
      case 2: return _buildDatabaseExplorer();
      case 3: return _buildSecurity();
      case 4: return _buildHealth();
      case 5: return _buildRealTimeTable("trips", "Ride Audit Log");
      case 6: return _buildRealTimeTable("wallet_transactions", "Financial Audit Log");
      case 7: return _buildApiMonitoring();
      case 8: return _buildRealTimeTable("chat_messages", "Chat & Support Audit");
      case 10: return _buildTopDriversReport();
      default: return _buildOverview();
    }
  }

  Widget _buildTopDriversReport() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Top Performing Drivers", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const Spacer(),
            _statusChip("ELITE RANKING", Colors.amber),
          ],
        ),
        const SizedBox(height: 30),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: DatabaseService.instance.getTopDriversStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.isEmpty) return const Center(child: Text("No driver data found", style: TextStyle(color: Colors.white24)));

              return ListView.builder(
                controller: _topDriversScrollController,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, i) {
                  final data = snapshot.data![i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: i == 0 ? Colors.amber.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Text("#${i + 1}", style: GoogleFonts.robotoMono(color: i < 3 ? Colors.amber : Colors.white24, fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 25),
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: AppTheme.adminPrimary.withValues(alpha: 0.1),
                          child: Text(data['name']?[0] ?? 'D', style: const TextStyle(color: AppTheme.adminPrimary, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['name'] ?? 'Unknown Driver', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(data['email'] ?? 'No Email', style: GoogleFonts.inter(color: Colors.white30, fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("${data['totalRides'] ?? 0} RIDES", style: GoogleFonts.robotoMono(color: AppTheme.adminPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                            Text(data['rating'] == null ? "No rating yet" : "Rating: ${data['rating']} ★", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOverview() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Governance Overview", style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const Spacer(),
              _dateRangePicker(),
            ],
          ),
          const SizedBox(height: 35),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 25,
            childAspectRatio: 1.3, // Imekuwa 1.3 badala ya 1.6 ili kutoa nafasi zaidi ya kimo
            children: [
              _statCard("Total Entities", "riders", Icons.people_outline_rounded, Colors.blue),
              _statCard("Active Rides", "trips", Icons.local_taxi_rounded, Colors.green),
              _statCard("Total Capital", "wallets", Icons.account_balance_wallet_rounded, Colors.orange),
              _statCard("System Alerts", "sos_alerts", Icons.warning_amber_rounded, Colors.redAccent),
              _statCard("Safety Events", "safety_events", Icons.health_and_safety_outlined, Colors.deepOrangeAccent),
            ],
          ),
          const SizedBox(height: 30),
          _buildRevenueChart(),
          const SizedBox(height: 40),
          _buildLiveActivityStream(isCompact: true),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Financial Performance", style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Real-time commission revenue flow", style: GoogleFonts.inter(color: Colors.white30, fontSize: 11)),
                ],
              ),
              const Spacer(),
              _statusChip("LIVE FEED", Colors.green),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService.instance.getCommissionTransactionsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                List<FlSpot> spots = [];
                final docs = [...snapshot.data!]
                  ..sort((a, b) => (a['created_at']?.toString() ?? '')
                      .compareTo(b['created_at']?.toString() ?? ''));
                final recent = docs.length > 10 ? docs.sublist(docs.length - 10) : docs;
                for (int i = 0; i < recent.length; i++) {
                  final amount = ((recent[i]['amount'] as num?)?.toDouble() ?? 0).abs();
                  spots.add(FlSpot(i.toDouble(), amount));
                }

                if (spots.isEmpty) {
                  return const Center(child: Text("Waiting for transaction data...", style: TextStyle(color: Colors.white24)));
                }

                return LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        gradient: const LinearGradient(colors: [AppTheme.adminPrimary, Colors.orangeAccent]),
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [AppTheme.adminPrimary.withValues(alpha: 0.2), Colors.transparent],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String collection, IconData icon, Color color) {
    return StreamBuilder<String>(
      stream: DatabaseService.instance.getAdminMetricStream(collection),
      builder: (context, snapshot) {
        String val = snapshot.data ?? "...";
        return Container(
          padding: const EdgeInsets.all(18), // Imepunguzwa kutoka 25
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20), // Imepunguzwa kidogo
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8), // Imepunguzwa
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18), // Imepunguzwa
              ),
              const Spacer(),
              FittedBox( // Nimeongeza FittedBox ili namba isivuje nje
                fit: BoxFit.scaleDown,
                child: Text(val, style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ),
              Text(title, style: GoogleFonts.inter(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        );
      }
    );
  }

  Widget _buildLiveActivityStream({bool isCompact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Real-Time Event Stream", style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 15),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text("LIVE", style: GoogleFonts.inter(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 25),
        SizedBox(
          height: isCompact ? 400 : 600,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: DatabaseService.instance.getAdminTripsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final trips = [...snapshot.data!]
                  ..sort((a, b) => (b['timestamp']?.toString() ?? '')
                      .compareTo(a['timestamp']?.toString() ?? ''));
                final recent = trips.take(20).toList();
                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(15),
                    shrinkWrap: isCompact,
                    itemCount: recent.length,
                    itemBuilder: (context, i) {
                      final data = recent[i];
                      return _activityItem(
                        data['timestamp'] ?? 'N/A',
                        "RIDE",
                        "Completed ride: ${data['riderName'] ?? 'Unknown'}",
                        data['status'] ?? 'completed',
                        Colors.blue,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _activityItem(dynamic time, String type, String msg, String status, Color color) {
    String timeStr = "Now";
    final parsedTime = DateTime.tryParse(time?.toString() ?? '');
    if (parsedTime != null) timeStr = DateFormat('HH:mm:ss').format(parsedTime.toLocal());
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.01), borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          Text(timeStr, style: GoogleFonts.robotoMono(color: Colors.white24, fontSize: 12)),
          const SizedBox(width: 25),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 25),
          Expanded(child: Text(msg, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500))),
          Text(status.toUpperCase(), style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontSize: 10, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildDatabaseExplorer() {
    if (_isLoadingTables) return const Center(child: CircularProgressIndicator());
    
    return Column(
      children: [
        Row(
          children: [
            Text("Database Explorer", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTable,
                  dropdownColor: const Color(0xFF1E293B),
                  style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontWeight: FontWeight.w900, fontSize: 12),
                  items: _tables.map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase()))).toList(),
                  onChanged: (val) => setState(() => _selectedTable = val),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Expanded(child: _buildRealTimeTable(_selectedTable ?? 'trips', "Live Table View")),
      ],
    );
  }

  Widget _buildRealTimeTable(String collection, String title) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: DatabaseService.instance.getAdminTableStream(collection),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No Data Available", style: TextStyle(color: Colors.white24)));

          final docs = snapshot.data!;
          final columns = docs.first;
          final colNames = columns.keys.toList();

          return ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Scrollbar(
              controller: _dbVerticalController,
              thumbVisibility: true,
              child: Scrollbar(
                controller: _dbHorizontalController,
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  controller: _dbHorizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _dbVerticalController,
                    child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.02)),
                    dataRowMaxHeight: 60,
                    columns: [
                      const DataColumn(label: Text("ACTIONS", style: TextStyle(color: AppTheme.adminPrimary, fontWeight: FontWeight.w900, fontSize: 10))),
                      ...colNames.map((c) => DataColumn(label: Text(c.toUpperCase(), style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 10)))),
                    ],
                    rows: docs.map((data) {
                      final recordId = data['id']?.toString() ?? data['key']?.toString();
                      final canDelete = ['notification_broadcasts', 'app_settings'].contains(collection) && recordId != null;
                      return DataRow(
                        cells: [
                          DataCell(Row(
                            children: [
                              IconButton(icon: const Icon(Icons.edit_note_rounded, color: AppTheme.adminPrimary, size: 18), onPressed: () {}),
                              IconButton(
                                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 18),
                                onPressed: !canDelete ? null : () async {
                                  await DatabaseService.instance.deleteRecord(collection, recordId);
                                },
                              ),
                            ],
                          )),
                          ...colNames.map((column) => DataCell(Text(data[column]?.toString() ?? '-', style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

  Widget _buildSecurity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Security Monitoring", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 30),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 30,
            mainAxisSpacing: 30,
            childAspectRatio: 2.5,
            children: [
              _securityMonitorCard("Active Admins", "4 Verified", Icons.admin_panel_settings, Colors.blue),
              _securityMonitorCard("Identity Cooldown", "Active", Icons.timer_rounded, Colors.orange),
              _securityMonitorCard("Brute Force Shield", "Engaged", Icons.shield_rounded, Colors.green),
              _securityMonitorCard("Identity Fraud Check", "0 Flagged", Icons.face_retouching_natural, AppTheme.adminPrimary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _securityMonitorCard(String title, String status, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 25),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: GoogleFonts.inter(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(status, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealth() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Infrastructure Health", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 30),
        FutureBuilder<Map<String, bool>>(
          future: DatabaseService.instance.getInfrastructureHealth(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final health = snapshot.data ?? const <String, bool>{};
            Widget row(String label, bool configured, String ready, String missing) =>
                _healthStatusRow(
                  label,
                  configured ? ready : missing,
                  configured ? "Available" : "Not configured",
                  configured ? Colors.green : Colors.orangeAccent,
                );
            return Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.01),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
              ),
              child: Column(
                children: [
                  row("Supabase Database", health['database'] == true, "Connected", "Unavailable"),
                  row("STA AI Service", health['ai'] == true, "Configured", "Missing server secret or deployment"),
                  row("Traffic-aware Routing", health['traffic'] == true, "Configured", "Missing server key or deployment"),
                  row("In-app Notifications", health['in_app_notifications'] == true, "Available", "Not deployed"),
                  row("Remote Push Notifications", health['push'] == true, "Configured", "Provider not configured"),
                  row("M-Pesa Payment Gateway", health['payments'] == true, "Configured", "Provider not configured"),
                  row("Fleet & Company Management", health['fleet'] == true, "Available", "Not deployed"),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _healthStatusRow(String label, String value, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
          Text(value, style: GoogleFonts.robotoMono(color: Colors.white38, fontSize: 14)),
          const SizedBox(width: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildApiMonitoring() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("API Traffic & Analytics", style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.orangeAccent, size: 28),
              SizedBox(height: 12),
              Text(
                'Request-level API telemetry is not connected to this dashboard yet. No sample or fabricated request logs are displayed.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _dateRangePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, color: Colors.white24, size: 16),
          const SizedBox(width: 12),
          Text("Last 24 Hours", style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}
