import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_background_service/flutter_background_service.dart';
import '../providers/auth_provider.dart';
import '../providers/driver_ride_provider.dart';
import '../services/route_service.dart';
import '../services/localization_service.dart';
import '../services/call_service.dart';
import 'call_screen.dart';
import '../utils/theme.dart';
import 'driver_trip_history_screen.dart';
import 'wallet_screen.dart';
import 'profile_screen.dart';
import '../models/user.dart';
import '../widgets/profile_image_widget.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isOnline = false;
  int _selectedIndex = 0;
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription? _rideRequestSubscription;
  StreamSubscription? _callSubscription;
  DriverRideProvider? _rideProvider;
  ll.LatLng _currentLatLng = const ll.LatLng(-6.7924, 39.2083);
  double _currentBearing = 0;
  List<ll.LatLng> _polylinePoints = [];
  DriverRideStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _listenToBackgroundService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initDriverProvider();
      _syncInitialOnlineStatus();
      _listenToRideRequests();
      _listenToMessages();
      _listenToIncomingCalls();
    });
    _startLocationTracking();
  }

  void _syncInitialOnlineStatus() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentUser != null) {
      setState(() {
        _isOnline = auth.currentUser!.isOnline;
      });
      // Ikiwa alikuwa online, hakikisha Firestore imesawazishwa
      if (_isOnline) {
        final rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
        rideProvider.updateStatus(
          auth.currentUser!.id, 
          'idle', 
          _currentLatLng, 
          auth.currentUser!.vehicleType ?? 'Car',
          region: auth.currentUser!.region,
          city: auth.currentUser!.city
        );
      }
    }
  }

  void _listenToBackgroundService() {
    if (kIsWeb) return;
    FlutterBackgroundService().on('update').listen((event) {
      if (event != null && mounted) {
        final double lat = event['latitude'];
        final double lng = event['longitude'];
        final double bearing = event['bearing'] ?? 0.0;

        setState(() {
          _currentLatLng = ll.LatLng(lat, lng);
          _currentBearing = bearing;
        });

        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (auth.currentUser == null) return;
        
        final rideProvider =
            Provider.of<DriverRideProvider>(context, listen: false);
        rideProvider.updateLocation(
          Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: bearing,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          ),
          auth.currentUser!.id,
          _isOnline,
        );
      }
    });
  }

  void _initDriverProvider() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentUser != null) {
      _rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
      _rideProvider!.init(auth.currentUser!);
    }
  }

  void _listenToRideRequests() {
    if (!mounted || _rideProvider == null) return;
    _rideRequestSubscription?.cancel();
    _rideRequestSubscription = _rideProvider!.rideRequestStream.listen((request) {
      if (_isOnline && mounted) {
        _showRideRequestSheet(request);
      }
    });
  }

  void _showRideRequestSheet(Map<String, dynamic> request) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _RideRequestSheet(request: request),
    );
  }

  void _listenToMessages() {
    if (!mounted || _rideProvider == null) return;
    _rideProvider!.addListener(_onProviderUpdate);
  }

  void _listenToIncomingCalls() {
    if (!mounted || _rideProvider == null) return;
    _rideProvider!.addListener(_onCallProviderUpdate);
  }

  void _onCallProviderUpdate() {
    if (!mounted || _rideProvider == null) return;
    
    final rideId = _rideProvider!.currentRideData?['rideId']?.toString();
    if (rideId != null) {
      if (_callSubscription != null) return;

      _callSubscription = CallService.listenToCall(rideId).listen((snapshot) {
        if (!mounted) return;
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;
        final activeCall = data['activeCall'];

        if (activeCall != null && activeCall['status'] == 'ringing') {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (activeCall['callerId'] != auth.currentUser?.id) {
            _showIncomingCallDialog(
              rideId,
              activeCall['callerName'] ?? 'Rider',
              _rideProvider?.currentRideData?['riderImage'],
            );
          }
        }
      });
    } else {
      _callSubscription?.cancel();
      _callSubscription = null;
    }
  }

  void _showIncomingCallDialog(String rideId, String callerName, String? callerImage) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceGrey : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ProfileImageWidget(
              imageUrl: callerImage,
              name: callerName,
              radius: 40,
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "Incoming In-App Call...",
              style: GoogleFonts.poppins(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 14),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCallAction(
                  icon: Icons.call_end,
                  color: Colors.red,
                  onTap: () {
                    CallService.updateCallStatus(rideId, null);
                    Navigator.pop(context);
                  },
                ),
                _buildCallAction(
                  icon: Icons.call,
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CallScreen(
                          channelId: rideId,
                          remoteUserName: callerName,
                          isIncoming: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallAction(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  void _onProviderUpdate() {
    if (!mounted || _rideProvider == null) return;

    if (_rideProvider!.status != _lastStatus) {
      if (mounted) {
        setState(() {
          _lastStatus = _rideProvider!.status;
        });
      }
      _loadRoute();
    }

    if (_rideProvider!.lastMessage != null) {
      final msg = _rideProvider!.lastMessage!;
      final lang = Provider.of<AuthProvider>(context, listen: false).language;
      _showInAppNotification(
          "${LocalizationService.translate('new_message', lang)}: ${msg.senderName}",
          msg.message);
      _rideProvider!.clearLastMessage();
    }
  }

  void _showInAppNotification(String title, String message) {
    if (!mounted) return;
    OverlayState? overlayState = Overlay.of(context);
    OverlayEntry overlayEntry;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceGrey : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppTheme.primaryGold, width: 1),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.chat, color: AppTheme.primaryGold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: AppTheme.primaryGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text(message,
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () => overlayEntry.remove());
  }

  @override
  void dispose() {
    _rideRequestSubscription?.cancel();
    _callSubscription?.cancel();
    _positionStream?.cancel();
    
    if (_rideProvider != null) {
      _rideProvider!.removeListener(_onProviderUpdate);
      _rideProvider!.removeListener(_onCallProviderUpdate);
    }

    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final rideProvider =
          Provider.of<DriverRideProvider>(context, listen: false);

      setState(() {
        _currentLatLng = ll.LatLng(position.latitude, position.longitude);
        _currentBearing = position.heading;
      });

      if (auth.currentUser != null) {
        rideProvider.updateLocation(
            position, auth.currentUser!.id, _isOnline);
      }

      _updateCameraPosition();
    });
  }

  void _updateCameraPosition() {
    if (!mounted || !_isMapReady) return;
    try {
      _mapController.move(_currentLatLng, 17);
    } catch (e) {
      debugPrint("Map move failed: $e");
    }
  }

  Future<void> _loadRoute() async {
    final rideProv = Provider.of<DriverRideProvider>(context, listen: false);
    if (rideProv.status == DriverRideStatus.idle) {
      if (mounted) {
        setState(() {
          _polylinePoints = [];
        });
      }
      return;
    }

    ll.LatLng? destination;
    if (rideProv.status == DriverRideStatus.pickingUp ||
        rideProv.status == DriverRideStatus.arrived) {
      destination = rideProv.pickupLatLng;
    } else if (rideProv.status == DriverRideStatus.tripInProgress) {
      destination = rideProv.dropoffLatLng;
    }

    if (destination != null) {
      try {
        final routeInfo = await RouteService.getRouteInfo(
          _currentLatLng.latitude.toString(),
          _currentLatLng.longitude.toString(),
          destination.latitude.toString(),
          destination.longitude.toString(),
        );
        if (mounted) {
          setState(() {
            _polylinePoints = routeInfo.polyline
                .map((p) => ll.LatLng(p.latitude, p.longitude))
                .toList();
          });
        }
      } catch (e) {
        debugPrint("Error loading route: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isVerified = auth.currentUser?.isVerified ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isVerified) {
      return _buildPendingVerificationScreen();
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundCharcoal : Colors.white,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLatLng,
              initialZoom: 17,
              maxZoom: 22,
              onMapReady: () {
                setState(() {
                  _isMapReady = true;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}",
                userAgentPackageName: 'com.sta.ride',
                maxNativeZoom: 20,
                maxZoom: 22,
              ),
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      color: AppTheme.primaryGold,
                      strokeWidth: 5,
                    ),
                  ],
                ),
              Consumer<DriverRideProvider>(
                builder: (context, rideProv, child) {
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLatLng,
                        width: 80,
                        height: 80,
                        child: Transform.rotate(
                          angle: (_currentBearing * (3.14159 / 180)),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SvgPicture.asset(
                                auth.currentUser?.vehicleType == 'BODABODA'
                                    ? 'assets/images/marker_bike.svg'
                                    : 'assets/images/marker_car.svg',
                                width: 50,
                                height: 50,
                                placeholderBuilder: (context) => Icon(
                                  auth.currentUser?.vehicleType == 'BODABODA'
                                      ? Icons.motorcycle
                                      : Icons.directions_car,
                                  color: AppTheme.primaryGold,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (rideProv.status != DriverRideStatus.idle &&
                          rideProv.pickupLatLng != null)
                        Marker(
                          point: ll.LatLng(rideProv.pickupLatLng!.latitude,
                              rideProv.pickupLatLng!.longitude),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on,
                              color: Colors.green, size: 40),
                        ),
                      if (rideProv.status != DriverRideStatus.idle &&
                          rideProv.dropoffLatLng != null)
                        Marker(
                          point: ll.LatLng(rideProv.dropoffLatLng!.latitude,
                              rideProv.dropoffLatLng!.longitude),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on,
                              color: Colors.red, size: 40),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 15,
            right: 15,
            child: _buildModernHeader(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 15,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'settings_btn',
              backgroundColor: (isDark ? AppTheme.surfaceGrey : Colors.white)
                  .withValues(alpha: 0.9),
              onPressed: _showSettingsModal,
              child: const Icon(Icons.settings, color: AppTheme.primaryGold),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _buildModernOnlineButton(),
          ),
          Positioned(
            bottom: 110,
            right: 15,
            child: Column(
              children: [
                _buildSosButton(context),
                const SizedBox(height: 12),
                FloatingActionButton(
                  mini: true,
                  heroTag: 'refresh_location',
                  backgroundColor:
                      (isDark ? AppTheme.surfaceGrey : Colors.white)
                          .withValues(alpha: 0.9),
                  onPressed:
                      _isRefreshingLocation ? null : _refreshCurrentLocation,
                  child: _isRefreshingLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primaryGold),
                        )
                      : Icon(Icons.my_location,
                          color: isDark ? Colors.white : Colors.black),
                ),
              ],
            ),
          ),
          _buildCurrentRideOverlay(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  bool _isRefreshingLocation = false;
  Future<void> _refreshCurrentLocation() async {
    if (_isRefreshingLocation) return;
    setState(() => _isRefreshingLocation = true);
    try {
      if (!kIsWeb) {
        Position? lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted && _currentLatLng.latitude == 0) {
          setState(() {
            _currentLatLng = ll.LatLng(lastPos.latitude, lastPos.longitude);
          });
          if (_isMapReady) {
            try {
              _mapController.move(_currentLatLng, 17);
            } catch (e) {}
          }
        }
      }
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        return Position(
          latitude: _currentLatLng.latitude, longitude: _currentLatLng.longitude,
          timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: _currentBearing,
          speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
        );
      });
      if (mounted) {
        setState(() {
          _currentLatLng = ll.LatLng(position.latitude, position.longitude);
          _isRefreshingLocation = false;
        });
        if (_isMapReady) {
          try { _mapController.move(_currentLatLng, 17); } catch (e) {}
        }
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
        if (auth.currentUser != null) {
          rideProvider.updateLocation(position, auth.currentUser!.id, _isOnline);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isRefreshingLocation = false);
    }
  }

  Widget _buildCurrentRideOverlay() {
    return Consumer<DriverRideProvider>(
      builder: (context, rideProvider, _) {
        if (rideProvider.status == DriverRideStatus.idle) return const SizedBox.shrink();
        return Positioned(left: 0, right: 0, bottom: 0, child: _ActiveRidePanel(rideProvider: rideProvider));
      },
    );
  }

  Widget _buildModernHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer2<AuthProvider, DriverRideProvider>(
      builder: (context, auth, rideProvider, _) {
        final lang = auth.language;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: (isDark ? AppTheme.surfaceGrey : Colors.white).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black12),
            boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.black12, blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('trips')
                .where('driverId', isEqualTo: auth.currentUser?.id)
                .where('status', whereIn: ['completed', 'paid', 'completed_paid', 'COMPLETED', 'PAID', 'COMPLETED_PAID'])
                .snapshots(),
            builder: (context, snapshot) {
              double totalEarnings = 0;
              int tripCount = 0;
              if (snapshot.hasData) {
                tripCount = snapshot.data!.docs.length;
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  totalEarnings += (data['fare'] as num?)?.toDouble() ?? 0.0;
                }
              }
              String level = auth.currentUser?.driverLevel ?? 'Bronze';
              Color levelColor = level == 'Gold' ? AppTheme.primaryGold : (level == 'Silver' ? Colors.grey : Colors.brown);
              return IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildHeaderItem("TZS ${totalEarnings.toStringAsFixed(0)}", LocalizationService.translate('earnings', lang), Icons.account_balance_wallet, AppTheme.primaryGold, isDark),
                    _buildHeaderDivider(isDark),
                    _buildHeaderItem(LocalizationService.translate(level.toLowerCase(), lang).toUpperCase(), LocalizationService.translate('rank', lang), Icons.workspace_premium, levelColor, isDark),
                    _buildHeaderDivider(isDark),
                    _buildHeaderItem(tripCount.toString(), LocalizationService.translate('trips', lang), Icons.directions_car, Colors.blueAccent, isDark),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeaderItem(String value, String label, IconData icon, Color color, bool isDark) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label.toUpperCase(), style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black54, fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      ]);
  }

  Widget _buildHeaderDivider(bool isDark) {
    return VerticalDivider(color: isDark ? Colors.white10 : Colors.black12, thickness: 1, indent: 5, endIndent: 5);
  }

  Widget _buildModernOnlineButton() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final lang = auth.language;
        return GestureDetector(
          onTap: () => _toggleOnlineStatus(!_isOnline),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 60,
            decoration: BoxDecoration(
              gradient: _isOnline ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]) : const LinearGradient(colors: [AppTheme.primaryGold, Color(0xFFFFB300)]),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: (_isOnline ? Colors.green : AppTheme.primaryGold).withValues(alpha: 0.4), blurRadius: _isOnline ? 20 : 10, spreadRadius: _isOnline ? 2 : 0, offset: const Offset(0, 4))],
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isOnline ? Icons.power_settings_new : Icons.bolt, color: _isOnline ? Colors.white : Colors.black, size: 24),
                  const SizedBox(width: 12),
                  Text(_isOnline ? LocalizationService.translate('waiting_requests', lang).toUpperCase() : LocalizationService.translate('go_online', lang).toUpperCase(), style: GoogleFonts.poppins(color: _isOnline ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSosButton(BuildContext context) {
    return FloatingActionButton(mini: true, heroTag: 'sos_btn', backgroundColor: Colors.red.withValues(alpha: 0.9), onPressed: () => _showSosDialog(context), child: const Icon(Icons.emergency, color: Colors.white));
  }

  void _showSosDialog(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceGrey : Colors.white,
        title: Text(LocalizationService.translate('emergency_sos', lang), style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(LocalizationService.translate('sos_desc', lang), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService.translate('cancel', lang), style: TextStyle(color: isDark ? Colors.white54 : Colors.black54))),
          ElevatedButton(
            onPressed: () {
              final rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
              rideProvider.sendSos(auth.currentUser!.id, rideProvider.currentLocation);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.translate('sos_sent_msg', lang)), backgroundColor: Colors.red));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(LocalizationService.translate('send_sos', lang), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer<AuthProvider>(
          builder: (context, auth, child) {
            final lang = auth.language;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceGrey : Colors.white,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                border: Border.all(color: AppTheme.primaryGold, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 20),
                  Text(LocalizationService.translate('preferences', lang), style: GoogleFonts.poppins(color: AppTheme.primaryGold, fontSize: 18, fontWeight: FontWeight.bold)),
                  Divider(color: isDark ? Colors.white12 : Colors.black12, height: 30),
                  Text(LocalizationService.translate('language', lang), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                  RadioGroup<String>(
                    groupValue: auth.language,
                    onChanged: (String? value) { if (value != null) auth.setLanguage(value); },
                    child: Row(children: [
                        Expanded(child: RadioListTile<String>(title: Text('English', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14)), value: 'English', activeColor: AppTheme.primaryGold)),
                        Expanded(child: RadioListTile<String>(title: Text('Kiswahili', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14)), value: 'Kiswahili', activeColor: AppTheme.primaryGold)),
                    ]),
                  ),
                  Divider(color: isDark ? Colors.white12 : Colors.black12),
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode, color: AppTheme.primaryGold),
                    title: Text(LocalizationService.translate('dark_mode', lang), style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                    value: auth.themeMode == ThemeMode.dark,
                    activeThumbColor: AppTheme.primaryGold,
                    onChanged: (bool value) { auth.toggleTheme(value); },
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

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0: setState(() => _selectedIndex = index); break;
      case 1:
        final auth = Provider.of<AuthProvider>(context, listen: false);
        Navigator.push(context, MaterialPageRoute(builder: (context) => DriverTripHistoryScreen(driverId: auth.currentUser?.id ?? '')));
        break;
      case 2: Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen())); break;
      case 3: Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())); break;
    }
  }

  Widget _buildBottomNav() {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      backgroundColor: isDark ? AppTheme.surfaceGrey : Colors.white,
      selectedItemColor: AppTheme.primaryGold,
      unselectedItemColor: isDark ? Colors.white54 : Colors.black54,
      type: BottomNavigationBarType.fixed,
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.home_filled), label: LocalizationService.translate('home', lang).toUpperCase()),
        BottomNavigationBarItem(icon: const Icon(Icons.history), label: LocalizationService.translate('trips', lang).toUpperCase()),
        BottomNavigationBarItem(icon: const Icon(Icons.wallet), label: LocalizationService.translate(auth.currentUser?.role == UserRole.driver ? 'wallet_title' : 'payment_trips', lang).toUpperCase()),
        BottomNavigationBarItem(icon: const Icon(Icons.person), label: LocalizationService.translate('profile', lang).toUpperCase()),
      ],
    );
  }

  void _toggleOnlineStatus(bool status) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
    if (status && rideProvider.isBlocked) {
      final lang = auth.language;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService.translate('debt_limit_reached', lang)),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: LocalizationService.translate('pay_now', lang).toUpperCase(), textColor: Colors.white, onPressed: () => _onItemTapped(2)),
      ));
      return;
    }
    setState(() { _isOnline = status; });
    if (!kIsWeb) {
      final service = FlutterBackgroundService();
      if (status) {
        _refreshCurrentLocation();
        bool isRunning = await service.isRunning();
        if (!isRunning) service.startService();
      } else {
        bool isRunning = await service.isRunning();
        if (isRunning) service.invoke("stopService");
      }
    } else if (status) { _refreshCurrentLocation(); }
    if (auth.currentUser != null) {
      rideProvider.updateStatus(auth.currentUser!.id, status ? 'idle' : 'offline', ll.LatLng(_currentLatLng.latitude, _currentLatLng.longitude), auth.currentUser!.vehicleType ?? 'Car', region: auth.currentUser!.region, city: auth.currentUser!.city);
    }
  }

  Widget _buildPendingVerificationScreen() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundCharcoal : Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: AppTheme.primaryGold.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.verified_user_outlined, size: 80, color: AppTheme.primaryGold)),
              const SizedBox(height: 40),
              Text(LocalizationService.translate('verification_pending', lang).toUpperCase(), style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 20),
              Text(LocalizationService.translate('verification_pending_desc', lang), textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 16)),
              const SizedBox(height: 60),
              SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: () { Provider.of<AuthProvider>(context, listen: false).logout(); Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false); }, style: ElevatedButton.styleFrom(backgroundColor: isDark ? Colors.white12 : Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(LocalizationService.translate('logout', lang), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)))),
            ]),
        ),
      ),
    );
  }
}

