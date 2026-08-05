import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/theme.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _targetGroup = 'All Riders';
  bool _isSending = false;

  final List<String> _groups = [
    'All Riders',
    'All Drivers',
    'All Staff',
    'System Wide'
  ];

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      // Logic ya kutuma notification kupitia Backend/Firebase
      // Kwa sasa tunasimulate na ku-log kwenye database
      // 1. Rekodi kwenye Firestore (Hii itachochea Cloud Function ya Push)
      await FirebaseFirestore.instance.collection('broadcasts').add({
        'title': _titleController.text,
        'body': _bodyController.text,
        'target': _targetGroup,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      debugPrint("Notification broadcast scheduled in Firestore");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Notification sent successfully to $_targetGroup!"),
            backgroundColor: Colors.green,
          ),
        );
        _titleController.clear();
        _bodyController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 900;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 15 : 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Push Notifications",
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            "Send instant alerts to specific user groups",
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 40),
          if (isMobile)
            Column(
              children: [
                _buildNotificationForm(),
                const SizedBox(height: 30),
                _buildInfoCards(),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildNotificationForm()),
                const SizedBox(width: 30),
                Expanded(child: _buildInfoCards()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationForm() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Compose Message",
                style: GoogleFonts.poppins(
                    color: AppTheme.adminPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _targetGroup,
              dropdownColor: AppTheme.adminSurface,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Target Audience",
                labelStyle: TextStyle(color: Colors.white54),
                prefixIcon:
                    Icon(Icons.group_rounded, color: AppTheme.adminPrimary),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10)),
              ),
              items: _groups
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (val) => setState(() => _targetGroup = val!),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Notification Title",
                hintText: "Enter catchy title...",
                labelStyle: TextStyle(color: Colors.white54),
                prefixIcon:
                    Icon(Icons.title_rounded, color: AppTheme.adminPrimary),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10)),
              ),
              validator: (v) => v!.isEmpty ? "Title is required" : null,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _bodyController,
              style: const TextStyle(color: Colors.white),
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: "Message Body",
                hintText: "Type your message here...",
                labelStyle: TextStyle(color: Colors.white54),
                alignLabelWithHint: true,
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10)),
              ),
              validator: (v) => v!.isEmpty ? "Message body is required" : null,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _sendNotification,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.send_rounded, color: Colors.black),
                label: Text(
                  _isSending ? "SENDING..." : "BROADCAST NOTIFICATION",
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.adminPrimary,
                  shape: RoundedRectangle_circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCards() {
    return Column(
      children: [
        _buildInfoCard(
          "Riders Group",
          "Sends to all registered passengers. Best for promotions and app updates.",
          Icons.people_rounded,
        ),
        const SizedBox(height: 15),
        _buildInfoCard(
          "Drivers Group",
          "Immediate alerts for all drivers. Use for system maintenance or policy changes.",
          Icons.drive_eta_rounded,
        ),
        const SizedBox(height: 15),
        _buildInfoCard(
          "System Wide",
          "Broadcasts to every single user in the system.",
          Icons.campaign_rounded,
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String desc, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.adminPrimary, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(desc,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper for borderRadius
  RoundedRectangleBorder RoundedRectangle_circular(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
}
