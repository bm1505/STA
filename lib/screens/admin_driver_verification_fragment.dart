import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../widgets/profile_image_widget.dart';
import '../widgets/postgres_image.dart';
import '../services/database_service.dart';

class AdminDriverVerificationFragment extends StatefulWidget {
  const AdminDriverVerificationFragment({super.key});

  @override
  State<AdminDriverVerificationFragment> createState() =>
      _AdminDriverVerificationFragmentState();
}

class _AdminDriverVerificationFragmentState
    extends State<AdminDriverVerificationFragment> {
  List<UserModel> _pendingDrivers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPendingDrivers();
  }

  Future<void> _fetchPendingDrivers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final drivers = await authProvider.getPendingDrivers();
      if (mounted) {
        setState(() {
          _pendingDrivers = drivers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching drivers: $e")),
        );
      }
    }
  }

  void _showImageOverlay(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: url.startsWith('pg://')
                      ? PostgresImage(
                          pgUrl: url,
                          fit: BoxFit.contain,
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (context, e, s) => _buildErrorView(url),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String url) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.broken_image, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        const Text("Could not load image", style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 8),
        SelectableText(url, style: const TextStyle(color: Colors.white24, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.adminPrimary));
    }

    if (_pendingDrivers.isEmpty) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "PENDING APPROVALS",
                style: GoogleFonts.poppins(
                    color: AppTheme.primaryGold,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2),
              ),
              IconButton(
                onPressed: _fetchPendingDrivers,
                icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
                tooltip: "Refresh List",
              ),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(child: _buildVerificationGrid()),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined, size: 80, color: Colors.white.withAlpha(25)),
          const SizedBox(height: 20),
          Text(
            "NO PENDING VERIFICATIONS",
            style: GoogleFonts.poppins(
                color: Colors.white24,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 25,
        mainAxisSpacing: 25,
        childAspectRatio: 2.2,
      ),
      itemCount: _pendingDrivers.length,
      itemBuilder: (context, index) {
        final driver = _pendingDrivers[index];
        return _buildDriverApprovalCard(driver);
      },
    );
  }

  Widget _buildDriverApprovalCard(UserModel driver) {
    bool isProfileUpdate = driver.profileEditStatus == 'submitted';
    
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(20),
        border: isProfileUpdate ? Border.all(color: Colors.blueAccent, width: 2) : null,
      ),
      child: Stack(
        children: [
          if (isProfileUpdate)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(10)),
                child: const Text("UPDATE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                ProfileImageWidget(
                  imageUrl: isProfileUpdate ? (driver.pendingUpdates?['profileImageUrl'] ?? driver.profileImageUrl) : driver.profileImageUrl,
                  name: isProfileUpdate ? (driver.pendingUpdates?['name'] ?? driver.name) : driver.name,
                  radius: 40,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        (isProfileUpdate ? (driver.pendingUpdates?['name'] ?? driver.name) : driver.name).toString().toUpperCase(),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isProfileUpdate 
                          ? "Updating: ${driver.pendingUpdates?['carPlate'] ?? driver.carPlate}"
                          : "${driver.vehicleType ?? 'VEHICLE'} • ${driver.carPlate ?? 'NO PLATE'}",
                        style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          _buildDocButton("LICENSE", isProfileUpdate ? (driver.pendingUpdates?['licenseUrl'] ?? driver.licenseUrl) : driver.licenseUrl),
                          const SizedBox(width: 8),
                          _buildDocButton("INSURANCE", isProfileUpdate ? (driver.pendingUpdates?['insuranceUrl'] ?? driver.insuranceUrl) : driver.insuranceUrl),
                          const SizedBox(width: 8),
                          _buildDocButton("ID", isProfileUpdate ? (driver.pendingUpdates?['nationalIdUrl'] ?? driver.nationalIdUrl) : driver.nationalIdUrl),
                        ],
                      )
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => _approveDriver(driver),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: Text(isProfileUpdate ? "APPLY" : "APPROVE", style: const TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                      onPressed: () => _rejectDriver(driver),
                      child: const Text("REJECT", style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocButton(String label, String? url) {
    final bool hasUrl = url != null && url.isNotEmpty;
    return InkWell(
      onTap: hasUrl ? () => _showImageOverlay(url) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: hasUrl ? Colors.blue.withAlpha(128) : Colors.white10),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          "✓ $label",
          style: TextStyle(
            color: hasUrl ? Colors.blue : Colors.white10,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _approveDriver(UserModel driver) async {
    try {
      bool isUpdate = driver.profileEditStatus == 'submitted';
      await DatabaseService.instance.updateDriverVerificationStatus(
        driver.id, 
        'verified',
        isUpdate: isUpdate,
      );
      _fetchPendingDrivers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${driver.name} ${isUpdate ? 'updates applied' : 'approved'} successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Approval failed: $e")),
        );
      }
    }
  }

  Future<void> _rejectDriver(UserModel driver) async {
    try {
      bool isUpdate = driver.profileEditStatus == 'submitted';
      await DatabaseService.instance.updateDriverVerificationStatus(
        driver.id, 
        'rejected',
        isUpdate: isUpdate,
      );
      _fetchPendingDrivers();
    } catch (e) {}
  }
}
