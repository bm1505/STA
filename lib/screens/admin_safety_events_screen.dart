import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSafetyEventsScreen extends StatelessWidget {
  const AdminSafetyEventsScreen({super.key});

  Future<void> _setStatus(BuildContext context, String id, String status) async {
    try {
      await Supabase.instance.client.rpc('sta_resolve_safety_event', params: {
        'p_event_id': id,
        'p_status': status,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Safety event marked $status.')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update safety event: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Safety & Risk Monitoring',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Live driver telemetry anomalies detected during active trips.',
            style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 18),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client.from('ride_safety_events').stream(primaryKey: ['id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Safety events unavailable: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white70)));
                }
                final events = [...(snapshot.data ?? <Map<String, dynamic>>[])]
                  ..sort((a,b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));
                final open = events.where((e) => e['status'] == 'open' || e['status'] == 'reviewing').toList();
                if (open.isEmpty) {
                  return const Center(child: Text('No open safety events.', style: TextStyle(color: Colors.white54)));
                }
                return ListView.separated(
                  itemCount: open.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = open[index];
                    final severity = event['severity']?.toString() ?? 'medium';
                    final color = severity == 'critical' || severity == 'high'
                        ? Colors.redAccent
                        : severity == 'medium' ? Colors.orangeAccent : Colors.blueAccent;
                    final created = DateTime.tryParse(event['created_at']?.toString() ?? '');
                    final details = event['details'] is Map
                        ? Map<String, dynamic>.from(event['details'] as Map)
                        : <String, dynamic>{};
                    return Card(
                      color: const Color(0xFF1D2B36),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.health_and_safety, color: color),
                            const SizedBox(width: 8),
                            Expanded(child: Text(event['event_type']?.toString().replaceAll('_',' ').toUpperCase() ?? 'SAFETY EVENT',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                            Text(severity.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                          ]),
                          const SizedBox(height: 8),
                          Text('Driver: ${event['user_id']} · Ride: ${event['ride_id'] ?? '—'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          if (details.isNotEmpty)
                            Text(details.entries.map((e) => '${e.key}: ${e.value}').join(' · '),
                              style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          if (created != null)
                            Text(DateFormat('dd MMM yyyy, HH:mm:ss').format(created.toLocal()),
                              style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, children: [
                            if (event['status'] == 'open')
                              OutlinedButton(
                                onPressed: () => _setStatus(context,event['id'].toString(),'reviewing'),
                                child: const Text('Review'),
                              ),
                            FilledButton(
                              onPressed: () => _setStatus(context,event['id'].toString(),'resolved'),
                              child: const Text('Resolve'),
                            ),
                            TextButton(
                              onPressed: () => _setStatus(context,event['id'].toString(),'dismissed'),
                              child: const Text('Dismiss'),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
