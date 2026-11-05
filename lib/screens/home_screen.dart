import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/ride_provider.dart';
import '../models/vehicle.dart';
import '../services/route_service.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../services/voice_service.dart';
import '../services/visual_positioning_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  late TextEditingController _pickupController;
  final TextEditingController _dropoffController = TextEditingController();

  List<Vehicle> _vehicles = [];
  RouteInfo? _routeInfo;
  double _estimatedFare = 0;
  bool _isCalculatingFare = false;
  Vehicle? _selectedVehicle;
  LatLng? _currentLatLng;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  String? _pickupRegion;
  String? _pickupCity;
  bool _isMapReady = false;
  bool _isMapVisible = false;
  bool _isSearchingPickup = false;
  final Color _accentGold = AppTheme.primaryGold;
  final Color _premiumChocolateCenter = const Color(0xFF7A4B13);
  final Color _premiumChocolateEdge = const Color(0xFF4B2E0B);

  @override
  void initState() {
    super.initState();
    _vehicles = Vehicle.getAvailableVehicles();
    _selectedVehicle = _vehicles.any((v) => v.name == 'Car')
        ? _vehicles.firstWhere((v) => v.name == 'Car')
        : (_vehicles.isNotEmpty ? _vehicles.first : null);

    _pickupController = TextEditingController(text: "Locating...");
    _getCurrentLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.currentUser != null) {
        Provider.of<RideProvider>(context, listen: false)
            .initializeConnection(auth.currentUser!.id);
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _pickupController.text = "GPS is OFF");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _pickupController.text = "Permission Denied");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (position.latitude.isFinite && position.longitude.isFinite) {
        setState(() {
          _currentLatLng = LatLng(position.latitude, position.longitude);
          _pickupLatLng = _currentLatLng;
        });

        if (_isMapReady) {
          try {
            _mapController.move(_currentLatLng!, 16.0);
          } catch (e) {
            debugPrint("Error moving map: $e");
          }
        }
        _getPlaceName(position.latitude, position.longitude);
      }
    } catch (e) {
      debugPrint("Location Error: $e");
      // Ondoa Mock Data hapa. 
      // Ikiwa kuna kosa, mjulishe mtumiaji kuwa eneo halikupatikana.
      if (mounted) {
        setState(() {
          _pickupController.text = "Location not found";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Tafadhali washa GPS au hakiki mtandao wako."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _getPlaceName(double lat, double lon,
      {bool isPickup = true}) async {
    try {
      final response = await http
          .get(Uri.parse('https://photon.komoot.io/reverse?lon=$lon&lat=$lat'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final props = data['features'][0]['properties'];

          String? name = props['name'];
          String? street = props['street'];
          String? district = props['district'];
          String? city = props['city'];
          String? state = props['state'] ?? props['region'];

          // Normalize region names (e.g., "Arusha Region" -> "Arusha")
          if (state != null) {
            if (state.contains("Arusha")) state = "Arusha";
            if (state.contains("Dar es Salaam")) state = "Dar es Salaam";
            if (state.contains("Mwanza")) state = "Mwanza";
            if (state.contains("Dodoma")) state = "Dodoma";
          }

          String? country = props['country'];
          String? housenumber = props['housenumber'];

          if (isPickup) {
            _pickupRegion = state;
            _pickupCity = city ?? district;
          }

          List<String> parts = [];
          if (name != null) parts.add(name);
          if (housenumber != null) parts.add(housenumber);
          if (street != null && street != name) parts.add(street);
          if (district != null) parts.add(district);
          if (city != null && city != district) parts.add(city);
          if (parts.length < 2 && state != null) parts.add(state);
          if (parts.length < 2 && country != null) parts.add(country);

          String finalName = parts.isNotEmpty
              ? (parts.length > 1 ? parts.take(3).join(", ") : parts[0])
              : "Location near ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}";

          setState(() {
            if (isPickup) {
              _pickupController.text = finalName;
            } else {
              _dropoffController.text = finalName;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Photon Geocode Error: $e");
    }
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer<AuthProvider>(
          builder: (context, auth, child) {
            final isDark = auth.themeMode == ThemeMode.dark;
            final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final textColor = isDark ? Colors.white : Colors.black;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
                border: Border.all(color: _accentGold, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    LocalizationService.translate('preferences', auth.language),
                    style: GoogleFonts.poppins(
                      color: _accentGold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 30),
                  Text(
                    LocalizationService.translate('language', auth.language),
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.7), fontSize: 14),
                  ),
                  RadioGroup<String>(
                    groupValue: auth.language,
                    onChanged: (String? value) {
                      if (value != null) auth.setLanguage(value);
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text('English',
                                style:
                                    TextStyle(color: textColor, fontSize: 14)),
                            value: 'English',
                            activeColor: _accentGold,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text('Kiswahili',
                                style:
                                    TextStyle(color: textColor, fontSize: 14)),
                            value: 'Kiswahili',
                            activeColor: _accentGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  SwitchListTile(
                    secondary: Icon(Icons.dark_mode, color: _accentGold),
                    title: Text(
                      LocalizationService.translate('dark_mode', auth.language),
                      style: TextStyle(color: textColor),
                    ),
                    value: isDark,
                    activeThumbColor: _accentGold,
                    onChanged: (bool value) {
                      auth.toggleTheme(value);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _handleMapTap(LatLng latLng) {
    if (!_isMapReady) return;
    if (mounted) {
      setState(() {
        if (_isSearchingPickup) {
          _pickupLatLng = latLng;
          _getPlaceName(latLng.latitude, latLng.longitude, isPickup: true);
        } else {
          _dropoffLatLng = latLng;
          _getPlaceName(latLng.latitude, latLng.longitude, isPickup: false);
        }
      });
      _updateRoute();
    }
  }

  void _updateRoute() async {
    if (!_isMapReady) return;
    if (_pickupLatLng != null && _dropoffLatLng != null) {
      if (mounted) setState(() { _isCalculatingFare = true; _estimatedFare = 0; });
      try {
      final route = await RouteService.getRouteInfo(
        _pickupLatLng!.latitude.toString(),
        _pickupLatLng!.longitude.toString(),
        _dropoffLatLng!.latitude.toString(),
        _dropoffLatLng!.longitude.toString(),
      );
      final vehicle = _selectedVehicle;
      final estimate = vehicle == null ? null : await DatabaseService.instance.estimateFare(
        vehicleType: vehicle.name,
        distanceMeters: route.distance * 1000,
        durationSeconds: route.duration * 60,
        pickupLatitude: _pickupLatLng!.latitude,
        pickupLongitude: _pickupLatLng!.longitude,
      );
      if (mounted) {
        // Wrap in post-frame callback to avoid "setstate during build" or font assertion errors
        // especially if this is triggered rapidly during a transition.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _routeInfo = route;
            _estimatedFare = (estimate?['estimated_fare'] as num?)?.toDouble() ?? 0;
            _isCalculatingFare = false;
          });
          if (_isMapReady &&
              _pickupLatLng!.latitude.isFinite &&
              _pickupLatLng!.longitude.isFinite &&
              _dropoffLatLng!.latitude.isFinite &&
              _dropoffLatLng!.longitude.isFinite) {
            try {
              _mapController.fitCamera(CameraFit.bounds(
                  bounds:
                      LatLngBounds.fromPoints([_pickupLatLng!, _dropoffLatLng!]),
                  padding: const EdgeInsets.all(80)));
            } catch (e) {
              debugPrint("Error fitting camera: $e");
            }
          }
        });
      }
      } catch (error) {
        debugPrint('Route or server fare estimate failed: $error');
        if (mounted) {
          setState(() {
            _routeInfo = null;
            _estimatedFare = 0;
            _isCalculatingFare = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Route or fare estimate is unavailable. Please try again.')),
          );
        }
      }
    } else if (mounted) {
      setState(() { _routeInfo = null; _estimatedFare = 0; _isCalculatingFare = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // CENTER: Google Map (Background)
          _buildMapLayer(),

          // TOP ICONS: Menu & Profile & Settings
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircleIcon(
                    Icons.menu, () => _scaffoldKey.currentState?.openDrawer()),
                _buildCircleIcon(Icons.notifications_none,
                    () => Navigator.pushNamed(context, '/notifications')),
                _buildCircleIcon(Icons.person,
                    () => Navigator.pushNamed(context, '/profile')),
              ],
            ),
          ),

          // SOS BUTTON (Floating)
          if (_isMapVisible)
            Positioned(
              right: 20,
              bottom: 240,
              child: FloatingActionButton(
                onPressed: _showSosDialog,
                backgroundColor: Colors.redAccent,
                mini: true,
                child: const Text("SOS",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
              ),
            ),

          // BOTTOM BOOKING PANEL
          if (_isMapVisible)
            Positioned(
              bottom: 110,
              left: 15,
              right: 15,
              child: _buildBookingPanel(),
            ),

          // Selection Page Overlay (Initial State)
          if (!_isMapVisible) _buildSelectionOverlay(),
        ],
      ),
      bottomNavigationBar: _isMapVisible ? _buildPersistentBottomBar() : null,
    );
  }

  Widget _buildMapLayer() {
    final rideProvider = Provider.of<RideProvider>(context);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: (_currentLatLng != null && _currentLatLng!.latitude.isFinite)
            ? _currentLatLng!
            : const LatLng(-6.3690, 34.8888),
        initialZoom: _currentLatLng != null ? 15 : 6.5,
        maxZoom: 22,
        onTap: (tap, latLng) => _handleMapTap(latLng),
        onMapReady: () {
          if (mounted) {
            setState(() => _isMapReady = true);
          }
          if (_currentLatLng != null &&
              _currentLatLng!.latitude.isFinite &&
              _isMapReady) {
            try {
              _mapController.move(_currentLatLng!, 16.0);
            } catch (e) {
              debugPrint("Error moving map in onMapReady: $e");
            }
          }

        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.sta.ride',
          maxNativeZoom: 19,
          maxZoom: 20,
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
        if (_routeInfo != null)
          PolylineLayer(
            polylines: [
              Polyline(
                  points: _routeInfo!.polyline
                      .map((p) => LatLng(p.latitude, p.longitude))
                      .toList(),
                  color: _accentGold,
                  strokeWidth: 4.0)
            ],
          ),
        MarkerLayer(
          markers: [
            if (_pickupLatLng != null && _pickupLatLng!.latitude.isFinite)
              Marker(
                point: _pickupLatLng!,
                width: 60,
                height: 60,
                child: _PulseMarker(
                    icon: Icons.radio_button_checked, color: _accentGold),
              ),
            if (_dropoffLatLng != null && _dropoffLatLng!.latitude.isFinite)
              Marker(
                point: _dropoffLatLng!,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on,
                    color: Colors.redAccent, size: 35),
              ),
            ...rideProvider.nearbyDrivers.entries
                .where((e) => e.value.latitude.isFinite && e.value.longitude.isFinite)
                .map((e) => Marker(
                  point: e.value,
                  width: 30,
                  height: 30,
                  child: Icon(
                    _selectedVehicle?.name == 'Bodaboda'
                        ? Icons.motorcycle
                        : (_selectedVehicle?.name == 'Bajaji'
                            ? Icons.electric_rickshaw
                            : Icons.directions_car),
                    color: Colors.black.withOpacity(0.7),
                    size: 20,
                  ),
                )),
          ],
        ),
      ],
    );
  }

  Widget _buildBookingPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pickup & Destination Capsules
        Row(
          children: [
            Expanded(
              child: _buildLocationCapsule("Pickup point...",
                  _pickupController.text, Icons.circle, Colors.blue, true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildLocationCapsule("Where to?", _dropoffController.text,
                  Icons.location_on, Colors.redAccent, false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Info Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_premiumChocolateCenter, _premiumChocolateEdge],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoText(
                        "AINA: ${_selectedVehicle?.name.toUpperCase() ?? 'CAR'}"),
                    const SizedBox(height: 4),
                    _infoText(
                        "UMBALI: ${_routeInfo?.distance.toStringAsFixed(1) ?? '--'} KM"),
                    const SizedBox(height: 4),
                    _infoText(
                        _isCalculatingFare
                            ? "BEI: Inakadiria..."
                            : _estimatedFare > 0
                                ? "BEI: TZS ${NumberFormat('#,###').format(_estimatedFare)}"
                                : "BEI: Haijapatikana"),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: (_dropoffLatLng != null && _estimatedFare > 0)
                    ? () => _handleRideRequest()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGold,
                  foregroundColor: Colors.black,
                  elevation: 5,
                  shadowColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: const BorderSide(color: Colors.black, width: 2)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                ),
                child: Shimmer.fromColors(
                  baseColor: Colors.black,
                  highlightColor: Colors.white.withOpacity(0.5),
                  period: const Duration(seconds: 2),
                  child: Text("REQUEST",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCapsule(
      String hint, String value, IconData icon, Color color, bool isPickup) {
    return GestureDetector(
      onTap: () => setState(() => _isSearchingPickup = isPickup),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color:
                  _isSearchingPickup == isPickup ? _accentGold : Colors.black,
              width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value.isEmpty || value == "Locating..." ? hint : value,
                style: GoogleFonts.poppins(
                    color: value.isEmpty || value == "Locating..."
                        ? Colors.white24
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoText(String text) {
    return Text(text,
        style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900));
  }

  void _handleRideRequest() {
    Navigator.pushNamed(context, '/ride-request', arguments: {
      'vehicle': _selectedVehicle,
      'pickup': _pickupController.text,
      'dropoff': _dropoffController.text,
      'pickupLatLng': _pickupLatLng!,
      'dropoffLatLng': _dropoffLatLng!,
      'region': _pickupRegion,
      'city': _pickupCity,
    });
  }

  void _showSosDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        title: const Text("EMERGENCY SOS",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            "Are you in danger? This will send your live location to our safety team and trigger an emergency call.",
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL",
                  style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.red),
            onPressed: () async {
              final authProv =
                  Provider.of<AuthProvider>(context, listen: false);
              final rideProv =
                  Provider.of<RideProvider>(context, listen: false);

              rideProv.sendSos(authProv.currentUser?.id ?? '', _currentLatLng);

              Navigator.pop(context);

              // Launch phone dialer
              final Uri telLaunchUri = Uri(
                scheme: 'tel',
                path: '112',
              );
              if (await canLaunchUrl(telLaunchUri)) {
                await launchUrl(telLaunchUri);
              }
            },
            child: const Text("SEND SOS"),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    final isDark = auth.themeMode == ThemeMode.dark;

    return Container(
      color: isDark ? AppTheme.backgroundCharcoal : Colors.white,
      width: double.infinity,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "STA RIDE",
                    style: GoogleFonts.poppins(
                      color: _accentGold,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  _buildCircleIcon(Icons.settings, _showSettingsModal),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocalizationService.translate('welcome_back', lang),
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    auth.currentUser?.name ?? "Rider",
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            // PROMO BANNER ANIMATED
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: PromoBanner(),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceGrey : Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "EXPLORE YOUR CITY",
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                          child: _buildSelectionCard(
                              "BODABODA", Icons.motorcycle_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildSelectionCard(
                              "BAJAJI", Icons.minor_crash_rounded)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildSelectionCard("CAR", Icons.directions_car_rounded)),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickAction("Profile", Icons.person_outline,
                            () => Navigator.pushNamed(context, '/profile')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickAction("History", Icons.history, () {
                          final auth =
                              Provider.of<AuthProvider>(context, listen: false);
                          Navigator.pushNamed(context, '/rider-history',
                              arguments: auth.currentUser?.id);
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickAction("Wallet", Icons.account_balance_wallet_outlined,
                            () => Navigator.pushNamed(context, '/wallet')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionCard(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        Vehicle vehicle;
        if (label == "BODABODA") {
          vehicle = _vehicles.firstWhere((v) => v.name == 'Bodaboda');
        } else if (label == "BAJAJI") {
          vehicle = _vehicles.firstWhere((v) => v.name == 'Bajaji');
        } else {
          vehicle = _vehicles.firstWhere((v) => v.name == 'Car');
        }

        setState(() {
          _selectedVehicle = vehicle;
        });

        if (_pickupLatLng == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location is not available. Enable GPS or choose a pickup point first.')),
          );
          return;
        }
        // Open booking with the actual pickup point; route and fare are calculated server-side.
        Navigator.pushNamed(context, '/ride-request', arguments: {
          'vehicle': vehicle,
          'pickup': _pickupController.text == "Locating..."
              ? "Current Location"
              : _pickupController.text,
          'dropoff': "Where to?.",
          'pickupLatLng': _pickupLatLng,
          'dropoffLatLng': null,
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _accentGold,
              _accentGold.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: _accentGold.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.black, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiActionCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAiSelection(Map<String, dynamic> result) {
    if (mounted) {
      setState(() {
        _dropoffController.text = result['name'];
        _dropoffLatLng = result['location'];
        _isMapVisible = true; // Fungua ramani ili aone mahali palipochaguliwa
      });
      _updateRoute();
    }
  }

  Widget _buildQuickAction(String label, IconData icon, VoidCallback onTap) {
    final isDark = Provider.of<AuthProvider>(context, listen: false).themeMode == ThemeMode.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: _accentGold, size: 24),
            const SizedBox(height: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E), shape: BoxShape.circle),
        child: Icon(icon, color: _accentGold, size: 24),
      ),
    );
  }

  Widget _buildPersistentBottomBar() {
    return Container(
      height: 90,
      decoration: BoxDecoration(
          color: _premiumChocolateEdge,
          border: const Border(top: BorderSide(color: Colors.black, width: 3)),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30), topRight: Radius.circular(30))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(Icons.home_filled, "Home", true,
              () => setState(() => _isMapVisible = false)),
          _navItem(Icons.account_balance_wallet, "Wallet", false,
              () => Navigator.pushNamed(context, '/wallet')),
          _navItem(Icons.history, "History", false, () {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            Navigator.pushNamed(context, '/rider-history',
                arguments: auth.currentUser?.id);
          }),
          _navItem(Icons.person, "Profile", false,
              () => Navigator.pushNamed(context, '/profile')),
        ],
      ),
    );
  }

  Widget _navItem(
      IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: active ? _accentGold : Colors.white54, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  color: active ? _accentGold : Colors.white54,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _premiumChocolateEdge,
      child: ListView(
        children: [
          DrawerHeader(
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                _premiumChocolateCenter,
                _premiumChocolateEdge
              ])),
              child: Center(
                  child: Text("STA RIDER",
                      style: GoogleFonts.poppins(
                          color: _accentGold,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)))),
          _drawerItem(Icons.history, "History", () {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            Navigator.pushNamed(context, '/rider-history',
                arguments: auth.currentUser?.id);
          }),
          _drawerItem(Icons.account_balance_wallet, "Wallet",
              () => Navigator.pushNamed(context, '/wallet')),
          _drawerItem(Icons.person, "Profile",
              () => Navigator.pushNamed(context, '/profile')),
          _drawerItem(Icons.notifications_none, "Notifications",
              () => Navigator.pushNamed(context, '/notifications')),
          _drawerItem(Icons.directions_bus, "Fleet & Transport",
              () => Navigator.pushNamed(context, '/fleet')),
          const Divider(color: Colors.black, thickness: 2),
          _drawerItem(Icons.logout, "Logout", () async {
            final auth = Provider.of<AuthProvider>(context, listen: false);
            final navigator = Navigator.of(context);
            await auth.logout();
            if (mounted) {
              navigator.pushNamedAndRemoveUntil('/', (route) => false);
            }
          }, color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
        leading: Icon(icon, color: color ?? _accentGold),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        onTap: onTap);
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
              width: 20 + (30 * _controller.value),
              height: 20 + (30 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(1 - _controller.value),
              ),
            ),
            Icon(widget.icon, color: widget.color, size: 24),
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

class PromoBanner extends StatefulWidget {
  const PromoBanner({super.key});

  @override
  State<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<PromoBanner> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late Timer _timer;

  final List<Map<String, dynamic>> _promos = [
    {
      "title": "Get 20% OFF",
      "subtitle": "On your first 3 rides this week!",
      "icon": Icons.local_offer_rounded,
      "color": [const Color(0xFFFFD700), const Color(0xFFFF8C00)], // Gold to Orange
      "image": "assets/rider_icon.png" 
    },
    {
      "title": "Safety First",
      "subtitle": "Your safety is our priority. Share your status.",
      "icon": Icons.shield_rounded,
      "color": [const Color(0xFF2196F3), const Color(0xFF00BCD4)], // Blue to Cyan
    },
    {
      "title": "STA Wallet",
      "subtitle": "Top up and enjoy instant bookings.",
      "icon": Icons.account_balance_wallet_rounded,
      "color": [const Color(0xFF4CAF50), const Color(0xFF8BC34A)], // Green
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_currentPage < _promos.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutQuart,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: PageView.builder(
          controller: _pageController,
          itemCount: _promos.length,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemBuilder: (context, index) {
            final promo = _promos[index];
            return AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                double value = 1.0;
                if (_pageController.position.haveDimensions) {
                  value = _pageController.page! - index;
                  value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                }
                return Center(
                  child: Transform.scale(
                    scale: Curves.easeOut.transform(value),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: promo['color'],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      right: -20,
                      top: -20,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "PROMO",
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                promo['title'],
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                promo['subtitle'],
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Hero(
                          tag: 'promo_icon_$index',
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: Icon(promo['icon'], color: Colors.white, size: 40),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
