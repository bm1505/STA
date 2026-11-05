import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sta/providers/auth_provider.dart';
import 'package:sta/utils/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'admin_dashboard_fragment.dart';
import 'admin_drivers_screen.dart';
import 'admin_users_screen.dart';
import 'admin_trip_history_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_map_screen.dart';
import 'admin_live_trips_screen.dart';
import 'admin_driver_verification_fragment.dart';
import 'admin_staff_fragment.dart';
import 'admin_system_audit_screen.dart';
import 'fleet_management_screen.dart';
import 'notifications_screen.dart';
import 'admin_safety_events_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_finance_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;
  final Set<String> _expandedSections = {"OPERATIONS", "MANAGEMENT", "REPORTS", "SYSTEM"};
  final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription<List<Map<String, dynamic>>>? _sosSubscription;
  final Set<String> _seenSosAlerts = <String>{};

  @override
  void initState() {
    super.initState();
    _initTts();
    _listenForSosAlerts();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _sosSubscription?.cancel();
    super.dispose();
  }

  void _listenForSosAlerts() {
    _sosSubscription = Supabase.instance.client
        .from('sos_alerts')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .listen((rows) {
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || !_seenSosAlerts.add(id)) continue;
        _showSosPopup(id, {
          ...row,
          'userId': row['user_id'],
          'timestamp': row['created_at'],
        });
      }
    }, onError: (Object error) {
      debugPrint('STA SOS subscription failed: $error');
    });
  }

  void _showSosPopup(String alertId, Map<String, dynamic> data) {
    _flutterTts.speak("Emergency S.O.S. alert. Immediate action required for user ${data['userId']}.");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Text("EMERGENCY SOS", 
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("User ID: ${data['userId']}", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            Text("Time: ${data['timestamp'] != null ? DateTime.tryParse(data['timestamp'].toString())?.toLocal().toString() ?? 'Unknown' : 'Unknown'}",
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            const Text("Immediate action required! Track this user on the map.",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _flutterTts.stop();
              Navigator.pop(context);
            },
            child: const Text("DISMISS", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red.shade900),
            onPressed: () {
              _flutterTts.stop();
              Navigator.pop(context);
              setState(() => _selectedIndex = 1); // Switch to Fleet Map
            },
            child: const Text("VIEW ON MAP"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              _flutterTts.stop();
              await Supabase.instance.client.rpc('sta_resolve_sos', params: {'p_alert_id': alertId});
              Navigator.pop(context);
            },
            child: const Text("RESOLVE"),
          ),
        ],
      ),
    );
  }

  final List<AdminMenuItem> _menuItems = [
    AdminMenuItem("Dashboard", Icons.dashboard_rounded, 0),
    AdminMenuItem("Fleet Map", Icons.map_rounded, 1),
    AdminMenuItem("Live Trips", Icons.track_changes_rounded, 2),
    AdminMenuItem("Drivers", Icons.drive_eta_rounded, 3),
    AdminMenuItem("Verifications", Icons.verified_user_rounded, 4),
    AdminMenuItem("Riders", Icons.people_alt_rounded, 5),
    AdminMenuItem("Trip History", Icons.history_rounded, 6),
    AdminMenuItem("Finance & Payouts", Icons.account_balance_wallet_rounded, 7),
    AdminMenuItem("Departments", Icons.lan_rounded, 8),
    AdminMenuItem("Broadcasts", Icons.campaign_rounded, 9),
    AdminMenuItem("Configurations", Icons.settings_suggest_rounded, 10),
    AdminMenuItem("System Audit", Icons.security_rounded, 11),
    AdminMenuItem("Fleet Management", Icons.directions_bus_rounded, 12),
    AdminMenuItem("Notification Inbox", Icons.notifications_none_rounded, 13),
    AdminMenuItem("Safety & Risk", Icons.health_and_safety_rounded, 14),
  ];

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        const AdminDashboardFragment(),
        const AdminMapScreen(),
        const AdminLiveTripsScreen(),
        const AdminDriversScreen(),
        const AdminDriverVerificationFragment(),
        const AdminUsersScreen(),
        const AdminTripHistoryScreen(),
        const AdminFinanceScreen(),
        const AdminStaffFragment(),
        const AdminNotificationsScreen(),
        const AdminSettingsScreen(),
        const AdminSystemAuditScreen(),
        const FleetManagementScreen(),
        const NotificationsScreen(),
        const AdminSafetyEventsScreen(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Darker Navy for Pro look
      drawer: isMobile ? _buildSidebar(context) : null,
      appBar: isMobile
          ? AppBar(
              title: Text("STA ADMIN",
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF1E293B),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(context),
          Expanded(
            child: Column(
              children: [
                if (!isMobile) _buildTopBar(context, auth),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: _buildBody(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AuthProvider auth) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: Colors.transparent,
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _menuItems[_selectedIndex].title.toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontSize: 24,
                ),
              ),
              Text(
                "Welcome back, ${auth.currentUser?.name ?? 'Admin'}",
                style: GoogleFonts.inter(color: Colors.white30, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none_rounded,
                  color: Colors.white70, size: 24),
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 25),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(auth.currentUser?.name ?? "Admin",
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text(
                        auth.currentUser?.role
                                .toString()
                                .split('.')
                                .last
                                .toUpperCase() ??
                            "STAFF",
                        style: GoogleFonts.inter(
                            color: AppTheme.adminPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(width: 15),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.adminPrimary, width: 2),
                  ),
                  child: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF1E293B),
                    child: Icon(Icons.person, color: AppTheme.adminPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 20),
                  onPressed: () {
                    auth.logout();
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/', (route) => false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userRole = auth.currentUser?.role.toString().toLowerCase() ?? '';
    final isIT = userRole.contains('it') || userRole.contains('admin');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: _isSidebarCollapsed ? 100 : 300,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        children: [
          // Logo Section
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.adminPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: AppTheme.adminPrimary, size: 28),
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 16),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "STA RIDE",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        "ENTERPRISE",
                        style: GoogleFonts.inter(
                          color: AppTheme.adminPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
          ),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              children: [
                _buildSectionHeader("OPERATIONS"),
                if (_expandedSections.contains("OPERATIONS") || _isSidebarCollapsed) ...[
                  _buildSidebarItem(_menuItems[0], _selectedIndex == 0),
                  _buildSidebarItem(_menuItems[1], _selectedIndex == 1),
                  _buildSidebarItem(_menuItems[2], _selectedIndex == 2),
                ],
                const SizedBox(height: 10),
                _buildSectionHeader("MANAGEMENT"),
                if (_expandedSections.contains("MANAGEMENT") || _isSidebarCollapsed) ...[
                  _buildSidebarItem(_menuItems[3], _selectedIndex == 3),
                  _buildSidebarItem(_menuItems[4], _selectedIndex == 4),
                  _buildSidebarItem(_menuItems[5], _selectedIndex == 5),
                  _buildSidebarItem(_menuItems[12], _selectedIndex == 12),
                ],
                const SizedBox(height: 10),
                _buildSectionHeader("REPORTS"),
                if (_expandedSections.contains("REPORTS") || _isSidebarCollapsed) ...[
                  _buildSidebarItem(_menuItems[6], _selectedIndex == 6),
                  _buildSidebarItem(_menuItems[7], _selectedIndex == 7),
                  _buildSidebarItem(_menuItems[9], _selectedIndex == 9),
                  _buildSidebarItem(_menuItems[13], _selectedIndex == 13),
                ],
                const SizedBox(height: 10),
                _buildSectionHeader("SYSTEM"),
                if (_expandedSections.contains("SYSTEM") || _isSidebarCollapsed) ...[
                  _buildSidebarItem(_menuItems[8], _selectedIndex == 8),
                  _buildSidebarItem(_menuItems[10], _selectedIndex == 10),
                  if (isIT) _buildSidebarItem(_menuItems[11], _selectedIndex == 11),
                  _buildSidebarItem(_menuItems[14], _selectedIndex == 14),
                ],
              ],
            ),
          ),

          // Footer Info
          if (!_isSidebarCollapsed)
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.blue, size: 16),
                  const SizedBox(width: 10),
                  Text("System Stable", style: GoogleFonts.inter(color: Colors.white30, fontSize: 11)),
                ],
              ),
            ),

          // Collapse Toggle
          IconButton(
            icon: Icon(
              _isSidebarCollapsed
                  ? Icons.align_horizontal_left_rounded
                  : Icons.align_horizontal_right_rounded,
              color: Colors.white24,
            ),
            onPressed: () =>
                setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    if (_isSidebarCollapsed) return const Padding(
      padding: EdgeInsets.symmetric(vertical: 15),
      child: Divider(color: Colors.white10, indent: 10, endIndent: 10),
    );
    
    final Set<String>? sections = _expandedSections;
    bool isExpanded = sections == null || sections.contains(title);
    
    return InkWell(
      onTap: () {
        if (_expandedSections == null) return;
        setState(() {
          if (isExpanded) {
            _expandedSections.remove(title);
          } else {
            _expandedSections.add(title);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 15, top: 20, bottom: 10, right: 10),
        child: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppTheme.adminMuted.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Icon(
              isExpanded ? Icons.remove : Icons.add,
              color: Colors.white10,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(AdminMenuItem item, bool isSelected) {
    String displayTitle = item.title;
    if (item.title == "Trip History") displayTitle = "History & Revenue";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          if (item.title == "System Audit") {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminSystemAuditScreen()),
            );
            return;
          }
          setState(() => _selectedIndex = item.index);
          if (MediaQuery.of(context).size.width < 1100) {
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      AppTheme.adminPrimary.withValues(alpha: 0.15),
                      AppTheme.adminPrimary.withValues(alpha: 0.02),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(
                    color: AppTheme.adminPrimary.withValues(alpha: 0.1),
                    width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: isSelected ? AppTheme.adminPrimary : Colors.white24,
                size: 22,
              ),
              if (!_isSidebarCollapsed) ...[
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    displayTitle,
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : Colors.white30,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (isSelected && !_isSidebarCollapsed)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: AppTheme.adminPrimary, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppTheme.adminPrimary, blurRadius: 10)]),
                )
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMenuItem {
  final String title;
  final IconData icon;
  final int index;

  AdminMenuItem(this.title, this.icon, this.index);
}
