import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  StreamSubscription? _driverSubscription;
  StreamSubscription? _rideSubscription;
  StreamSubscription? _demandSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // 1. Listen to Online Drivers
    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers_online')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          for (var change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data != null) {
              final id = change.doc.id;
              if (change.type == DocumentChangeType.removed) {
                _onlineDrivers.remove(id);
              } else {
                // Hakikisha lat na lng zipo kabla ya kuzitumia
                final lat = data['lat'] as num?;
                final lng = data['lng'] as num?;

                if (lat != null && lng != null) {
                  _onlineDrivers[id] = {
                    'id': id,
                    'lat': lat.toDouble(),
                    'lng': lng.toDouble(),
                    'name': data['name'] ?? 'Driver',
                    'status': data['status'] ?? 'idle',
                    'vehicleType': data['vehicleType'] ?? 'Car',
                    'bearing': (data['bearing'] as num?)?.toDouble() ?? 0.0,
                    'lastUpdate': data['lastUpdate'] != null
                        ? (data['lastUpdate'] as Timestamp).toDate()
                        : DateTime.now(),
                  };
                }
              }
            }
          }
        });
      }
    });

    // 2. Listen to Active Rides (accepted or started)
    _rideSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', whereIn: ['accepted', 'started', 'arrived'])
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          for (var change in snapshot.docChanges) {
            final data = change.doc.data();
            final id = change.doc.id;
            if (change.type == DocumentChangeType.removed) {
              _activeRides.remove(id);
            } else if (data != null) {
              _activeRides[id] = data;
            }
          }
        });
      }
    });

    // 3. Listen to Pending Requests (Heatmap Demand)
    _demandSubscription = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', isEqualTo: 'requesting')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          for (var change in snapshot.docChanges) {
            final data = change.doc.data();
            final id = change.doc.id;
            if (change.type == DocumentChangeType.removed) {
              _demandPoints.remove(id);
            } else if (data != null) {
              _demandPoints[id] = data;
            }
          }
        });
      }
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