class _RideRequestSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  const _RideRequestSheet({required this.request});
  @override
  State<_RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<_RideRequestSheet> {
  int _secondsRemaining = 30;
  Timer? _timer;
  @override
  void initState() { super.initState(); _startTimer(); }
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) { setState(() => _secondsRemaining--); } else { _timer?.cancel(); Navigator.pop(context); }
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<DriverRideProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: isDark ? AppTheme.surfaceGrey : Colors.white, borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(LocalizationService.translate('new_ride_request', auth.language).toUpperCase(), style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: BorderRadius.circular(10)), child: Text("$_secondsRemaining s", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 20),
          _buildInfoRow(ProfileImageWidget(imageUrl: widget.request['riderImage'], name: widget.request['riderName'], radius: 12, iconSize: 12), (widget.request['isGuestRide'] == true && widget.request['guestName'] != null && widget.request['guestName'].toString().isNotEmpty) ? "${widget.request['guestName']} (${LocalizationService.translate('guest', auth.language)})" : widget.request['riderName'] ?? "Rider", isDark),
          const SizedBox(height: 10),
          _buildInfoRow(const Icon(Icons.location_on, color: AppTheme.primaryGold, size: 20), widget.request['pickupAddress'] ?? "Pickup", isDark),
          const SizedBox(height: 10),
          _buildInfoRow(const Icon(Icons.flag, color: AppTheme.primaryGold, size: 20), widget.request['dropoffAddress'] ?? "Dropoff", isDark),
          const SizedBox(height: 20),
          Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService.translate('cancel', auth.language).toUpperCase(), style: TextStyle(color: isDark ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 15)))),
              Expanded(child: ElevatedButton(onPressed: () async {
                    final currentUser = auth.currentUser!;
                    final lang = auth.language;
                    Navigator.pop(context);
                    final success = await rideProvider.acceptRide(widget.request, currentUser);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.translate('ride_no_longer_available', lang))));
                    }
                  }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold, foregroundColor: Colors.black), child: Text(LocalizationService.translate('accept_ride', auth.language).toUpperCase()))),
          ]),
      ]),
    );
  }
  Widget _buildInfoRow(Widget leading, String text, bool isDark) {
    return Row(children: [leading, const SizedBox(width: 12), Expanded(child: Text(text, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis))]);
  }
}

