import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _carFareController = TextEditingController();
  final TextEditingController _bajajiFareController = TextEditingController();
  final TextEditingController _bodaFareController = TextEditingController();

  // Commission & Payment Settings
  final TextEditingController _commissionController = TextEditingController();
  final TextEditingController _taxController = TextEditingController();
  final TextEditingController _minPayoutController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    String car =
        await DatabaseService.instance.getSetting('base_fare_car', '3000');
    String bajaji =
        await DatabaseService.instance.getSetting('base_fare_bajaji', '1500');
    String boda =
        await DatabaseService.instance.getSetting('base_fare_bodaboda', '1000');

    String commission =
        await DatabaseService.instance.getSetting('commission_rate', '15');
    String tax = await DatabaseService.instance.getSetting('tax_rate', '5');
    String minPayout =
        await DatabaseService.instance.getSetting('min_payout', '50000');

    setState(() {
      _carFareController.text = car;
      _bajajiFareController.text = bajaji;
      _bodaFareController.text = boda;

      _commissionController.text = commission;
      _taxController.text = tax;
      _minPayoutController.text = minPayout;

      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      await DatabaseService.instance
          .updateSetting('base_fare_car', _carFareController.text);
      await DatabaseService.instance
          .updateSetting('base_fare_bajaji', _bajajiFareController.text);
      await DatabaseService.instance
          .updateSetting('base_fare_bodaboda', _bodaFareController.text);

      await DatabaseService.instance
          .updateSetting('commission_rate', _commissionController.text);
      await DatabaseService.instance
          .updateSetting('tax_rate', _taxController.text);
      await DatabaseService.instance
          .updateSetting('min_payout', _minPayoutController.text);

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Settings saved successfully!'),
              backgroundColor: Theme.of(context).primaryColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Configurations'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(25),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Fare Settings (Base Price)",
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Set the base starting price for each vehicle category.",
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 30),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 600) {
                              return Row(
                                children: [
                                  Expanded(
                                      child: _buildFareField(
                                          "STA Car",
                                          _carFareController,
                                          Icons.directions_car,
                                          Theme.of(context).primaryColor)),
                                  const SizedBox(width: 20),
                                  Expanded(
                                      child: _buildFareField(
                                          "Bajaji",
                                          _bajajiFareController,
                                          Icons.electric_rickshaw,
                                          Theme.of(context).primaryColor)),
                                  const SizedBox(width: 20),
                                  Expanded(
                                      child: _buildFareField(
                                          "Bodaboda",
                                          _bodaFareController,
                                          Icons.motorcycle,
                                          Theme.of(context).primaryColor)),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _buildFareField(
                                    "STA Car (Standard)",
                                    _carFareController,
                                    Icons.directions_car,
                                    Theme.of(context).primaryColor),
                                _buildFareField(
                                    "Bajaji",
                                    _bajajiFareController,
                                    Icons.electric_rickshaw,
                                    Theme.of(context).primaryColor),
                                _buildFareField(
                                    "Bodaboda",
                                    _bodaFareController,
                                    Icons.motorcycle,
                                    Theme.of(context).primaryColor),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                        Text(
                          "Commission & Payment (Driver)",
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Configure commission rates and driver payment thresholds.",
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 30),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 600) {
                              return Row(
                                children: [
                                  Expanded(
                                      child: _buildGeneralField(
                                          "Commission Rate",
                                          _commissionController,
                                          Icons.percent,
                                          "%",
                                          Theme.of(context).primaryColor)),
                                  const SizedBox(width: 20),
                                  Expanded(
                                      child: _buildGeneralField(
                                          "Tax Rate",
                                          _taxController,
                                          Icons.account_balance,
                                          "%",
                                          Theme.of(context).primaryColor)),
                                  const SizedBox(width: 20),
                                  Expanded(
                                      child: _buildGeneralField(
                                          "Min Payout",
                                          _minPayoutController,
                                          Icons.payments,
                                          "TZS",
                                          Theme.of(context).primaryColor)),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _buildGeneralField(
                                    "Commission Rate",
                                    _commissionController,
                                    Icons.percent,
                                    "%",
                                    Theme.of(context).primaryColor),
                                _buildGeneralField(
                                    "Tax Rate",
                                    _taxController,
                                    Icons.account_balance,
                                    "%",
                                    Theme.of(context).primaryColor),
                                _buildGeneralField(
                                    "Min Payout",
                                    _minPayoutController,
                                    Icons.payments,
                                    "TZS",
                                    Theme.of(context).primaryColor),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _saveSettings,
                            child: const Text("SAVE CONFIGURATIONS"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFareField(String label, TextEditingController controller,
      IconData icon, Color color) {
    return _buildGeneralField(label, controller, icon, "TZS", color);
  }

  Widget _buildGeneralField(String label, TextEditingController controller,
      IconData icon, String suffix, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: color),
          suffixText: suffix,
          suffixStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      ),
    );
  }
}
