import 'dart:convert';
import 'dart:math' show pi;
import 'package:http/http.dart' as http;
import 'package:osm_nominatim/osm_nominatim.dart' as osm;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';

import 'package:provider/provider.dart';
import 'package:sta/providers/auth_provider.dart';
import 'package:sta/providers/ride_provider.dart';
import 'package:sta/services/visual_positioning_service.dart';
import 'package:sta/services/voice_service.dart';
import 'package:sta/utils/theme.dart';
import 'package:intl/intl.dart';
import 'package:sta/services/localization_service.dart';

import '../services/route_service.dart';
import '../models/ride.dart';
import '../models/vehicle.dart';
import 'dart:async';
import 'ride_request_screen.dart';

class MapScreen extends StatefulWidget {
  final String? vehicleType;
  final Vehicle? vehicle;

  const MapScreen({
    super.key,
    this.vehicleType,
    this.vehicle,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();

  List<LatLng> _routePolyline = [];
  LatLng? _currentLatLng;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  String? _pickupRegion;
  RouteInfo? _routeInfo;
  String? _aiAdvice;
  bool _isMapReady = false;
  bool _isListening = false;
  bool _followDriver = true;
  LatLng? _lastDriverLatLng;

  final Color _accentGold = AppTheme.primaryGold;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      rideProvider.addListener(_onRideUpdate);

      if (widget.vehicleType != null) {
        _startDriverTracking();
      }
    });
  }

  void _startDriverTracking() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      String vType = widget.vehicleType ?? 'Car';
      if (vType.contains("BODABODA")) vType = "Bodaboda";
      if (vType.contains("BAJAJI")) vType = "Bajaji";
      if (vType.contains("CAR")) vType = "Car";

      Provider.of<RideProvider>(context, listen: false).findNearbyDrivers(
        lat: position.latitude,
        lng: position.longitude,
        vehicleType: vType,
        region: _pickupRegion,
      );
    } catch (e) {
      debugPrint("Tracking error: $e");
    }
  }

  void _onRideUpdate() {
    if (!mounted) return;
    final provider = Provider.of<RideProvider>(context, listen: false);
    final ride = provider.currentRide;
    final driverLoc = provider.driverLocation;

    if (ride != null &&
        _followDriver &&
        driverLoc != null &&
        (ride.status == RideStatus.accepted ||
            ride.status == RideStatus.arrived ||
            ride.status == RideStatus.inProgress)) {
      
      double distanceMoved = 0;
      if (_lastDriverLatLng != null) {
        distanceMoved = const Distance().as(LengthUnit.Meter, _lastDriverLatLng!, driverLoc);
      }

      if (_lastDriverLatLng == null || distanceMoved > 10) {
        _animatedMapMove(driverLoc, 16.5);
        _lastDriverLatLng = driverLoc;
      }
    }

    if (ride != null && ride.status == RideStatus.requesting) {
      // If we are still on MapScreen but ride is requesting, we should probably be in RideRequestScreen
      // But we stay here to show nearby drivers or status.
    }
  }

  Future<void> _getAddressFromLatLng(LatLng point, bool isPickup) async {
    debugPrint("DEBUG: Inaanza kutafuta jina la eneo: ${point.latitude}, ${point.longitude}");
    try {
      // Tunatumia jina la kipekee zaidi kama User Agent
      final nominatim = osm.Nominatim(userAgent: 'STA-Ride-App-v1-User-Agent');

      final reverseSearchResult = await nominatim.reverseSearch(
        lat: point.latitude,
        lon: point.longitude,
        addressDetails: true,
      );

      String address = reverseSearchResult.displayName;
      debugPrint("DEBUG: Jina limepatikana: $address");

      // Kurahisisha jina (Shorten address)
      List<String> parts = address.split(',');
      if (parts.length > 2) {
        // Tunachukua sehemu mbili za kwanza tu (Mtaa na Eneo)
        address = "${parts[0].trim()}, ${parts[1].trim()}";
      }

      String? adminArea = reverseSearchResult.address?['state']?.toString();
      if (adminArea != null) {
        if (adminArea.contains("Arusha")) adminArea = "Arusha";
        if (adminArea.contains("Dar es Salaam")) adminArea = "Dar es Salaam";
        if (adminArea.contains("Mwanza")) adminArea = "Mwanza";
        if (adminArea.contains("Dodoma")) adminArea = "Dodoma";
      }

      setState(() {
        if (isPickup) {
          _pickupController.text = address;
          _pickupRegion = adminArea;
          _pickupLatLng = point; // Update the LatLng when address is resolved from current location/tap
        } else {
          _dropoffController.text = address;
          _dropoffLatLng = point; // Update the LatLng
        }
      });
    } catch (e) {
      debugPrint("Geocoding error: $e");
      setState(() {
        if (isPickup) {
          _pickupController.text = "Eneo limechaguliwa";
        } else {
          _dropoffController.text = "Destination Selected";
        }
      });
    }
  }

  Future<void> _calculateRoute() async {
    if (!_isMapReady) return;
    if (_pickupLatLng == null || _dropoffLatLng == null) return;
    try {
      final route = await RouteService.getRouteInfo(
        _pickupLatLng!.latitude.toString(),
        _pickupLatLng!.longitude.toString(),
        _dropoffLatLng!.latitude.toString(),
        _dropoffLatLng!.longitude.toString(),
      );
      if (mounted) {
        setState(() {
          _routeInfo = route;
          _routePolyline =
              route.polyline.map((p) => LatLng(p.latitude, p.longitude)).toList();
        });

        // Pata ushauri wa AI baada ya kupata route
        final advice =
            await RouteService.getAISmartAdvice(route, _dropoffController.text);
        if (mounted) {
          setState(() {
            _aiAdvice = advice;
          });
        }
        if (_isMapReady) {
          try {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(_routePolyline),
                padding: const EdgeInsets.all(70),
              ),
            );
          } catch (e) {
            debugPrint("Error fitting camera: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Route calculation error: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _pickupLatLng = _currentLatLng;
      });

      _getAddressFromLatLng(_currentLatLng!, true);

      if (_isMapReady) {
        _mapController.move(_currentLatLng!, 15);
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  void _handleMapTap(LatLng point) {
    if (_pickupLatLng != null && _dropoffLatLng == null) {
      setState(() {
        _dropoffLatLng = point;
      });
      _getAddressFromLatLng(point, false);
      _calculateRoute();
    } else {
      setState(() {
        _pickupLatLng = point;
        _dropoffLatLng = null;
        _dropoffController.text = "";
        _routePolyline = [];
        _routeInfo = null;
      });
      _getAddressFromLatLng(point, true);
    }
  }

  Future<void> _handleVisualAI() async {
    final result = await VisualPositioningService.detectLocationFromCamera();
    // ... rest of the visual AI code (keeping it for reference)
    if (result != null) {
      final LatLng loc = result['location'];
      final String name = result['name'];

      setState(() {
        _pickupLatLng = loc;
        _pickupController.text = name;
      });

      _mapController.move(loc, 17);

      if (_dropoffLatLng != null) {
        _calculateRoute();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("AI Recognized: $name. Location Adjusted!",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("AI could not recognize any landmarks. Using GPS...",
                style: GoogleFonts.poppins()),
            backgroundColor: _accentGold,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _getCurrentLocation();
    }
  }

  Future<void> _handleVoiceAI() async {
    setState(() => _isListening = true);

    // Show a premium voice dialog
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Shimmer.fromColors(
              baseColor: _accentGold,
              highlightColor: Colors.white,
              child: const Icon(Icons.mic, size: 80),
            ),
            const SizedBox(height: 20),
            Text(
              LocalizationService.translate('voice_search_prompt',
                  Provider.of<AuthProvider>(context, listen: false).language),
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              LocalizationService.translate('voice_search_example',
                  Provider.of<AuthProvider>(context, listen: false).language),
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
            const SizedBox(height: 30),
            CircularProgressIndicator(color: _accentGold),
          ],
        ),
      ),
    );

    try {
      final result = await VoiceService.listenAndGetLocation();
      if (mounted && Navigator.canPop(context)) Navigator.pop(context); // Close bottom sheet

      if (result != null) {
        final LatLng loc = result['location'];
        final String name = result['name'];

        setState(() {
          _dropoffLatLng = loc;
          _dropoffController.text = name;
        });

        _mapController.move(loc, 15);
        _calculateRoute();

        if (mounted) {
          final lang =
              Provider.of<AuthProvider>(context, listen: false).language;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  LocalizationService.translate('location_found', lang)
                      .replaceFirst('{name}', name),
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          final lang =
              Provider.of<AuthProvider>(context, listen: false).language;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  LocalizationService.translate('voice_not_understood', lang),
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } finally {
      setState(() => _isListening = false);
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady) return;
    
    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude,
        end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude,
        end: destLocation.longitude);
    final zoomTween = Tween<double>(
        begin: _mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation));
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  LatLng? _lastAnimatedDriverLocation;

  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<RideProvider>(context);
    final currentRide = rideProvider.currentRide;
    final isTracking = currentRide != null &&
        (currentRide.status == RideStatus.accepted ||
            currentRide.status == RideStatus.arrived ||
            currentRide.status == RideStatus.inProgress);

    if (isTracking && rideProvider.driverLocation != null) {
       // Update last location for smooth interpolation if needed
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Hybrid Map (Satellite + Roads + Labels)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLatLng ?? const LatLng(-3.3869, 36.6830),
              initialZoom: 15,
              maxZoom: 20,
              minZoom: 3,
              onMapReady: () => setState(() => _isMapReady = true),
              onTap: (tapPosition, point) {
                if (!isTracking) _handleMapTap(point);
              },
            ),
            children: [
              // Google Hybrid Layer (Satellite + Streets + Labels) - Exact Google Look
              TileLayer(
                urlTemplate: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
                userAgentPackageName: 'com.sta.ride',
                maxNativeZoom: 20,
                maxZoom: 22,
              ),
              if (_routePolyline.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                      points: _routePolyline,
                      strokeWidth: 5,
                      color: _accentGold)
                ]),
              MarkerLayer(
                markers: [
                  if (_pickupLatLng != null)
                    Marker(
                        point: _pickupLatLng!,
                        width: 60,
                        height: 60,
                        child: _PulseMarker(
                          icon: Icons.person_pin_circle,
                          color: Colors.blue,
                        )),
                  if (_dropoffLatLng != null)
                    Marker(
                        point: _dropoffLatLng!,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on,
                            color: _accentGold, size: 40)),

                  // Nearby Drivers (Static for non-active rides)
                  if (!isTracking)
                    ...rideProvider.nearbyDrivers.entries.map((entry) {
                      return Marker(
                        point: entry.value,
                        width: 40,
                        height: 40,
                        child: Icon(
                          widget.vehicleType == 'Bodaboda'
                              ? Icons.motorcycle
                              : (widget.vehicleType == 'Bajaji'
                                  ? Icons.electric_rickshaw
                                  : Icons.directions_car),
                          color: _accentGold.withOpacity(0.7),
                          size: 30,
                        ),
                      );
                    }).toList(),
                ],
              ),

              // 2. Animated Driver Marker (For Active Ride)
              if (isTracking && rideProvider.driverLocation != null)
                TweenAnimationBuilder<LatLng>(
                  tween: LatLngTween(
                    begin: _lastAnimatedDriverLocation ?? rideProvider.driverLocation!,
                    end: rideProvider.driverLocation!,
                  ),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeInOutCubic,
                  onEnd: () => _lastAnimatedDriverLocation = rideProvider.driverLocation,
                  builder: (context, animatedLatLng, child) {
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: animatedLatLng,
                          width: 60,
                          height: 60,
                          child: Transform.rotate(
                            angle: rideProvider.driverBearing * (pi / 180),
                            child: _AnimatedCarIcon(
                              vehicleType: widget.vehicleType,
                              color: _accentGold,
                              isArrived: currentRide.status == RideStatus.arrived,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),

          // 2. Custom Top Bar
          _buildTopBar(),

          // 3. AI Camera Float Button
          if (!isTracking)
            Positioned(
              right: 20,
              bottom: 240,
              child: FloatingActionButton(
                onPressed: _handleVisualAI,
                heroTag: "visual_ai",
                backgroundColor: Colors.black,
                elevation: 10,
                shape: CircleBorder(
                    side: BorderSide(color: _accentGold, width: 2)),
                child: Icon(Icons.camera_enhance, color: _accentGold),
              ),
            ),

          // 3b. Follow Me/Driver Toggle
          if (isTracking)
            Positioned(
              right: 20,
              bottom: 240,
              child: FloatingActionButton(
                onPressed: () => setState(() => _followDriver = !_followDriver),
                heroTag: "follow_toggle",
                backgroundColor: _followDriver ? _accentGold : Colors.black,
                elevation: 10,
                shape: CircleBorder(
                    side: BorderSide(color: _accentGold, width: 2)),
                child: Icon(
                  _followDriver ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: _followDriver ? Colors.black : _accentGold,
                ),
              ),
            ),

          // 4. Search Inputs Panel
          if (!isTracking) _buildSearchPanel(),

          // 5. Bottom Request / Tracking Panel
          Positioned(
            bottom: 30,
            left: 15,
            right: 15,
            child: isTracking
                ? _buildTrackingPanel(currentRide, rideProvider)
                : _buildInfoPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final rideProvider = Provider.of<RideProvider>(context);
    final isTracking = rideProvider.currentRide != null &&
        (rideProvider.currentRide!.status == RideStatus.accepted ||
            rideProvider.currentRide!.status == RideStatus.arrived ||
            rideProvider.currentRide!.status == RideStatus.inProgress);

    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircularButton(Icons.arrow_back, () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: _accentGold.withValues(alpha: 0.5)),
            ),
            child: Text(
              isTracking ? "TRACKING RIDE" : (widget.vehicleType?.toUpperCase() ?? "STA RIDE"),
              style: GoogleFonts.poppins(
                color: _accentGold,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          if (!isTracking)
            _buildCircularButton(Icons.camera_alt, _handleVisualAI)
          else
             const SizedBox(width: 45),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    return Positioned(
      top: 110,
      left: 15,
      right: 15,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: Column(
          children: [
            _buildSearchField(
              controller: _pickupController,
              hint: "Chagua unapoanzia...",
              icon: Icons.my_location,
              iconColor: Colors.blue,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Divider(color: Colors.white10, height: 20),
            ),
            _buildSearchField(
              controller: _dropoffController,
              hint: "Unakwenda wapi?",
              icon: Icons.location_on,
              iconColor: _accentGold,
              trailing: IconButton(
                icon: const Icon(Icons.mic, color: AppTheme.primaryGold),
                onPressed: _handleVoiceAI,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 15),
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: true,
            onTap: () async {
              if (controller == _pickupController && _currentLatLng != null) {
                 // Option to use current location directly
              }
              
              final result = await showSearch(
                context: context,
                delegate: AddressSearchDelegate(),
              );
              if (result != null) {
                final lat = result['lat'] as double;
                final lng = result['lng'] as double;
                final name = result['name'] as String;

                setState(() {
                  controller.text = name;
                  if (controller == _pickupController) {
                    _pickupLatLng = LatLng(lat, lng);
                  } else {
                    _dropoffLatLng = LatLng(lat, lng);
                  }
                });

                _mapController.move(LatLng(lat, lng), 15);
                if (_pickupLatLng != null && _dropoffLatLng != null) {
                  _calculateRoute();
                }
              }
            },
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
              border: InputBorder.none,
              isDense: true,
              suffixIcon: controller.text.isNotEmpty ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white24, size: 16),
                onPressed: () {
                  setState(() {
                    controller.clear();
                    if (controller == _pickupController) _pickupLatLng = null;
                    else _dropoffLatLng = null;
                    _routePolyline = [];
                    _routeInfo = null;
                  });
                },
              ) : null,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildInfoPanel() {
    final dist = _routeInfo?.distance ?? 0.0;
    final distanceStr = dist.toStringAsFixed(1);
    final fareValue =
        widget.vehicle?.calculateFare(dist, _routeInfo?.duration ?? 0) ?? 0.0;
    final fare =
        dist > 0 ? NumberFormat('#,###').format(fareValue) : "Hesabu...";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: _accentGold.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 20, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("UMBALI KADIRIWA",
                      style: GoogleFonts.poppins(
                          color: _accentGold,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          fontSize: 10)),
                  const SizedBox(height: 4),
                  Text("$distanceStr km",
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("BEI KADIRIWA",
                      style: GoogleFonts.poppins(
                          color: _accentGold,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(dist > 0 ? "TZS $fare" : "---",
                      style: GoogleFonts.poppins(
                          color: _accentGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_aiAdvice != null && dist > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: AppTheme.primaryGold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.primaryGold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _aiAdvice!,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (_pickupLatLng != null && _dropoffLatLng != null)
                  ? () {
                      Navigator.pushNamed(context, '/ride-request', arguments: {
                        'vehicle': widget.vehicle,
                        'vehicleType': widget.vehicleType,
                        'pickup': _pickupController.text,
                        'dropoff': _dropoffController.text,
                        'pickupLatLng': _pickupLatLng,
                        'dropoffLatLng': _dropoffLatLng,
                        'fare': fareValue,
                        'distance': dist,
                        'region': _pickupRegion,
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                disabledBackgroundColor: Colors.white10,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: Shimmer.fromColors(
                baseColor: Colors.black,
                highlightColor: Colors.white.withOpacity(0.5),
                period: const Duration(seconds: 2),
                child: Text(
                  "OMBA USAFIRI",
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.black,
                      fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingPanel(Ride ride, RideProvider provider) {
    final driver = provider.driverInfo;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: _accentGold),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: _accentGold.withValues(alpha: 0.1),
                child: Icon(Icons.person, color: _accentGold),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver?.name ?? "Dereva",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white)),
                    Text(
                        "${driver?.carModel ?? 'Gari'} • ${driver?.carPlate ?? 'Namba'}",
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _accentGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(ride.status.name.toUpperCase(),
                    style: TextStyle(
                        color: _accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/chat', arguments: {
                    'receiverId': driver?.id,
                    'receiverName': driver?.name,
                    'senderId': auth.currentUser?.id,
                    'senderName': auth.currentUser?.fullName ?? 'User',
                  }),
                  icon: const Icon(Icons.chat),
                  label: const Text("Chat"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => provider.cancelRide(),
                  icon: const Icon(Icons.close),
                  label: const Text("Ghairi"),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(color: _accentGold.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, color: _accentGold, size: 20),
      ),
    );
  }

  @override
  void dispose() {
    Provider.of<RideProvider>(context, listen: false)
        .removeListener(_onRideUpdate);
    _pickupController.dispose();
    _dropoffController.dispose();
    _mapController.dispose();
    super.dispose();
  }
}

// --- Helper Widgets & Classes for Premium Animations ---

class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});

  @override
  LatLng lerp(double t) {
    if (begin == null || end == null) return end ?? const LatLng(0, 0);
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}

class _PulseMarker extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulseMarker({required this.icon, required this.color});

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 25 + (35 * _controller.value),
              height: 25 + (35 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(1 - _controller.value),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 2),
              ),
              padding: const EdgeInsets.all(5),
              child: Icon(widget.icon, color: widget.color, size: 20),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _AnimatedCarIcon extends StatefulWidget {
  final String? vehicleType;
  final Color color;
  final bool isArrived;

  const _AnimatedCarIcon({
    required this.vehicleType,
    required this.color,
    required this.isArrived,
  });

  @override
  State<_AnimatedCarIcon> createState() => _AnimatedCarIconState();
}

class _AnimatedCarIconState extends State<_AnimatedCarIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double scale = 1.0;
        if (widget.isArrived) {
          scale = 1.0 + (0.2 * _controller.value);
        }
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(
              widget.vehicleType == 'Bodaboda'
                  ? Icons.motorcycle
                  : (widget.vehicleType == 'Bajaji'
                      ? Icons.electric_rickshaw
                      : Icons.directions_car),
              color: widget.color,
              size: 30,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