class _ActiveRidePanel extends StatelessWidget {
  final DriverRideProvider rideProvider;
  const _ActiveRidePanel({required this.rideProvider});
  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<DriverRideProvider>(context);
    final status = rideProvider.status;
    final data = rideProvider.currentRideData;
    if (data == null) return const SizedBox.shrink();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: isDark ? AppTheme.surfaceGrey : Colors.white, borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)), boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 20, offset: const Offset(0, -5))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
              ProfileImageWidget(imageUrl: data['riderImage'], name: data['riderName'], radius: 25),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text((data['isGuestRide'] == true) ? (data['guestName'] != null && data['guestName'].isNotEmpty) ? "${data['guestName']} (${LocalizationService.translate('guest', lang)})" : LocalizationService.translate('guest', lang).toUpperCase() : data['riderName'] ?? LocalizationService.translate('rider', lang).toUpperCase(), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(status == DriverRideStatus.pickingUp ? "${LocalizationService.translate('pickup', lang).toUpperCase()}: ${rideProvider.distanceToPickup.toStringAsFixed(1)} KM" : status == DriverRideStatus.arrived ? LocalizationService.translate('driver_arrived', lang).toUpperCase() : status == DriverRideStatus.tripInProgress ? "${LocalizationService.translate('dropoff', lang).toUpperCase()}: ${rideProvider.distanceToDestination.toStringAsFixed(1)} KM" : LocalizationService.translate('waiting_payment', lang).toUpperCase(), style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
              ])),
              IconButton(icon: const Icon(Icons.chat, color: AppTheme.primaryGold), onPressed: () { Navigator.pushNamed(context, '/chat', arguments: {'receiverId': data['riderId'], 'receiverName': data['riderName'] ?? 'Rider', 'senderId': auth.currentUser!.id, 'senderName': auth.currentUser!.name}); }),
              IconButton(icon: const Icon(Icons.call, color: AppTheme.primaryGold), onPressed: () { _showCallDialog(context, rideProvider, (data['isGuestRide'] == true && data['guestPhone'] != null && data['guestPhone'].isNotEmpty) ? data['guestPhone'] : data['riderPhone'] ?? '', (data['isGuestRide'] == true && data['guestName'] != null && data['guestName'].isNotEmpty) ? data['guestName'] : data['riderName'] ?? 'Rider'); }),
          ]),
          const SizedBox(height: 20),
          _buildActionButton(context),
          const SizedBox(height: 10),
          if (status == DriverRideStatus.pickingUp || status == DriverRideStatus.arrived) TextButton(onPressed: () => _showCancelDialog(context), child: Text(LocalizationService.translate('cancel_ride', lang), style: const TextStyle(color: Colors.red))),
      ]),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final rideProvider = Provider.of<DriverRideProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (rideProvider.status == DriverRideStatus.waitingForPayment) {
      double displayDistance = rideProvider.tripDistance / 1000;
      if (displayDistance <= 0.05) {
        final p = rideProvider.pickupLatLng; final d = rideProvider.dropoffLatLng;
        if (p != null && d != null) displayDistance = (Geolocator.distanceBetween(p.latitude, p.longitude, d.latitude, d.longitude) / 1000) * 1.2;
      }
      return Column(children: [
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.primaryGold.withValues(alpha: 0.2))), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(LocalizationService.translate('distance', lang).toUpperCase(), style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)), Text("${displayDistance.toStringAsFixed(1)} KM", style: GoogleFonts.poppins(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.w900))]),
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(LocalizationService.translate('fare', lang).toUpperCase(), style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)), Text("TZS ${NumberFormat('#,###').format(rideProvider.currentFare)}", style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.w900))]),
                if (rideProvider.paymentStatus == 'cash_selected') ...[const SizedBox(height: 15), Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withValues(alpha: 0.3))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.payments_rounded, color: Colors.green, size: 18), const SizedBox(width: 10), Text(LocalizationService.translate('rider_selected_cash', lang).toUpperCase(), style: GoogleFonts.poppins(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 11))]))]
          ])),
          const SizedBox(height: 25),
          SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: () => rideProvider.confirmPaymentReceived(), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(LocalizationService.translate('confirm_payment_received', lang).toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.w900, letterSpacing: 1)))),
      ]);
    }
    String text = ""; VoidCallback? onPressed; Color color = AppTheme.primaryGold;
    switch (rideProvider.status) {
      case DriverRideStatus.pickingUp: text = LocalizationService.translate('i_have_arrived', lang); onPressed = () => rideProvider.updateRideStatus(DriverRideStatus.arrived); break;
      case DriverRideStatus.arrived: text = LocalizationService.translate('start_trip', lang); onPressed = () => rideProvider.updateRideStatus(DriverRideStatus.tripInProgress); break;
      case DriverRideStatus.tripInProgress: text = LocalizationService.translate('complete_trip', lang); color = Colors.green; onPressed = () => rideProvider.completeRide(fare: rideProvider.currentFare, distance: rideProvider.tripDistance, duration: rideProvider.tripSeconds.toDouble()); break;
      default: return const SizedBox.shrink();
    }
    return SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: onPressed, style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(text.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))));
  }

  void _showCallDialog(BuildContext context, DriverRideProvider rideProvider, String phoneNumber, String name) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(context: context, backgroundColor: isDark ? AppTheme.surfaceGrey : Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (context) => Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(LocalizationService.translate('call_options', lang), style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 20),
            _buildCallOptionTile(context, icon: Icons.wifi_calling_3, title: LocalizationService.translate('in_app_call', lang), subtitle: LocalizationService.translate('in_app_call_desc', lang), isDark: isDark, onTap: () async { Navigator.pop(context); bool hasPermission = await CallService.handlePermissions(); if (hasPermission) { final rideId = rideProvider.currentRideData?['rideId']; if (rideId != null && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => CallScreen(channelId: rideId, remoteUserName: name))); } else { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService.translate('mic_permission_denied', lang)))); } }),
            Divider(color: isDark ? Colors.white10 : Colors.black12),
            _buildCallOptionTile(context, icon: Icons.phone, title: LocalizationService.translate('phone_call', lang), subtitle: phoneNumber, isDark: isDark, onTap: () async { Navigator.pop(context); final url = Uri.parse("tel:$phoneNumber"); if (await canLaunchUrl(url)) await launchUrl(url); }),
            const SizedBox(height: 20),
    ])));
  }

  Widget _buildCallOptionTile(BuildContext context, {required IconData icon, required String title, required String subtitle, required bool isDark, required VoidCallback onTap}) {
    return ListTile(leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.primaryGold.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: AppTheme.primaryGold)), title: Text(title, style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)), subtitle: Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)), onTap: onTap);
  }

  void _showCancelDialog(BuildContext context) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: isDark ? AppTheme.surfaceGrey : Colors.white, title: Text(LocalizationService.translate('cancel_ride_question', lang), style: TextStyle(color: isDark ? Colors.white : Colors.black)), content: Text(LocalizationService.translate('cancel_ride_confirm_desc', lang), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService.translate('no', lang))), TextButton(onPressed: () { rideProvider.cancelRideByDriver("Driver cancelled"); Navigator.pop(context); }, child: Text(LocalizationService.translate('yes_cancel', lang), style: const TextStyle(color: Colors.red)))]));
  }
}

class RadioGroup<T> extends StatelessWidget {
  final T groupValue; final ValueChanged<T?> onChanged; final Widget child;
  const RadioGroup({super.key, required this.groupValue, required this.onChanged, required this.child});
  @override
  Widget build(BuildContext context) { return child; }
}
