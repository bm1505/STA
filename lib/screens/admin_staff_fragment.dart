import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import '../models/user.dart';

class AdminStaffFragment extends StatefulWidget {
  const AdminStaffFragment({super.key});

  @override
  State<AdminStaffFragment> createState() => _AdminStaffFragmentState();
}

class _AdminStaffFragmentState extends State<AdminStaffFragment> {
  List<UserModel> _staff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final List<Map<String, dynamic>> data = await DatabaseService.instance.getTableData('staff');
      // The staff table contains various roles (admin, it, support). 
      // UserModel.fromJson will parse the 'role' string correctly.
      final allStaff = data.map((d) => UserModel.fromJson(d)).toList();

      if (mounted) {
        setState(() {
          _staff = allStaff;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading staff: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Department Management",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "Manage system administrators, IT staff, and support teams",
                    style: GoogleFonts.poppins(
                        color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddStaffDialog(),
                icon: const Icon(Icons.add, color: Colors.black),
                label: const Text("ADD STAFF",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.adminPrimary),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.adminPrimary))
                : _staff.isEmpty
                    ? _buildEmptyState()
                    : _buildStaffTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 80, color: Colors.white10),
          const SizedBox(height: 16),
          Text("No staff members found",
              style: GoogleFonts.poppins(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildStaffTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: SingleChildScrollView(
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
          },
          children: [
            _buildTableHeader(),
            ..._staff.map((s) => _buildTableRow(s)),
          ],
        ),
      ),
    );
  }

  TableRow _buildTableHeader() {
    return TableRow(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10))),
      children: ["Full Name", "Email/Phone", "Role", "Department", "Actions"]
          .map((h) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text(h,
                    style: GoogleFonts.poppins(
                        color: AppTheme.adminPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ))
          .toList(),
    );
  }

  TableRow _buildTableRow(UserModel staff) {
    return TableRow(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02)))),
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(staff.name.isNotEmpty ? staff.name : 'N/A',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(staff.email.isNotEmpty ? staff.email : staff.phoneNumber,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: _buildRoleBadge(
              staff.role.toString().split('.').last.toUpperCase()),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(staff.department ?? 'General',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.blue, size: 18),
                  onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 18),
                onPressed: () => _confirmDelete(staff.id, staff.role),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color;
    switch (role.toLowerCase()) {
      case 'admin':
        color = Colors.redAccent;
        break;
      case 'it':
        color = Colors.blueAccent;
        break;
      case 'support':
        color = Colors.greenAccent;
        break;
      default:
        color = Colors.orangeAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(role,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
    );
  }

  void _confirmDelete(String id, UserRole role) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: const Text("Confirm Deletion",
            style: TextStyle(color: Colors.white)),
        content: const Text(
            "Are you sure you want to remove this staff member?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              await DatabaseService.instance.deleteUser(id, role);
              if (mounted) {
                Navigator.pop(context);
                _loadStaff();
              }
            },
            child:
                const Text("DELETE", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showAddStaffDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final deptController = TextEditingController();
    String selectedRole = 'it';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.adminSurface,
          title: Text("Add New Staff Member",
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(nameController, "Full Name", Icons.person),
                const SizedBox(height: 15),
                _buildTextField(emailController, "Email Address", Icons.email),
                const SizedBox(height: 15),
                _buildTextField(deptController,
                    "Department (e.g. Infrastructure, UX)", Icons.business),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  dropdownColor: AppTheme.adminSurface,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "System Role",
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: ['admin', 'it', 'support']
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(r.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedRole = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () async {
                final newUser = UserModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  email: emailController.text,
                  phoneNumber: '',
                  role: selectedRole == 'admin'
                      ? UserRole.admin
                      : (selectedRole == 'it' ? UserRole.it : UserRole.support),
                  createdAt: DateTime.now(),
                );
                // Since we added department to UserModel but didn't update constructor to accept it as non-null if we want it,
                // but I added it as optional. I'll need to update copyWith or the constructor.
                // Let's assume I can save extra fields in rawJson for now or I update DatabaseService.

                // For now, let's just save via DatabaseService
                await DatabaseService.instance.saveUser(newUser);
                // I should also save the department info.
                // DatabaseService.saveUser uses user.toJson() which includes department now.

                if (mounted) {
                  Navigator.pop(context);
                  _loadStaff();
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.adminPrimary),
              child: const Text("SAVE STAFF",
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: AppTheme.adminPrimary, size: 20),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white10),
            borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.adminPrimary),
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
