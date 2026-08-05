import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/theme.dart';
import '../services/localization_service.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, required this.title, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng _selectedLocation = const LatLng(-6.7924, 39.2083); // Dar es Salaam default
  String _address = "";
  bool _isLoading = true;
  bool _isSearching = false;
  bool _mapReady = false;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setInitialLocation();
  }

  Future<void> _searchPlace(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=$query&limit=1'),
        headers: {'User-Agent': 'STA Ride (com.sta.ride)'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newPos = LatLng(lat, lon);
          _mapController.move(newPos, 15.0);
          setState(() {
            _selectedLocation = newPos;
            _address = data[0]['display_name'];
          });
        }
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _setInitialLocation() async {
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!;
      _isLoading = false;
      _getAddress(_selectedLocation);
    } else {
      _goToCurrentLocation();
    }
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      final newPos = LatLng(position.latitude, position.longitude);
      if (_mapReady) {
        _mapController.move(newPos, 16.0);
      }
      setState(() {
        _selectedLocation = newPos;
        _isLoading = false;
      });
      _getAddress(_selectedLocation);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getAddress(LatLng location) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${location.latitude}&lon=${location.longitude}&zoom=18&addressdetails=1'),
        headers: {'User-Agent': 'STA Ride (com.sta.ride)'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _address = data['display_name'] ?? "Unknown Location";
        });
      } else {
        setState(() {
          _address = "Point at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}";
        });
      }
    } catch (e) {
      setState(() => _address = "Point on map selected");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    
    final bool isAddressLoading = _address.isEmpty;
    final String displayAddress = isAddressLoading
        ? LocalizationService.translate('fetching_address', lang)
        : _address;
    
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 15.0,
              onMapReady: () {
                setState(() => _mapReady = true);
                if (widget.initialLocation != null) {
                  _mapController.move(widget.initialLocation!, 15.0);
                }
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _selectedLocation = pos.center!;
                  });
                }
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  _getAddress(_selectedLocation);
                }
              },
              maxZoom: 22,
            ),
            children: [
              // 1. Base Layer: Satellite Imagery
              // Google Hybrid Layer (Satellite + Streets + Labels) - Exact Google Look
              TileLayer(
                urlTemplate: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
                userAgentPackageName: 'com.sta.ride',
                maxNativeZoom: 20,
                maxZoom: 22,
              ),
            ],
          ),
          
          // Header with Back Button and Search
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.8) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: LocalizationService.translate('search_location', lang),
                            hintStyle: GoogleFonts.poppins(fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onSubmitted: _searchPlace,
                        ),
                      ),
                      if (_isSearching)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _searchPlace(_searchController.text),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Center Marker Pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(5)),
                    child: Text(
                      LocalizationService.translate('set_here', Provider.of<AuthProvider>(context, listen: false).language), 
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                  ),
                  Icon(Icons.location_on, size: 45, color: AppTheme.primaryGold),
                ],
              ),
            ),
          ),

          // My Location Button
          Positioned(
            bottom: 230,
            right: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: isDark ? Colors.black87 : Colors.white,
              onPressed: _goToCurrentLocation,
              child: Icon(Icons.my_location, color: AppTheme.primaryGold),
            ),
          ),

          // Bottom Address Card
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 15, spreadRadius: 2)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.location_on_outlined, color: AppTheme.primaryGold),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title.toUpperCase(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.primaryGold)),
                            Text(
                              displayAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isAddressLoading ? null : () => Navigator.pop(context, {'address': _address, 'latlng': _selectedLocation}),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGold,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: Text(LocalizationService.translate('confirm_address', lang),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
