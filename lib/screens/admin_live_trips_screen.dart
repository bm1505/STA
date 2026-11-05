import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/theme.dart';

class AdminLiveTripsScreen extends StatefulWidget {
  const AdminLiveTripsScreen({super.key});

  @override
  State<AdminLiveTripsScreen> createState() => _AdminLiveTripsScreenState();
}

class _AdminLiveTripsScreenState extends State<AdminLiveTripsScreen> {
  final Map<String, Map<String, dynamic>> _activeTrips = {};

  StreamSubscription<List<Map<String, dynamic>>>? _tripsSubscription;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _setupSupabaseListener();
  }

  void _setupSupabaseListener() {
    _tripsSubscription = _db.from('ride_requests')
        .stream(primaryKey: ['id'])
        .listen((rows) {
      if (!mounted) return;
      final activeStatuses = {'requesting', 'accepted', 'driver_arrived', 'in_progress'};
      setState(() {
        _activeTrips.clear();
        for (final row in rows) {
          final status = row['status']?.toString() ?? '';
          if (!activeStatuses.contains(status)) continue;
          final rideData = row['ride_data'] is Map
              ? Map<String, dynamic>.from(row['ride_data'] as Map)
              : <String, dynamic>{};
          _activeTrips[row['id'].toString()] = {
            'rideId': row['id'].toString(),
            'status': status,
            'fare': row['final_fare'] ?? row['estimated_fare'] ?? 0,
            'createdAt': row['created_at']?.toString(),
            'vehicleType': row['vehicle_type'] ?? 'Standard',
            'riderName': rideData['riderName'] ?? 'Unknown Rider',
            'pickupAddress': row['pickup_label'] ?? 'Unknown Location',
            'dropoffAddress': row['dropoff_label'] ?? 'Unknown Destination',
            'driverName': rideData['driverName'],
          };
        }
      });
    }, onError: (Object error) {
      debugPrint('STA live trips stream failed: $error');
    });
  }

  @override
  void dispose() {
    _tripsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LIVE TRIP MONITOR',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(
                '${_activeTrips.length} ONGOING TRIPS',
                style: GoogleFonts.inter(
                  color: AppTheme.adminPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _activeTrips.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _activeTrips.length,
              itemBuilder: (context, index) {
                final trip = _activeTrips.values.toList()[index];
                return _buildTripMonitorCard(trip);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run,
              size: 80, color: AppTheme.adminMuted.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No active trips at the moment',
              style: GoogleFonts.poppins(color: AppTheme.adminMuted)),
        ],
      ),
    );
  }

  Widget _buildTripMonitorCard(Map<String, dynamic> trip) {
    final statusColor = _getStatusColor(trip['status']);
    final fare = (trip['fare'] as num?)?.toDouble() ?? 0.0;
    final createdAt = DateTime.tryParse(trip['createdAt']?.toString() ?? '') ?? DateTime.now();
    final timeAgo = DateTime.now().difference(createdAt).inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header: Trip ID & Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.local_taxi_rounded, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TRIP #${trip['rideId'].toString().toUpperCase().substring(trip['rideId'].toString().length > 8 ? trip['rideId'].toString().length - 8 : 0)}",
                          style: GoogleFonts.robotoMono(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          "$timeAgo min ago • ${trip['vehicleType'] ?? 'Standard'}",
                          style: GoogleFonts.inter(color: AppTheme.adminMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(trip['status'].toString(), statusColor),
                ],
              ),
            ),

            // Body: Rider & Route
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.person_outline, size: 16, color: Colors.white70),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        trip['riderName'] ?? 'Unknown Rider',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "TZS ${NumberFormat('#,###').format(fare)}",
                        style: GoogleFonts.robotoMono(
                          color: AppTheme.adminPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildRouteVisualization(
                    trip['pickupAddress'] ?? "Unknown Location",
                    trip['dropoffAddress'] ?? "Unknown Destination",
                  ),
                ],
              ),
            ),

            // Footer: Driver Info
            if (trip['driverName'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: Colors.black.withValues(alpha: 0.2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "DRIVER: ",
                      style: GoogleFonts.inter(
                        color: AppTheme.adminMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      trip['driverName'].toString().toUpperCase(),
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.phone_in_talk_outlined, size: 14, color: AppTheme.adminPrimary),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRouteVisualization(String pickup, String dropoff) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(Icons.radio_button_checked, size: 14, color: AppTheme.adminPrimary),
            Container(width: 1, height: 30, color: Colors.white12),
            const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
          ],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickup,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              Text(
                dropoff,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationInfo(String label, String address) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(
          address,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'requesting':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'arrived':
        return Colors.purple;
      case 'started':
      case 'in_progress':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
