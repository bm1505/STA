import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import '../widgets/profile_image_widget.dart';
import '../services/database_service.dart';
import '../widgets/postgres_image.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  String _searchQuery = "";
  String _statusFilter = "All";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.adminBg,
      body: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(child: _buildDriversList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("DRIVER MANAGEMENT",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              Text("Verify documents and monitor performance",
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
            ],
          ),
          const Spacer(),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      width: 300,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: const InputDecoration(
          hintText: "Search by name or email...",
          hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: AppTheme.adminPrimary, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          _filterChip("All"),
          _filterChip("Online"),
          _filterChip("Offline"),
          _filterChip("Pending Verification"),
        ],
      ),
    );
  }

  Widget _filterChip(String label) {
    bool isSelected = _statusFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.adminPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? AppTheme.adminPrimary : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: isSelected ? Colors.black : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildDriversList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var drivers = snapshot.data!.docs.map((doc) {
          return UserModel.fromFirestore(doc);
        }).toList();

        // Apply filters
        if (_searchQuery.isNotEmpty) {
          drivers = drivers.where((d) => 
            d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            d.email.toLowerCase().contains(_searchQuery.toLowerCase())
          ).toList();
        }

        if (_statusFilter == "Online") {
          drivers = drivers.where((d) => d.isOnline).toList();
        } else if (_statusFilter == "Offline") {
          drivers = drivers.where((d) => !d.isOnline).toList();
        }

        if (drivers.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: drivers.length,
          itemBuilder: (context, index) => _buildDriverCard(drivers[index]),
        );
      },
    );
  }

  Widget _buildDriverCard(UserModel driver) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          ProfileImageWidget(
            imageUrl: driver.profileImageUrl,
            name: driver.name,
            radius: 25,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(driver.email,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          _buildRatingCell(driver.rating),
          const SizedBox(width: 24),
          _buildStatusChip(driver.isOnline),
          const SizedBox(width: 24),
          _buildActionButtons(driver),
        ],
      ),
    );
  }

  Widget _buildRatingCell(dynamic rating) {
    double r = (rating as num?)?.toDouble() ?? 5.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 14),
        const SizedBox(width: 5),
        Text(r.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildStatusChip(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isOnline ? Colors.green : Colors.red).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color:
                (isOnline ? Colors.green : Colors.red).withValues(alpha: 0.2)),
      ),
      child: Text(
        isOnline ? "ONLINE" : "OFFLINE",
        style: TextStyle(
            color: isOnline ? Colors.green : Colors.red,
            fontSize: 10,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showDriverDetails(UserModel driver) {
    showDialog(
      context: context,
      builder: (context) => StreamBuilder<Map<String, dynamic>?>(
        stream: DatabaseService.instance.getWalletStream(driver.id),
        builder: (context, walletSnap) {
          double walletBalance = (walletSnap.data?['balance'] as num?)?.toDouble() ?? 0.0;
          double totalEarned = (walletSnap.data?['totalEarned'] as num?)?.toDouble() ?? (driver.earnings ?? 0.0);

          return Dialog(
            backgroundColor: AppTheme.adminSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 600,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(30, 30, 30, 10),
                    child: Row(
                      children: [
                        ProfileImageWidget(
                          imageUrl: driver.profileImageUrl,
                          name: driver.name,
                          radius: 40,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(driver.name.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Text(driver.email,
                                  style: const TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white24))
                      ],
                    ),
                  ),
                  const Divider(height: 30, color: Colors.white10),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CORE INFORMATION", 
                            style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 15),
                          _detailRow("Phone", driver.phoneNumber),
                          _detailRow("Vehicle", "${driver.vehicleType} (${driver.carModel})"),
                          _detailRow("Plate Number", driver.carPlate ?? "N/A"),
                          _detailRow("Color", driver.carColor ?? "N/A"),
                          _detailRow("Wallet Balance", "TSH ${NumberFormat('#,###').format(walletBalance)}"),
                          _detailRow("Total Earnings", "TSH ${NumberFormat('#,###').format(totalEarned)}"),
                          _detailRow("Total Rides", driver.totalRides.toString()),
                          _detailRow("Rating", driver.rating.toStringAsFixed(1)),
                          _detailRow("Joined", DateFormat('MMM dd, yyyy').format(driver.createdAt)),
                          const SizedBox(height: 30),
                          Text("DRIVER DOCUMENTS", 
                            style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 15),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            mainAxisSpacing: 15,
                            crossAxisSpacing: 15,
                            childAspectRatio: 1.4,
                            children: [
                              _buildDocCard("Driving License", driver.licenseUrl),
                              _buildDocCard("Insurance", driver.insuranceUrl),
                              _buildDocCard("National ID", driver.nationalIdUrl),
                              _buildDocCard("Vehicle Photo", driver.vehiclePhotoUrl),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Text("USER REVIEWS & FEEDBACK", 
                            style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 15),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('ratings')
                                .where('driverId', isEqualTo: driver.id)
                                .orderBy('timestamp', descending: true)
                                .limit(10)
                                .snapshots(),
                            builder: (context, reviewSnap) {
                              if (!reviewSnap.hasData) return const Center(child: CircularProgressIndicator());
                              final reviews = reviewSnap.data!.docs;
                              if (reviews.isEmpty) return const Text("No reviews yet", style: TextStyle(color: Colors.white24, fontSize: 12));
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: reviews.length,
                                itemBuilder: (context, index) {
                                  final rev = reviews[index].data() as Map<String, dynamic>;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(rev['riderName'] ?? "Rider", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                            Row(
                                              children: List.generate(5, (i) => Icon(Icons.star, size: 12, color: i < (rev['rating'] ?? 0) ? Colors.amber : Colors.white10)),
                                            ),
                                          ],
                                        ),
                                        if (rev['comment'] != null && rev['comment'].toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(rev['comment'], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          rev['timestamp'] != null 
                                            ? DateFormat('MMM dd, yyyy').format((rev['timestamp'] as Timestamp).toDate())
                                            : "",
                                          style: const TextStyle(color: Colors.white24, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 30),
                          if (driver.profileEditStatus == 'requested')
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      "Driver requested to change profile info.",
                                      style: TextStyle(color: Colors.orange, fontSize: 13),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection('drivers')
                                          .doc(driver.id)
                                          .update({'profileEditStatus': 'allowed'});
                                      if (context.mounted) Navigator.pop(context);
                                    },
                                    child: const Text("ALLOW", style: TextStyle(fontWeight: FontWeight.bold)),
                                  )
                                ],
                              ),
                            ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocCard(String label, String? url) {
    final bool isPostgres = url != null && url.startsWith('pg://');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: url != null && url.isNotEmpty
                  ? (isPostgres 
                      ? PostgresImage(pgUrl: url, fit: BoxFit.cover)
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 30),
                          ),
                        ))
                  : const Center(
                      child: Text("No Document", style: TextStyle(color: Colors.white24, fontSize: 10)),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActionButtons(UserModel driver) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined, color: AppTheme.adminPrimary, size: 20),
          onPressed: () => _showDriverDetails(driver),
        ),
        IconButton(
          icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white54, size: 20),
          onPressed: () => _showPayoutDialog(driver),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
          onPressed: () => _deleteDriver(driver.id, driver.name),
        ),
      ],
    );
  }

  void _showPayoutDialog(UserModel driver) {
    // Implementation of payout dialog
  }

  void _deleteDriver(String id, String name) {
    // Implementation of delete driver
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_accounts_rounded, size: 100, color: Colors.white10),
          const SizedBox(height: 20),
          Text("NO DRIVERS FOUND", style: GoogleFonts.poppins(color: Colors.white54, letterSpacing: 2)),
        ],
      ),
    );
  }
}
