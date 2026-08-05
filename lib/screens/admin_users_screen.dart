import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../widgets/profile_image_widget.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<UserModel> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final List<dynamic> riders = await DatabaseService.instance.getTableData('riders');
      final List<dynamic> drivers = await DatabaseService.instance.getTableData('drivers');
      final List<dynamic> staff = await DatabaseService.instance.getTableData('staff');
      
      final List<UserModel> all = [];
      // Chukua data na utumie Role halisi iliyopo kwenye Database
      all.addAll(riders.map((d) => UserModel.fromJson(d)));
      all.addAll(drivers.map((d) => UserModel.fromJson(d)));
      all.addAll(staff.map((d) => UserModel.fromJson(d)));

      if (mounted) {
        setState(() {
          // Chuja ili kuonyesha Riders pekee kwenye screen hii ya Passenger Management
          _users = all.where((u) => u.role == UserRole.rider).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: Text("Delete User?",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text(
            "Are you sure you want to remove $name from the system? Their history will be archived.",
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("DELETE",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm == true) {
      // Find the user to get their role
      final user = _users.firstWhere((u) => u.id == id);
      await DatabaseService.instance.deleteUser(id, user.role);
      _fetchUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.adminBg,
      appBar: AppBar(
        backgroundColor: AppTheme.adminSurface,
        elevation: 0,
        title: Text('Passenger Management',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, color: AppTheme.adminPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.adminPrimary),
            onPressed: _fetchUsers,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.adminPrimary))
          : _users.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 30),
                          _buildUsersTable(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("TOTAL PASSENGERS",
            style: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5)),
        Text("${_users.length} Registered",
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildUsersTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            horizontalMargin: 25,
            columnSpacing: 60,
            headingRowHeight: 70,
            dataRowMaxHeight: 70,
            headingRowColor:
                WidgetStateProperty.all(Colors.white.withValues(alpha: 0.02)),
            columns: [
              DataColumn(label: _tableHeader('NAME & CONTACT')),
              DataColumn(label: _tableHeader('GENDER')),
              DataColumn(label: _tableHeader('JOINED DATE')),
              DataColumn(label: _tableHeader('RATING')),
              DataColumn(label: _tableHeader('ACTIONS')),
            ],
            rows: _users.map((user) {
              String? pic = user.profileImageUrl;
              DateTime createdAt = user.createdAt;

              return DataRow(cells: [
                DataCell(Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileImageWidget(
                        imageUrl: pic,
                        name: user.name,
                        radius: 20,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              user.phoneNumber,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
                DataCell(Text(user.gender?.toUpperCase() ?? 'N/A',
                    softWrap: false,
                    style: const TextStyle(color: Colors.white70, fontSize: 12))),
                DataCell(Text(DateFormat('MMM dd, yyyy').format(createdAt),
                    softWrap: false,
                    style: const TextStyle(color: Colors.white38))),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 14),
                    const SizedBox(width: 5),
                    Text(user.rating.toString(),
                        style: const TextStyle(color: Colors.white70)),
                  ],
                )),
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: Colors.white38, size: 20),
                      onPressed: () {
                        Navigator.pushNamed(context, '/chat', arguments: {
                          'receiverId': user.id,
                          'receiverName': user.name,
                          'senderId': 'admin',
                          'senderName': 'Admin',
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      onPressed: () => _deleteUser(user.id, user.name),
                    ),
                  ],
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _tableHeader(String text) {
    return Text(text,
        softWrap: false,
        style: GoogleFonts.poppins(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded,
              size: 100, color: Colors.white10),
          const SizedBox(height: 20),
          Text("NO REGISTERED USERS",
              style:
                  GoogleFonts.poppins(color: Colors.white54, letterSpacing: 2)),
        ],
      ),
    );
  }
}
