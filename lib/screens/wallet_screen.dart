import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../services/database_service.dart';
import '../services/payment_service.dart';
import '../utils/theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _balance = 0.0;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocalizationService.translate('wallet_title', lang),
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: DatabaseService.instance.getWalletStream(user?.id ?? ''),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            _balance = (snapshot.data!['balance'] as num?)?.toDouble() ?? 0.0;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBalanceCard(isDark, lang),
                const SizedBox(height: 30),
                
                // Pending Requests Section
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: DatabaseService.instance.getPendingRequestsStream(user?.id ?? ''),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "Pending Requests",
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                snapshot.data!.length.toString(),
                                style: const TextStyle(color: AppTheme.primaryGold, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 15),
                        ...snapshot.data!.map((req) {
                          double amount = (req['amount'] as num?)?.toDouble() ?? 0.0;
                          return _buildTransactionItem(
                            title: req['type'] == 'topup' ? 'Top-up Request' : 'Withdrawal Request',
                            subtitle: 'Waiting for transfer',
                            amount: req['type'] == 'topup' ? amount : -amount,
                            date: 'Pending',
                            isDark: isDark,
                            isPending: true,
                          );
                        }),
                        const SizedBox(height: 30),
                      ],
                    );
                  },
                ),

                Text(
                  LocalizationService.translate('recent_transactions', lang),
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 15),
                _buildTransactionList(user?.id ?? '', isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(bool isDark, String lang) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark 
            ? [const Color(0xFF1E1E1E), const Color(0xFF121212)]
            : [const Color(0xFF2C2C2C), Colors.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Text(
            LocalizationService.translate('your_balance', lang).toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            "TZS ${NumberFormat('#,###').format(_balance)}",
            style: GoogleFonts.poppins(
              color: AppTheme.primaryGold,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  icon: Icons.add_circle_outline,
                  label: LocalizationService.translate('add_money', lang),
                  onTap: () => _showTopUpDialog(),
                  isGold: true,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildActionBtn(
                  icon: Icons.file_download_outlined,
                  label: LocalizationService.translate('withdraw', lang),
                  onTap: () => _showWithdrawDialog(),
                  isGold: false,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionBtn({required IconData icon, required String label, required VoidCallback onTap, required bool isGold}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isGold ? AppTheme.primaryGold : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isGold ? Colors.black : Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isGold ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList(String userId, bool isDark) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService.instance.getTransactionsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                "No transactions yet",
                style: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          separatorBuilder: (context, index) => Divider(color: isDark ? Colors.white10 : Colors.black12),
          itemBuilder: (context, index) {
            final tx = snapshot.data![index];
            return _buildTransactionItem(
              title: tx['description'] ?? 'Transaction',
              subtitle: tx['type'] ?? 'payment',
              amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
              date: tx['timestamp'] != null 
                ? DateFormat('MMM dd, hh:mm a').format((tx['timestamp'] as Timestamp).toDate())
                : 'Recent',
              isDark: isDark,
            );
          },
        );
      },
    );
  }

  Widget _buildTransactionItem({
    required String title,
    required String subtitle,
    required double amount,
    required String date,
    required bool isDark,
    bool isPending = false,
  }) {
    final bool isPositive = amount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isPending 
              ? AppTheme.primaryGold.withValues(alpha: 0.1)
              : (isPositive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1)),
            child: Icon(
              isPending ? Icons.timer : (isPositive ? Icons.add : Icons.remove),
              color: isPending ? AppTheme.primaryGold : (isPositive ? Colors.green : Colors.red),
              size: 18,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isPositive ? '+' : ''}${NumberFormat('#,###').format(amount)}",
                style: TextStyle(
                  color: isPending ? AppTheme.primaryGold : (isPositive ? Colors.green : (isDark ? Colors.white : Colors.black)),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Text(
                date,
                style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTopUpDialog() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(LocalizationService.translate('top_up_title', lang),
            style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LocalizationService.translate('top_up_desc', lang),
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 25),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: LocalizationService.translate('example_amount', lang),
                  hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                  labelText: LocalizationService.translate('amount_tzs', lang),
                  labelStyle: const TextStyle(color: AppTheme.primaryGold),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryGold)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                  LocalizationService.translate('cancel', lang).toUpperCase(),
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                minimumSize: const Size(120, 45),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => _handleTopUp(amountController.text),
            child: Text(
                LocalizationService.translate('continue', lang).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTopUp(String amountStr) async {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final amount = double.tryParse(amountStr) ?? 0;
    if (amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(LocalizationService.translate('min_amount_100', lang))));
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;

    try {
      // Automatic Wallet Credit (Immediate)
      await DatabaseService.instance.approveTopUpDirect(user?.id ?? '', amount);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Wallet topped up successfully!"),
          backgroundColor: Colors.green));

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('error_occurred', lang)
              .replaceAll('{error}', e.toString())),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWithdrawDialog() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final user = auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String selectedMethod = user?.payoutMethod == 'Bank Transfer' ? 'Bank Transfer' : 'Mobile Money';
    String selectedProvider = user?.payoutMethod ?? 'M-Pesa';
    final targetController = TextEditingController(text: user?.payoutNumber ?? user?.phoneNumber);
    final amountController = TextEditingController();

    final List<String> networks = ['M-Pesa', 'Tigo Pesa', 'Airtel Money', 'Halo Pesa'];
    final List<String> banks = ['CRDB Bank', 'NMB Bank', 'NBC Bank', 'Absa Bank', 'Stanbic Bank', 'Equity Bank'];

    if (selectedMethod == 'Mobile Money' && !networks.contains(selectedProvider)) {
      selectedProvider = 'M-Pesa';
    } else if (selectedMethod == 'Bank Transfer' && !banks.contains(selectedProvider)) {
      selectedProvider = 'CRDB Bank';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(LocalizationService.translate('withdraw_title', lang),
                style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocalizationService.translate('select_payout_method', lang),
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  // Method Selection
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text('Mobile Money', style: TextStyle(fontSize: 11, color: selectedMethod == 'Mobile Money' ? Colors.black : (isDark ? Colors.white : Colors.black))),
                          selected: selectedMethod == 'Mobile Money',
                          selectedColor: AppTheme.primaryGold,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                selectedMethod = 'Mobile Money';
                                selectedProvider = 'M-Pesa';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('Bank Transfer', style: TextStyle(fontSize: 11, color: selectedMethod == 'Bank Transfer' ? Colors.black : (isDark ? Colors.white : Colors.black))),
                          selected: selectedMethod == 'Bank Transfer',
                          selectedColor: AppTheme.primaryGold,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() {
                                selectedMethod = 'Bank Transfer';
                                selectedProvider = 'CRDB Bank';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Provider Dropdown
                  Text(
                    selectedMethod == 'Mobile Money' ? 'Select Network' : 'Select Bank',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedProvider,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        items: (selectedMethod == 'Mobile Money' ? networks : banks).map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedProvider = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Target Number/Account
                  TextField(
                    controller: targetController,
                    keyboardType: selectedMethod == 'Mobile Money' ? TextInputType.phone : TextInputType.number,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      labelText: selectedMethod == 'Mobile Money' ? 'Phone Number' : 'Account Number',
                      labelStyle: const TextStyle(color: AppTheme.primaryGold, fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryGold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Amount
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      hintText: LocalizationService.translate('example_amount', lang),
                      hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                      labelText: LocalizationService.translate('amount_tzs', lang),
                      labelStyle: const TextStyle(color: AppTheme.primaryGold, fontSize: 13),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryGold)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                      LocalizationService.translate('cancel', lang).toUpperCase(),
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    minimumSize: const Size(120, 45),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _handleWithdraw(
                  amountController.text,
                  selectedMethod,
                  selectedProvider,
                  targetController.text,
                ),
                child: Text(
                    LocalizationService.translate('withdraw', lang).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleWithdraw(String amountStr, String method, String provider, String target) async {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final amount = double.tryParse(amountStr) ?? 0;

    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter phone/account number")));
      return;
    }

    if (amount < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('min_withdraw_1000', lang))));
      return;
    }

    if (amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('insufficient_balance', lang))));
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoading = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;

    try {
      await FirebaseFirestore.instance.collection('withdrawals').add({
        'userId': user?.id,
        'phoneNumber': target,
        'payoutMethod': method,
        'payoutProvider': provider,
        'amount': amount,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Optional: Update user profile with latest payout preference
      await FirebaseFirestore.instance.collection('drivers').doc(user?.id).update({
        'payoutMethod': provider,
        'payoutNumber': target,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('withdraw_request_sent', lang)),
          backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('error_occurred', lang).replaceAll('{error}', e.toString())),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
