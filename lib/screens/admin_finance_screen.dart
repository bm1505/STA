import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key});

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.adminBg,
        appBar: AppBar(
          backgroundColor: AppTheme.adminSurface,
          elevation: 0,
          title: Text("Financial Management", 
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Payout Requests"),
              Tab(text: "Wallet Top-ups"),
            ],
            indicatorColor: AppTheme.adminPrimary,
            labelColor: AppTheme.adminPrimary,
            unselectedLabelColor: Colors.white54,
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRevenueSummary(),
                  const SizedBox(height: 30),
                  Text("Pending Payouts (Pay Drivers)", 
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 15),
                  _buildWithdrawalRequests(),
                ],
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopUpInfo(),
                  const SizedBox(height: 25),
                  Text("Pending Top-up Verifications", 
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 15),
                  _buildTopUpRequests(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueSummary() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService.instance.getAllWalletsStream(),
      builder: (context, snapshot) {
        double totalToPay = 0;
        double totalToCollect = 0;
        for (final wallet in snapshot.data ?? const <Map<String, dynamic>>[]) {
          final balance = (wallet['balance'] as num?)?.toDouble() ?? 0;
          if (balance > 0) totalToPay += balance;
          if (balance < 0) totalToCollect += balance.abs();
        }
        return Row(
          children: [
            _buildFinCard("TOTAL TO PAY (DRIVERS)", totalToPay, Colors.orangeAccent, Icons.outbox),
            const SizedBox(width: 20),
            _buildFinCard("TOTAL TO COLLECT (CASH)", totalToCollect, Colors.greenAccent, Icons.move_to_inbox),
          ],
        );
      },
    );
  }

  Widget _buildFinCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.adminSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text("TZS ${NumberFormat('#,###').format(amount)}", 
              style: GoogleFonts.robotoMono(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalRequests() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService.instance.getPendingWithdrawals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState("No pending payout requests");

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) => _buildWithdrawalCard(snapshot.data![index]),
        );
      },
    );
  }

  Widget _buildWithdrawalCard(Map<String, dynamic> req) {
    final amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
    final userId = req['userId'] ?? '';
    final docId = req['id'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<UserModel?>(
              future: DatabaseService.instance.getUser(userId),
              builder: (context, snap) {
                String name = "Loading...";
                String method = "M-Pesa";
                String number = "";
                if (snap.hasData && snap.data != null) {
                  final data = snap.data!;
                  name = data.name.isEmpty ? 'Unknown' : data.name;
                  method = data.payoutMethod ?? 'M-Pesa';
                  number = data.payoutNumber ?? data.phoneNumber;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: number));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Number copied!")));
                      },
                      child: Row(
                        children: [
                          Text("$method: $number", style: const TextStyle(color: AppTheme.adminPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          const Icon(Icons.copy, size: 12, color: AppTheme.adminPrimary),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("TZS ${NumberFormat('#,###').format(amount)}", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _confirmRejection(docId),
                    child: const Text("REJECT", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    ),
                    onPressed: () => _confirmApproval(docId, userId, amount),
                    child: const Text("MARK AS PAID", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRejection(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: const Text("Reject Payout?", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure? The request will be cancelled.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("REJECT", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) await DatabaseService.instance.rejectWithdrawal(id);
  }

  Future<void> _confirmApproval(String id, String userId, double amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: const Text("Confirm Payment", style: TextStyle(color: Colors.white)),
        content: Text("Have you already sent TZS ${NumberFormat('#,###').format(amount)} to the driver's phone? Only click 'YES' if the money has been sent.",
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NOT YET")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("YES, I PAID")),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseService.instance.approveWithdrawal(id, userId, amount);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payout marked as completed")));
    }
  }

  Widget _buildTopUpInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              "Top-ups are for drivers who want to pay commissions in advance. Verify the payment in your bank/mobile money account before clicking 'VERIFY'.",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopUpRequests() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService.instance.getPendingTopUps(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        // Filter for only 'topup' type requests to separate from ride payments
        final topups = snapshot.data?.where((req) => req['status'] == 'pending').toList() ?? [];
        
        if (topups.isEmpty) return _buildEmptyState("No pending top-up requests");
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topups.length,
          itemBuilder: (context, index) => _buildTopUpCard(topups[index]),
        );
      },
    );
  }

  Widget _buildTopUpCard(Map<String, dynamic> req) {
    final amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
    final userId = req['userId'] ?? '';
    final docId = req['id'] ?? '';
    final phone = req['phoneNumber'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blue.withValues(alpha: 0.1),
            child: const Icon(Icons.add_card, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<UserModel?>(
                  future: DatabaseService.instance.getUser(userId),
                  builder: (context, snap) {
                    String name = "Loading...";
                    if (snap.hasData && snap.data != null) {
                      name = snap.data!.name.isEmpty ? 'Unknown' : snap.data!.name;
                    }
                    return Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15));
                  },
                ),
                Text("Source Phone: $phone", style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("TZS ${NumberFormat('#,###').format(amount)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(onPressed: () => _confirmTopUpRejection(docId), child: const Text("REJECT", style: TextStyle(color: Colors.redAccent, fontSize: 11))),
                  ElevatedButton(
                    onPressed: () => _confirmTopUpApproval(docId, userId, amount),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.adminPrimary, foregroundColor: Colors.black, minimumSize: const Size(70, 32)),
                    child: const Text("VERIFY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmTopUpRejection(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: const Text("Reject Top-up?", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to reject this top-up? Make sure the money was not received.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("REJECT", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) await DatabaseService.instance.rejectTopUp(id);
  }

  Future<void> _confirmTopUpApproval(String id, String userId, double amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title: const Text("Approve Top-up?", style: TextStyle(color: Colors.white)),
        content: Text("Confirm you have received TZS ${NumberFormat('#,###').format(amount)} and want to credit the driver's wallet.",
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("VERIFY")),
        ],
      ),
    );
    if (confirm == true) await DatabaseService.instance.approveTopUp(id, userId, amount);
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: AppTheme.adminSurface, borderRadius: BorderRadius.circular(16)),
      child: Center(child: Text(message, style: const TextStyle(color: Colors.white24))),
    );
  }
}
