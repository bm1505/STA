import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final Map<String, Map<String, dynamic>> _onlineDrivers = {};
  final Map<String, Map<String, dynamic>> _activeRides = {};
  final Map<String, Map<String, dynamic>> _demandPoints = {};
  bool _showHeatmap = true;
  final MapController _mapController = MapController();

  StreamSubscription<List<Map<String, dynamic>>>? _driverSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _rideSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _demandSubscription;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    _driverSubscription = _db.from('driver_locations')
        .stream(primaryKey: ['driver_id'])
        .listen((locations) async {
      try {
        final ids = locations.map((row) => row['driver_id'].toString()).toList();
        if (ids.isEmpty) {
          if (mounted) setState(_onlineDrivers.clear);
          return;
        }
        final driverRows = await _db.from('driver_profiles')
            .select('user_id,vehicle_type,availability_status,is_online')
            .inFilter('user_id', ids);
        final profileRows = await _db.from('profiles')
            .select('id,full_name,user_data').inFilter('id', ids);
        final driversById = {for (final row in driverRows) row['user_id'].toString(): row};
        final profilesById = {for (final row in profileRows) row['id'].toString(): row};
        if (!mounted) return;
        setState(() {
          _onlineDrivers.clear();
          for (final location in locations) {
            final id = location['driver_id'].toString();
            final driver = driversById[id];
            if (driver == null || driver['is_online'] != true) continue;
            final lat = (location['latitude'] as num?)?.toDouble();
            final lng = (location['longitude'] as num?)?.toDouble();
            if (lat == null || lng == null) continue;
            final recordedAt = DateTime.tryParse(location['recorded_at']?.toString() ?? '');
            if (recordedAt == null || DateTime.now().difference(recordedAt).inSeconds > 90) continue;
            final profile = profilesById[id];
            final userData = profile?['user_data'] is Map
                ? Map<String, dynamic>.from(profile!['user_data'] as Map)
                : <String, dynamic>{};
            final availability = driver['availability_status']?.toString() ?? 'idle';
            _onlineDrivers[id] = {
              'id': id,
              'lat': lat,
              'lng': lng,
              'name': userData['name'] ?? profile?['full_name'] ?? 'Driver',
              'status': availability == 'on_trip' ? 'busy' : 'idle',
              'vehicleType': driver['vehicle_type'] ?? 'Car',
              'bearing': (location['heading'] as num?)?.toDouble() ?? 0.0,
              'lastUpdate': recordedAt,
            };
          }
        });
      } catch (error) {
        debugPrint('STA live driver map update failed: $error');
      }
    }, onError: (Object error) {
      debugPrint('STA driver location stream failed: $error');
    });

    _rideSubscription = _db.from('ride_requests')
        .stream(primaryKey: ['id']).listen((rows) {
      if (!mounted) return;
      setState(() {
        _activeRides.clear();
        for (final row in rows) {
          if (!['accepted', 'driver_arrived', 'in_progress'].contains(row['status'])) continue;
          _activeRides[row['id'].toString()] = Map<String, dynamic>.from(row);
        }
      });
    }, onError: (Object error) {
      debugPrint('STA active ride stream failed: $error');
    });

    _demandSubscription = _db.from('ride_requests')
        .stream(primaryKey: ['id']).listen((rows) {
      if (!mounted) return;
      setState(() {
        _demandPoints.clear();
        for (final row in rows) {
          if (row['status'] != 'requesting') continue;
          _demandPoints[row['id'].toString()] = Map<String, dynamic>.from(row);
        }
      });
    }, onError: (Object error) {
      debugPrint('STA ride demand stream failed: $error');
    });
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    _rideSubscription?.cancel();
    _demandSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int idleDrivers =
        _onlineDrivers.values.where((d) => d['status'] == 'idle').length;
    int busyDrivers =
        _onlineDrivers.values.where((d) => d['status'] == 'busy').length;

    return Scaffold(
      backgroundColor: AppTheme.adminBg,
      body: RepaintBoundary(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(-6.7924, 39.2083), // Dar es Salaam
                initialZoom: 13,
                maxZoom: 20,
                minZoom: 5,
                interactionOptions: const InteractionOptions(
                  // Turuhusu tu Drag na Zoom ili kuifanya iwe nyepesi (optimized)
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                // Google Hybrid Layer (Satellite + Streets + Labels) - Exact Google Look
                TileLayer(
                  urlTemplate: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
                  userAgentPackageName: 'com.sta.ride',
                  maxNativeZoom: 20,
                  maxZoom: 20,
                ),

                // Demand Heatmap Layer (Enhanced Visuals)
                if (_showHeatmap)
                  CircleLayer(
                    circles: _demandPoints.values.map((ride) {
                      final pickup = ride['pickup'];
                      return CircleMarker(
                        point: LatLng((pickup['lat'] as num).toDouble(),
                            (pickup['lng'] as num).toDouble()),
                        radius: 80, // Larger radius for better heatmap feel
                        useRadiusInMeter: true,
                        color: Colors.red.withValues(alpha: 0.15),
                        borderColor: Colors.red.withValues(alpha: 0.05),
                        borderStrokeWidth: 1,
                      );
                    }).toList(),
                  ),
                
                // Secondary glow layer for high-density areas
                if (_showHeatmap)
                  CircleLayer(
                    circles: _demandPoints.values.map((ride) {
                      final pickup = ride['pickup'];
                      return CircleMarker(
                        point: LatLng((pickup['lat'] as num).toDouble(),
                            (pickup['lng'] as num).toDouble()),
                        radius: 30,
                        useRadiusInMeter: true,
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderStrokeWidth: 0,
                      );
                    }).toList(),
                  ),

                // Active Rides (Lines from Pickup to Dropoff)
                PolylineLayer(
                  polylines: _activeRides.values.map((ride) {
                    try {
                      final pickup = ride['pickup'];
                      final dropoff = ride['dropoff'];
                      return Polyline(
                        points: [
                          LatLng((pickup['lat'] as num).toDouble(),
                              (pickup['lng'] as num).toDouble()),
                          LatLng((dropoff['lat'] as num).toDouble(),
                              (dropoff['lng'] as num).toDouble()),
                        ],
                        color: AppTheme.adminPrimary.withValues(alpha: 0.3),
                        strokeWidth: 2,
                        pattern: const StrokePattern.dotted(),
                      );
                    } catch (e) {
                      return Polyline(points: [], color: Colors.transparent);
                    }
                  }).toList(),
                ),

                // Markers Layer
                MarkerLayer(
                  markers: [
                    // Drivers Markers
                    ..._onlineDrivers.entries.map((entry) {
                      final driver = entry.value;
                      bool isBusy = driver['status'] == 'busy';
                      return Marker(
                        point: LatLng(driver['lat'], driver['lng']),
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _showDriverDetails(driver),
                          child: _buildDriverMarker(
                            driver['vehicleType'],
                            isBusy,
                            driver['bearing'] ?? 0.0,
                          ),
                        ),
                      );
                    }),

                    // Ride Markers (Pickup & Dropoff)
                    ..._activeRides.values.expand((ride) {
                      try {
                        final pickup = ride['pickup'];
                        final dropoff = ride['dropoff'];
                        return [
                          Marker(
                            point: LatLng((pickup['lat'] as num).toDouble(),
                                (pickup['lng'] as num).toDouble()),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.location_on,
                                color: Colors.green, size: 20),
                          ),
                          Marker(
                            point: LatLng((dropoff['lat'] as num).toDouble(),
                                (dropoff['lng'] as num).toDouble()),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.flag_rounded,
                                color: Colors.red, size: 20),
                          ),
                        ];
                      } catch (e) {
                        return [];
                      }
                    }),
                  ],
                ),
              ],
            ),

            // Top Info Bar
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  _buildStatBadge("IDLE", idleDrivers, Colors.green),
                  const SizedBox(width: 10),
                  _buildStatBadge("BUSY", busyDrivers, Colors.orange),
                  const SizedBox(width: 10),
                  _buildStatBadge(
                      "LIVE TRIPS", _activeRides.length, AppTheme.adminPrimary),
                  const SizedBox(width: 10),
                  _buildHeatmapToggle(),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.adminSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.refresh,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text("LIVE FEED",
                            style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map Controls
            Positioned(
              bottom: 30,
              right: 20,
              child: Column(
                children: [
                  _buildMapAction(Icons.my_location, () {
                    if (_onlineDrivers.isNotEmpty) {
                      final first = _onlineDrivers.values.first;
                      _mapController.move(
                          LatLng(first['lat'], first['lng']), 14);
                    }
                  }),
                  const SizedBox(height: 10),
                  _buildMapAction(Icons.add, () {
                    final currentZoom = _mapController.camera.zoom;
                    if (currentZoom < 18) {
                      _mapController.move(
                          _mapController.camera.center, currentZoom + 1);
                    }
                  }),
                  const SizedBox(height: 10),
                  _buildMapAction(Icons.remove, () {
                    final currentZoom = _mapController.camera.zoom;
                    if (currentZoom > 5) {
                      _mapController.move(
                          _mapController.camera.center, currentZoom - 1);
                    }
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmapToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showHeatmap = !_showHeatmap),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: _showHeatmap
              ? Colors.orange.withValues(alpha: 0.2)
              : AppTheme.adminSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _showHeatmap ? Colors.orange : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _showHeatmap ? Icons.layers_rounded : Icons.layers_outlined,
              color: _showHeatmap ? Colors.orange : Colors.white60,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              "HEATMAP",
              style: GoogleFonts.inter(
                color: _showHeatmap ? Colors.orange : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.adminSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text("$label: ",
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          Text(count.toString(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDriverMarker(String type, bool isBusy, double bearing) {
    Color mainColor = isBusy ? AppTheme.primaryGold : Colors.white;
    Color iconColor = isBusy ? Colors.black : Colors.green;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow effect for visibility
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: mainColor.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 1,
              )
            ],
          ),
        ),
        // Main Marker
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: mainColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2.5),
          ),
          child: Transform.rotate(
            angle: bearing * (3.14159 / 180), // Convert degrees to radians
            child: Icon(
              _getVehicleIcon(type),
              color: iconColor,
              size: 20,
            ),
          ),
        ),
        if (isBusy)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapAction(IconData icon, VoidCallback onTap) {
    return FloatingActionButton.small(
      heroTag: null,
      onPressed: onTap,
      backgroundColor: AppTheme.adminSurface,
      foregroundColor: AppTheme.adminPrimary,
      child: Icon(icon),
    );
  }

  IconData _getVehicleIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bike':
        return Icons.moped_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  void _showDriverDetails(Map<String, dynamic> driver) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.adminSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white10,
                  child: Icon(Icons.person, color: Colors.white70),
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver['name'],
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white)),
                    Text(driver['vehicleType'].toString().toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                _buildStatusChip(driver['status'] == 'busy'),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                    child: _buildDetailItem(
                        "LATITUDE", driver['lat'].toStringAsFixed(4))),
                Expanded(
                    child: _buildDetailItem(
                        "LONGITUDE", driver['lng'].toStringAsFixed(4))),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.adminPrimary,
                    foregroundColor: Colors.black),
                child: const Text("CLOSE",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isBusy) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isBusy ? Colors.orange : Colors.green).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color:
                (isBusy ? Colors.orange : Colors.green).withValues(alpha: 0.3)),
      ),
      child: Text(
        isBusy ? "ON TRIP" : "AVAILABLE",
        style: TextStyle(
            color: isBusy ? Colors.orange : Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: 10),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
