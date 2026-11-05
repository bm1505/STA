import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAllRead() async {
    await Supabase.instance.client.rpc('sta_mark_all_notifications_read');
  }

  Future<void> _markRead(String id) async {
    await Supabase.instance.client.rpc(
      'sta_mark_notification_read',
      params: {'p_notification_id': id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in to view notifications.')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: Text('Notifications', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read', style: TextStyle(color: Color(0xFFFFD166))),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client.from('user_notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load notifications: ${snapshot.error}',
              style: const TextStyle(color: Colors.white70)));
          }
          final notifications = [...(snapshot.data ?? <Map<String, dynamic>>[])]
            ..sort((a, b) => (b['created_at']?.toString() ?? '')
                .compareTo(a['created_at']?.toString() ?? ''));
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 54, color: Colors.white.withValues(alpha: 0.35)),
                  const SizedBox(height: 12),
                  const Text('You are all caught up.', style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = notifications[index];
              final id = item['id'].toString();
              final unread = item['read_at'] == null;
              final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
              return Material(
                color: unread ? const Color(0xFF1D2B36) : const Color(0xFF17212A),
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: Icon(
                    item['notification_type'] == 'payment'
                        ? Icons.account_balance_wallet
                        : item['notification_type'] == 'ride_status'
                            ? Icons.local_taxi
                            : item['notification_type'] == 'safety_alert'
                                ? Icons.health_and_safety
                                : Icons.campaign,
                    color: unread ? const Color(0xFFFFD166) : Colors.white54,
                  ),
                  title: Text(item['title']?.toString() ?? 'STA Notification',
                    style: TextStyle(color: Colors.white, fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(item['body']?.toString() ?? '', style: const TextStyle(color: Colors.white70)),
                      if (createdAt != null) ...[
                        const SizedBox(height: 6),
                        Text(DateFormat('dd MMM yyyy, HH:mm').format(createdAt.toLocal()),
                          style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ],
                  ),
                  trailing: unread
                      ? const Icon(Icons.circle, color: Color(0xFFFFD166), size: 9)
                      : const Icon(Icons.check, color: Colors.white30, size: 18),
                  onTap: unread ? () => _markRead(id) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
