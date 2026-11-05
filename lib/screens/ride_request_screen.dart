import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:osm_nominatim/osm_nominatim.dart' as osm;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../providers/ride_provider.dart';
import '../providers/auth_provider.dart';
import '../models/ride.dart';
import '../models/vehicle.dart';
import '../services/route_service.dart';
import '../services/localization_service.dart';
import '../services/visual_positioning_service.dart';
import '../services/database_service.dart';
import '../services/voice_service.dart';
import '../services/call_service.dart';
import 'call_screen.dart';
import '../services/payment_service.dart';
import '../utils/theme.dart';
import '../widgets/profile_image_widget.dart';
import 'chat_screen.dart';

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({super.key});

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _isRequesting = false;
  double _distance = 0.0;
  String? _dropoffAddress;
  ll.LatLng? _dropoffLatLng;
  ll.LatLng? _pickupLatLng;
  String? _pickupAddress;
  String? _pickupRegion;
  String? _pickupCity;
  double _calculatedFare = 0.0;
  String _selectedPaymentMethod = "Cash";
  List<ll.LatLng> _polylinePoints = [];
  RideProvider? _rideProvider;
  bool _isDriverRouteFetched = false;
  DateTime? _lastRouteUpdateTime;
  String _arrivalInfo = "Calculating arrival...";
  int _userRating = 5;
  final TextEditingController _ratingController = TextEditingController();
  StreamSubscription? _callSubscription;

  bool _isGuestRide = false;
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rideProvider = Provider.of<RideProvider>(context, listen: false);
    _rideProvider?.addListener(_onRideUpdate);
    _rideProvider?.addListener(_onMessageUpdate);
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _rideProvider?.removeListener(_onRideUpdate);
    _rideProvider?.removeListener(_onMessageUpdate);
    _callSubscription?.cancel();
    _ratingController.dispose();
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    super.dispose();
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
                border: Border.all(color: AppTheme.primaryGold, width: 1),
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
                      color: AppTheme.primaryGold,
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
                            activeColor: AppTheme.primaryGold,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: Text('Kiswahili',
                                style:
                                    TextStyle(color: textColor, fontSize: 14)),
                            value: 'Kiswahili',
                            activeColor: AppTheme.primaryGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  SwitchListTile(
                    secondary:
                        Icon(Icons.dark_mode, color: AppTheme.primaryGold),
                    title: Text(
                      LocalizationService.translate('dark_mode', auth.language),
                      style: TextStyle(color: textColor),
                    ),
                    value: isDark,
                    activeThumbColor: AppTheme.primaryGold,
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

  void _onMessageUpdate() {
    final msg = _rideProvider?.lastMessage;
    if (msg != null) {
      _showInAppNotification(msg);
      _rideProvider?.clearLastMessage();
    }
  }

  OverlayEntry? _lastNotificationEntry;

  void _showInAppNotification(ChatMessage msg) {
    if (!mounted) return;

    // Remove existing notification if any
    _lastNotificationEntry?.remove();
    _lastNotificationEntry = null;

    final OverlayState overlayState = Overlay.of(context);
    final OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              _lastNotificationEntry?.remove();
              _lastNotificationEntry = null;

              final driverInfo = _rideProvider?.driverInfo;
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final currentUser = authProvider.currentUser;
              if (driverInfo != null && currentUser != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      receiverId: msg.senderId,
                      receiverName: msg.senderName,
                      senderId: currentUser.id,
                      senderName: currentUser.fullName,
                    ),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.orange, width: 1),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            "${LocalizationService.translate('new_message', Provider.of<AuthProvider>(context, listen: false).language)}: ${msg.senderName}",
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text(msg.message,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
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
      ),
    );

    _lastNotificationEntry = overlayEntry;
    overlayState.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
        if (_lastNotificationEntry == overlayEntry) {
          _lastNotificationEntry = null;
        }
      }
    });
  }

  void _onRideUpdate() {
    final rideProv = _rideProvider;
    if (rideProv == null) return;

    if (rideProv.currentRide != null) {
      _listenToIncomingCalls();
    } else {
      _callSubscription?.cancel();
      _callSubscription = null;
    }

    final driverLoc = rideProv.driverLocation;
    if (rideProv.isDriverFound &&
        driverLoc != null &&
        driverLoc.latitude.isFinite &&
        driverLoc.longitude.isFinite) {
      // 1. Move camera to follow driver or ride
      final driverLL = ll.LatLng(driverLoc.latitude, driverLoc.longitude);
      if (_isMapReady) {
        try {
          _mapController.move(driverLL, 17);
        } catch (e) {
          debugPrint("Map move failed: $e");
        }
      }

      final status = rideProv.currentRide?.status;
      final pickupLL = _pickupLatLng;

      // 2. Calculate distance and ETA to rider (if driver is coming) or to destination (if in progress)
      if ((status == RideStatus.accepted || status == RideStatus.arrived) &&
          pickupLL != null &&
          pickupLL.latitude.isFinite) {
        double distMeters = Geolocator.distanceBetween(
          driverLoc.latitude,
          driverLoc.longitude,
          pickupLL.latitude,
          pickupLL.longitude,
        );

        int mins = (distMeters / 500).ceil();
        final auth = Provider.of<AuthProvider>(context, listen: false);
        String info = LocalizationService.translate('eta_info', auth.language)
            .replaceFirst('{dist}', (distMeters / 1000).toStringAsFixed(1))
            .replaceFirst('{min}', mins.toString());

        if (mounted && _arrivalInfo != info) {
          setState(() {
            _arrivalInfo = info;
          });
        }
      } else if (status == RideStatus.inProgress) {
        if (_dropoffLatLng != null) {
          // Update polyline from current driver position to dropoff
          // Throttle updates to once every 30 seconds to save data/battery
          if (_lastRouteUpdateTime == null ||
              DateTime.now().difference(_lastRouteUpdateTime!) >
                  const Duration(seconds: 30)) {
            _updateLivePolyline();
          }
        }
      }

      // 3. Fetch route from Driver to Rider once
      if (!_isDriverRouteFetched) {
        _isDriverRouteFetched = true;
        _fetchDriverToRiderRoute();
      }
    } else {
      // Reset if driver is no longer found (cancelled/completed)
      _isDriverRouteFetched = false;
    }
  }

  Future<void> _updateLivePolyline() async {
    final driverLoc = _rideProvider?.driverLocation;
    final dropoffLL = _dropoffLatLng;
    if (driverLoc == null ||
        !driverLoc.latitude.isFinite ||
        dropoffLL == null ||
        !dropoffLL.latitude.isFinite) return;
    _lastRouteUpdateTime = DateTime.now();
    try {
      final routeInfo = await RouteService.getRouteInfo(
        driverLoc.latitude.toString(),
        driverLoc.longitude.toString(),
        dropoffLL.latitude.toString(),
        dropoffLL.longitude.toString(),
      );
      if (mounted) {
        setState(() {
          _polylinePoints = routeInfo.polyline
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Live polyline error: $e");
    }
  }

  Future<void> _fetchDriverToRiderRoute() async {
    final driverLoc = _rideProvider?.driverLocation;
    final pickupLL = _pickupLatLng;
    if (driverLoc == null ||
        !driverLoc.latitude.isFinite ||
        pickupLL == null ||
        !pickupLL.latitude.isFinite) return;
    try {
      final routeInfo = await RouteService.getRouteInfo(
        driverLoc.latitude.toString(),
        driverLoc.longitude.toString(),
        pickupLL.latitude.toString(),
        pickupLL.longitude.toString(),
      );
      if (mounted) {
        setState(() {
          _polylinePoints = routeInfo.polyline
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Driver route error: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 1. Get last known position immediately (Very fast)
      Position? position = await Geolocator.getLastKnownPosition();
      if (mounted && position != null) {
        _updatePosition(position);
      }

      // 2. Request current position with medium accuracy (10s timeout)
      Position? mediumPos;
      try {
        mediumPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint("Medium accuracy timeout/error: $e");
      }

      if (mounted && mediumPos != null) {
        _updatePosition(mediumPos);
      }

      // 3. Request high accuracy (15s timeout)
      try {
        Position highAccPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
          timeLimit: const Duration(seconds: 15),
        );
        if (mounted) {
          _updatePosition(highAccPos);
        }
      } catch (e) {
        debugPrint("High accuracy timeout/error: $e");
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  void _updatePosition(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) return;
    final loc = ll.LatLng(position.latitude, position.longitude);
    setState(() {
      _pickupLatLng = loc;
    });
    // Move camera to current position
    if (_isMapReady) {
      try {
        if (_mapController.camera.center != loc) {
          _mapController.move(loc, 17);
        }
      } catch (e) {
        debugPrint("Map move in _updatePosition failed: $e");
      }
    }
    _getPlaceName(loc.latitude, loc.longitude, isPickup: true);
    _loadRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize localized arrival info
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    if (_arrivalInfo ==
        LocalizationService.translate('calculating_arrival', 'English')) {
      _arrivalInfo = LocalizationService.translate('calculating_arrival', lang);
    }

    // Anzisha msikilizaji wa RideProvider kwa ajili ya Camera tracking
    final newRideProvider = Provider.of<RideProvider>(context);
    if (_rideProvider != newRideProvider) {
      _rideProvider?.removeListener(_onRideUpdate);
      _rideProvider?.removeListener(_onMessageUpdate);
      _rideProvider = newRideProvider;
      _rideProvider?.addListener(_onRideUpdate);
      _rideProvider?.addListener(_onMessageUpdate);
    }

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args != null) {
      // 1. Shughulikia Pickup: Hakikisha jina linatafutwa kama ni generic
      final pickupArg = args['pickupLatLng'] as ll.LatLng?;
      if (_pickupLatLng == null && pickupArg != null) {
        _pickupLatLng = pickupArg;
      }

      // Ikiwa jina ni generic au halipo, anza kutafuta jina halisi la mtaa
      final currentPickupLL = _pickupLatLng;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final lang = authProvider.language;
      final isGeneric = _pickupAddress == null || 
                       _pickupAddress == "Current location" || 
                       _pickupAddress == LocalizationService.translate('current_location', lang) ||
                       _pickupAddress == "Locating...";

      if (currentPickupLL != null && isGeneric) {
        _getPlaceName(currentPickupLL.latitude, currentPickupLL.longitude,
            isPickup: true);
      }

      // 2. Shughulikia Dropoff
      final dropoffArg = args['dropoffLatLng'] as ll.LatLng?;
      if (_dropoffLatLng == null && dropoffArg != null) {
        _dropoffLatLng = dropoffArg;
        _dropoffAddress = args['dropoff'] as String?;
        _loadRoute();
      } else if (_distance == 0.0) {
        _loadRoute();
      }
    }
  }

  Future<void> _getPlaceName(double lat, double lon,
      {bool isPickup = true}) async {
    if (!lat.isFinite || !lon.isFinite) return;

    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    if (mounted) {
      setState(() {
        if (isPickup) {
          _pickupAddress = LocalizationService.translate('locating', lang);
        } else {
          _dropoffAddress = LocalizationService.translate('locating', lang);
        }
      });
    }

    try {
      // Tunatumia Nominatim (OSM) huku pia kwa usahihi zaidi bila malipo
      final nominatim = osm.Nominatim(userAgent: 'STA-Ride-App-v1-User-Agent');
      final reverseSearchResult = await nominatim.reverseSearch(
        lat: lat,
        lon: lon,
        addressDetails: true,
      );

      String address = reverseSearchResult.displayName;

      // Kurahisisha jina (Shorten address)
      List<String> parts = address.split(',');
      if (parts.length > 2) {
        address = "${parts[0].trim()}, ${parts[1].trim()}";
      }

      if (mounted) {
        setState(() {
          if (isPickup) {
            _pickupAddress = address;
            _pickupRegion = reverseSearchResult.address?['state']?.toString() ?? "Arusha";
            _pickupCity = reverseSearchResult.address?['city']?.toString() ?? "Arusha";
          } else {
            _dropoffAddress = address;
          }
        });
        return;
      }
    } catch (e) {
      debugPrint("Reverse Geocode Error (Nominatim): $e");
    }

    // Ikishindikana, tumia majina mbadala
    if (mounted) {
      setState(() {
        if (isPickup) {
          _pickupAddress = LocalizationService.translate('current_location', lang);
        } else {
          _dropoffAddress = LocalizationService.translate('pinned_location', lang);
        }
      });
    }
  }

  Future<void> _loadRoute() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) return;

    final ll.LatLng pickup = _pickupLatLng ??
        (args['pickupLatLng'] as ll.LatLng?) ??
        const ll.LatLng(-3.37, 36.68);
    
    if (!pickup.latitude.isFinite) return;

    final vehicle = args['vehicle'] as Vehicle?;
    final ll.LatLng? dropoff =
        _dropoffLatLng ?? (args['dropoffLatLng'] as ll.LatLng?);

    if (dropoff == null || !dropoff.latitude.isFinite || vehicle == null) return;

    try {
      final routeInfo = await RouteService.getRouteInfo(
        pickup.latitude.toString(),
        pickup.longitude.toString(),
        dropoff.latitude.toString(),
        dropoff.longitude.toString(),
      );

      if (mounted) {
        setState(() {
          _distance = routeInfo.distance;
          _polylinePoints = routeInfo.polyline
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();
          _calculatedFare =
              vehicle.calculateFare(routeInfo.distance, routeInfo.duration);
        });

        if (_polylinePoints.isNotEmpty &&
            _isMapReady &&
            pickup.latitude.isFinite &&
            dropoff.latitude.isFinite) {
          try {
            final bounds = LatLngBounds(pickup, dropoff);
            _mapController.fitCamera(
              CameraFit.bounds(
                  bounds: bounds, padding: const EdgeInsets.all(70)),
            );
          } catch (e) {
            debugPrint("Map fitCamera failed: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("Route loading failed: $e");
    }
  }

  void _searchAddress({bool isPickup = false}) async {
    final result = await showSearch(
      context: context,
      delegate: AddressSearchDelegate(),
    );

    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickupAddress = result['name'];
          _pickupLatLng = ll.LatLng(result['lat'], result['lng']);
        } else {
          _dropoffAddress = result['name'];
          _dropoffLatLng = ll.LatLng(result['lat'], result['lng']);
        }
      });
      _loadRoute();
    }
  }

  void _startVoiceSearch({bool isPickup = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, color: Colors.orange, size: 50),
            const SizedBox(height: 20),
            Text(
              LocalizationService.translate('voice_search_prompt',
                  Provider.of<AuthProvider>(context, listen: false).language),
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              LocalizationService.translate('voice_search_example',
                  Provider.of<AuthProvider>(context, listen: false).language),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),
            const LinearProgressIndicator(color: Colors.orange),
          ],
        ),
      ),
    );

    try {
      final result = await VoiceService.listenAndGetLocation();
      if (mounted) Navigator.pop(context); // Close dialog

      if (result != null) {
        setState(() {
          if (isPickup) {
            _pickupAddress = result['name'];
            _pickupLatLng = result['location'];
          } else {
            _dropoffAddress = result['name'];
            _dropoffLatLng = result['location'];
          }
        });
        _loadRoute();

        if (mounted) {
          final lang =
              Provider.of<AuthProvider>(context, listen: false).language;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  LocalizationService.translate('location_found', lang)
                      .replaceFirst('{name}', result['name'])),
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
                content: Text(LocalizationService.translate(
                    'voice_not_understood', lang))),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Voice Search Error: $e");
    }
  }

  void _triggerVisualAI({bool isPickup = true}) async {
    final result = await VisualPositioningService.detectLocationFromCamera();
    if (result != null) {
      final ll.LatLng loc = result['location'];
      final String name = result['name'];

      setState(() {
        if (isPickup) {
          _pickupLatLng = loc;
          _pickupAddress = name;
        } else {
          _dropoffLatLng = loc;
          _dropoffAddress = name;
        }
      });

      if (_isMapReady) {
        try {
          _mapController.move(loc, 18);
        } catch (e) {
          debugPrint("Map move in AI failed: $e");
        }
      }
      _loadRoute();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate('ai_recognized',
                    Provider.of<AuthProvider>(context, listen: false).language)
                .replaceFirst('{name}', name)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate('ai_failed',
                Provider.of<AuthProvider>(context, listen: false).language)),
          ),
        );
      }
      if (isPickup) _getCurrentLocation();
    }
  }

  void _handleRequest() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final rideProvider = Provider.of<RideProvider>(context, listen: false);

    if (args == null ||
        (_dropoffLatLng == null && args['dropoffLatLng'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(LocalizationService.translate(
                'select_destination', authProvider.language))),
      );
      return;
    }

    setState(() => _isRequesting = true);

    final user = authProvider.currentUser;
    if (user == null) {
      setState(() => _isRequesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(LocalizationService.translate(
                'session_expired', authProvider.language))),
      );
      return;
    }

    final success = await rideProvider.requestRide(
      userId: user.id,
      riderName: user.name,
      riderPhone: user.phoneNumber,
      pickupLat: _pickupLatLng?.latitude ??
          (args['pickupLatLng'] as ll.LatLng?)?.latitude ??
          0.0,
      pickupLng: _pickupLatLng?.longitude ??
          (args['pickupLatLng'] as ll.LatLng?)?.longitude ??
          0.0,
      pickupAddress: _pickupAddress ??
          (args['pickup'] as String?) ??
          LocalizationService.translate('unknown', authProvider.language),
      dropoffLat: _dropoffLatLng?.latitude ??
          (args['dropoffLatLng'] as ll.LatLng?)?.latitude ??
          0.0,
      dropoffLng: _dropoffLatLng?.longitude ??
          (args['dropoffLatLng'] as ll.LatLng?)?.longitude ??
          0.0,
      dropoffAddress: _dropoffAddress ??
          (args['dropoff'] as String?) ??
          LocalizationService.translate('unknown', authProvider.language),
      region: _pickupRegion ?? (args['region'] as String?) ?? user.region,
      city: _pickupCity ?? (args['city'] as String?) ?? user.city,
      fare: _calculatedFare > 0
          ? _calculatedFare
          : ((args['fare'] as num?)?.toDouble() ?? 0.0),
      vehicleType: (args['vehicle'] as Vehicle?)?.name ?? "Car",
      riderImage: user.profileImageUrl,
      isGuestRide: _isGuestRide,
      guestName: _isGuestRide ? _guestNameController.text.trim() : null,
      guestPhone: _isGuestRide ? _guestPhoneController.text.trim() : null,
    );

    if (!mounted) return;

    if (mounted) {
      if (!success) {
        final lang = authProvider.language;
        setState(() => _isRequesting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(LocalizationService.translate(
                  rideProvider.error ?? 'request_failed', lang))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final pickupAddress = args?['pickup'] ?? "Current location";
    final rawPickupLatLng = args?['pickupLatLng'];
    final pickupLatLng = (rawPickupLatLng is ll.LatLng && rawPickupLatLng.latitude.isFinite) 
        ? rawPickupLatLng 
        : const ll.LatLng(-3.37, 36.68);
    
    final currentCenter = _pickupLatLng ?? pickupLatLng;
    final safeCenter = (currentCenter.latitude.isFinite && currentCenter.longitude.isFinite)
        ? currentCenter
        : const ll.LatLng(-3.37, 36.68);

    final vehicleName = (args?['vehicle'] as Vehicle?)?.name ?? "BODABODA";
    final fare =
        _calculatedFare > 0 ? _calculatedFare : (args?['fare'] ?? 3500.0);
    final displayDropoff = _dropoffAddress ?? args?['dropoff'] ?? "Where to?.";

    debugPrint(
        "UI Debug: $pickupAddress, $vehicleName, $fare, $displayDropoff");

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Background (Satellite View with High Zoom)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: safeCenter,
              initialZoom: 18,
              maxZoom: 22,
              onMapReady: () {
                if (mounted) {
                  setState(() {
                    _isMapReady = true;
                  });
                }
              },
              onTap: (tapPosition, latLng) {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                setState(() {
                  _dropoffLatLng = latLng;
                  _dropoffAddress = LocalizationService.translate(
                      'pinned_location', auth.language);
                });
                _getPlaceName(latLng.latitude, latLng.longitude,
                    isPickup: false);
                _loadRoute();
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
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      color: Colors.orange,
                      strokeWidth: 6,
                    ),
                  ],
                ),
              Consumer<RideProvider>(builder: (context, rideProv, child) {
                return MarkerLayer(
                  markers: [
                    // Alama ya Pickup (Rider)
                    if (safeCenter.latitude.isFinite)
                      Marker(
                        point: safeCenter,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: Colors.green, size: 40),
                      ),
                    // Alama ya Dropoff
                    if (_dropoffLatLng != null && _dropoffLatLng!.latitude.isFinite)
                      Marker(
                        point: _dropoffLatLng!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 40),
                      )
                    else if (args?['dropoffLatLng'] != null && (args?['dropoffLatLng'] as ll.LatLng).latitude.isFinite)
                      Marker(
                        point: args?['dropoffLatLng'],
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 40),
                      ),
                    // ALAMA YA DEREVA (Hii itaonekana tu akishakubali)
                    if (rideProv.isDriverFound &&
                        rideProv.driverLocation != null &&
                        rideProv.driverLocation!.latitude.isFinite)
                      Marker(
                        point: ll.LatLng(rideProv.driverLocation!.latitude,
                            rideProv.driverLocation!.longitude),
                        width: 80,
                        height: 80,
                        child: Transform.rotate(
                          angle: (rideProv.driverBearing * (3.14159 / 180)),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                width: 70,
                                height: 70,
                              ),
                              SvgPicture.asset(
                                rideProv.currentRide?.vehicleType == 'BODABODA'
                                    ? 'assets/images/marker_bike.svg'
                                    : 'assets/images/marker_car.svg',
                                width: 50,
                                height: 50,
                                placeholderBuilder: (context) => Icon(
                                  rideProv.currentRide?.vehicleType ==
                                          'BODABODA'
                                      ? Icons.motorcycle
                                      : Icons.directions_car,
                                  color: Colors.blue[800],
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),

          // 2. Top Floating Buttons
          Positioned(
            top: 50,
            left: 20,
            child: Row(
              children: [
                _buildTopRoundBtn(Icons.person,
                    () => Navigator.pushNamed(context, '/profile')),
              ],
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: _buildTopRoundBtn(Icons.settings, _showSettingsModal),
          ),

          // 3. Bottom UI Panel
          Align(
            alignment: Alignment.bottomCenter,
            child: Consumer2<RideProvider, AuthProvider>(
              builder: (context, rideProvider, auth, child) {
                final currentRide = rideProvider.currentRide;
                if (currentRide?.status == RideStatus.completed) {
                  return _buildRatingPanel(rideProvider, auth);
                }
                if (rideProvider.isDriverFound && currentRide != null) {
                  return _buildDriverAcceptedPanel(rideProvider);
                }

                final args = ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?;
                final vehicle = args?['vehicle'] as Vehicle?;
                final vehicleName = vehicle?.name ?? "Vehicle";
                final pickupAddress =
                    args?['pickup'] as String? ?? "Current location";
                final dropoffAddress =
                    args?['dropoff'] as String? ?? "Destination";
                final displayDropoff = _dropoffAddress ?? dropoffAddress;
                final fare = _calculatedFare > 0
                    ? _calculatedFare
                    : ((args?['fare'] as num?)?.toDouble() ?? 0.0);

                if (_isRequesting) {
                  return _buildSearchingPanel(vehicleName,
                      _pickupAddress ?? pickupAddress, displayDropoff);
                }
                return _buildConfirmPanel(vehicleName,
                    _pickupAddress ?? pickupAddress, displayDropoff, fare);
              },
            ),
          ),

          // 4. SOS Button (Only during active ride)
          Consumer<RideProvider>(builder: (context, rideProv, child) {
            final status = rideProv.currentRide?.status;
            if (status == RideStatus.accepted ||
                status == RideStatus.arrived ||
                status == RideStatus.inProgress) {
              return Positioned(
                top: 120,
                right: 20,
                child: _buildTopRoundBtn(
                  Icons.sos,
                  _showSosDialog,
                  color: Colors.red.shade900,
                ),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }

  Widget _buildDriverAcceptedPanel(RideProvider rideProvider) {
    final driver = rideProvider.driverInfo;
    final isArrived = rideProvider.currentRide?.status == RideStatus.arrived;
    final isInProgress =
        rideProvider.currentRide?.status == RideStatus.inProgress;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          // From - Distance - To Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildLocTileSimple(
                      Icons.location_on,
                      Colors.green,
                      LocalizationService.translate('pickup', lang),
                      rideProvider.currentRide?.pickupLocation.address ?? ""),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    "${_distance.toStringAsFixed(1)} KM",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white70),
                  ),
                ),
                Expanded(
                  child: _buildLocTileSimple(
                      Icons.location_on,
                      Colors.red,
                      LocalizationService.translate('dropoff', lang),
                      rideProvider.currentRide?.dropoffLocation.address ?? ""),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isInProgress
                  ? Colors.blue.withValues(alpha: 0.1)
                  : AppTheme.primaryGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isInProgress
                    ? Colors.blue.withValues(alpha: 0.3)
                    : AppTheme.primaryGold.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    ProfileImageWidget(
                      imageUrl: driver?.profileImageUrl,
                      name: driver?.name,
                      radius: 35,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                              isInProgress
                                  ? LocalizationService.translate(
                                      'trip_in_progress', lang)
                                  : isArrived
                                      ? LocalizationService.translate(
                                          'driver_arrived', lang)
                                      : LocalizationService.translate(
                                          'driver_accepted_msg', lang),
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppTheme.primaryGold)),
                          const SizedBox(height: 4),
                          if (!isInProgress)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Text(isArrived ? "0.1KM" : _arrivalInfo,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ),
                          if (isInProgress)
                            Text(
                                LocalizationService.translate(
                                    'enjoy_ride', lang),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDriverDetailText(LocalizationService.translate(
                                'name_label', lang)
                            .replaceFirst('{name}', driver?.fullName ?? '')),
                        _buildDriverDetailText(LocalizationService.translate(
                                'vehicle_label', lang)
                            .replaceFirst('{model}', driver?.carModel ?? '')),
                        _buildDriverDetailText(
                            LocalizationService.translate('color_label', lang)
                                .replaceFirst(
                                    '{color}', driver?.carColor ?? 'BLUE')),
                        _buildDriverDetailText(LocalizationService.translate(
                                'plate_label', lang)
                            .replaceFirst('{plate}', driver?.carPlate ?? '')),
                        _buildDriverDetailText(LocalizationService.translate(
                                'rating_label', lang)
                            .replaceFirst('{rating}',
                                driver?.rating.toStringAsFixed(1) ?? '5.0')),
                      ],
                    ),
                    Row(
                      children: [
                        if (!isArrived && !isInProgress)
                          _buildDriverActionBtn(
                              LocalizationService.translate('cancel', lang),
                              Colors.red.withValues(alpha: 0.8), () {
                            rideProvider.cancelRide();
                            setState(() => _isRequesting = false);
                          }),
                        if (isArrived)
                          _buildDriverActionBtn(
                              LocalizationService.translate('confirm', lang),
                              Colors.green.withValues(alpha: 0.8), () async {
                            await rideProvider.startRide();
                          }),
                        if (isInProgress)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                                LocalizationService.translate(
                                        'trip_in_progress', lang)
                                    .toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10)),
                          ),
                        const SizedBox(width: 5),
                        if (!isInProgress) ...[
                          _buildDriverActionBtn(
                              "", AppTheme.primaryGold.withValues(alpha: 0.8),
                              () {
                            final driverId = driver?.id;
                            final driverName = driver?.name;
                            final authProvider = Provider.of<AuthProvider>(
                                context,
                                listen: false);
                            final currentUser = authProvider.currentUser;
                            if (driverId != null && currentUser != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    receiverId: driverId,
                                    receiverName: driverName ?? "Driver",
                                    senderId: currentUser.id,
                                    senderName: currentUser.fullName,
                                  ),
                                ),
                              );
                            }
                          }, icon: Icons.chat),
                          const SizedBox(width: 5),
                          _buildDriverActionBtn(
                              "", Colors.blue.withValues(alpha: 0.8), () {
                            _showCallDialog(driver?.phoneNumber ?? '',
                                driver?.fullName ?? 'Driver');
                          }, icon: Icons.call),
                        ],
                      ],
                    )
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showCallDialog(String phoneNumber, String name) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LocalizationService.translate('call_options', lang),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            _buildCallOptionTile(
              icon: Icons.wifi_calling_3,
              title: LocalizationService.translate('in_app_call', lang),
              subtitle: LocalizationService.translate('in_app_call_desc', lang),
              onTap: () async {
                Navigator.pop(context);
                bool hasPermission = await CallService.handlePermissions();
                if (hasPermission && mounted) {
                  final rideId =
                      Provider.of<RideProvider>(context, listen: false)
                          .currentRide
                          ?.id;
                  if (rideId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CallScreen(
                          channelId: rideId,
                          remoteUserName: name,
                        ),
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(LocalizationService.translate(
                          'mic_permission_denied', lang)),
                    ),
                  );
                }
              },
            ),
            const Divider(color: Colors.white10),
            _buildCallOptionTile(
              icon: Icons.phone,
              title: LocalizationService.translate('phone_call', lang),
              subtitle: phoneNumber,
              onTap: () async {
                Navigator.pop(context);
                final url = Uri.parse("tel:$phoneNumber");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCallOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primaryGold.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.primaryGold),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  Widget _buildDriverDetailText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Colors.white,
      ),
    );
  }

  Widget _buildDriverActionBtn(String text, Color color, VoidCallback onTap,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            if (icon != null) Icon(icon, color: Colors.white, size: 16),
            if (text.isNotEmpty)
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingPanel(RideProvider rideProvider, AuthProvider auth) {
    final lang = auth.language;
    final ride = rideProvider.currentRide;

    // Hakikisha tunapata umbali halisi kutoka kwa ride object au variable ya ndani
    double displayDistance = (ride?.distance ?? 0.0) > 0
        ? ride!.distance
        : (_distance > 0 ? _distance : 0.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 40,
            offset: const Offset(0, -10),
          )
        ],
        border: Border.all(
          color: AppTheme.primaryGold.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Indicator
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 25),
          Text(
            LocalizationService.translate('trip_summary', lang).toUpperCase(),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppTheme.primaryGold,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 25),
          // Info Card
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                    LocalizationService.translate('pickup', lang),
                    ride?.pickupLocation.address ??
                        LocalizationService.translate('unknown', lang)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                _buildSummaryRow(
                    LocalizationService.translate('dropoff', lang),
                    ride?.dropoffLocation.address ??
                        LocalizationService.translate('unknown', lang)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryRow(
                          LocalizationService.translate('distance', lang),
                          "${displayDistance.toStringAsFixed(1)} KM"),
                    ),
                    Container(
                      width: 1,
                      height: 15,
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                    ),
                    Expanded(
                      child: _buildSummaryRow(
                          LocalizationService.translate('fare', lang),
                          "TZS ${NumberFormat('#,###').format(ride?.fare ?? _calculatedFare)}"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            LocalizationService.translate('rate_driver_desc', lang),
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  index < _userRating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: AppTheme.primaryGold,
                  size: 45,
                ),
                onPressed: () => setState(() => _userRating = index + 1),
              );
            }),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: _ratingController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  LocalizationService.translate('write_comment_optional', lang),
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.4),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                    color: AppTheme.primaryGold.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                    color: AppTheme.primaryGold.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppTheme.primaryGold, width: 1.5),
              ),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    final ride = rideProvider.currentRide;
                    if (ride != null) {
                      Navigator.pushNamed(context, '/receipt', arguments: {
                        'id': ride.id,
                        'timestamp': DateTime.now().toIso8601String(),
                        'fare': ride.fare > 0 ? ride.fare : _calculatedFare,
                        'pickup': ride.pickupLocation.address,
                        'dropoff': ride.dropoffLocation.address,
                        'driverName':
                            rideProvider.driverInfo?.fullName ?? "STA Driver",
                        'vehicleType': ride.vehicleType,
                        'distance':
                            ride.distance > 0 ? ride.distance : _distance,
                        'payment_method': _selectedPaymentMethod,
                      });
                    }
                  },
                  child: Text(
                    LocalizationService.translate('view_receipt', lang)
                        .toUpperCase(),
                    style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.1),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGold.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final ride = rideProvider.currentRide;
                      final rideId = ride?.id;
                      final driverId = ride?.driverId;

                      if (ride != null) {
                        // Hakikisha safari inarekodiwa kwenye Firestore kabla ya kuifuta
                        await DatabaseService.instance.recordTrip({
                          'id': ride.id,
                          'riderId': auth.currentUser?.id,
                          'riderName': auth.currentUser?.name,
                          'driverId': ride.driverId,
                          'driverName': rideProvider.driverInfo?.fullName ??
                              LocalizationService.translate('sta_driver', lang),
                          'pickup': ride.pickupLocation.address,
                          'dropoff': ride.dropoffLocation.address,
                          'fare': ride.fare > 0 ? ride.fare : _calculatedFare,
                          'distance':
                              ride.distance > 0 ? ride.distance : _distance,
                          'status': 'completed',
                          'payment_method': _selectedPaymentMethod,
                          'timestamp': DateTime.now().toUtc().toIso8601String(),
                          'vehicleType': ride.vehicleType,
                        });
                      }

                      if (rideId != null && driverId != null) {
                        await rideProvider.submitRating(
                          rideId: rideId,
                          targetId: driverId,
                          rating: _userRating,
                          comment: _ratingController.text,
                          role: 'rider',
                          riderName: auth.currentUser?.name ?? "Rider",
                          driverId: driverId,
                        );
                      }
                      rideProvider.clearRide();
                      if (mounted) {
                        setState(() {
                          _isRequesting = false;
                          _polylinePoints = [];
                          _distance = 0;
                          _arrivalInfo = LocalizationService.translate(
                              'calculating_arrival', lang);
                          _ratingController.clear();
                          _userRating = 5;
                        });
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    child: Text(
                      LocalizationService.translate('complete_trip', lang)
                          .toUpperCase(),
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase() + ":",
            style: GoogleFonts.poppins(
              color: AppTheme.primaryGold.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileMoneyOptions() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E), // Match surfaceGrey
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(LocalizationService.translate('select_network', lang),
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
            const SizedBox(height: 20),
            _buildMMOption("M-Pesa", Colors.red, "074...", lang),
            _buildMMOption("Tigo Pesa", Colors.blue, "065...", lang),
            _buildMMOption("Airtel Money", Colors.redAccent, "068...", lang),
            _buildMMOption("HaloPesa", Colors.orange, "062...", lang),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMMOption(String name, Color color, String prefix, String lang) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: const Icon(Icons.phone_android, color: Colors.white, size: 20),
      ),
      title: Text(name,
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(
          LocalizationService.translate('simulated_stk_prefix', lang)
              .replaceFirst('{prefix}', prefix),
          style: const TextStyle(color: Colors.white70, fontSize: 10)),
      trailing:
          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
      onTap: () {
        Navigator.pop(context);
        _startSimulatedSTK(name);
      },
    );
  }

  void _startSimulatedSTK(String provider) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final ride = Provider.of<RideProvider>(context, listen: false).currentRide;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            CircularProgressIndicator(color: AppTheme.primaryGold),
            const SizedBox(height: 20),
            Text(LocalizationService.translate('wait_a_moment', lang),
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(
              LocalizationService.translate('stk_init_msg', lang)
                  .replaceFirst('{provider}', provider),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );

    // Banza mchakato wa kweli wa malipo (Hii itatuma STK Push via Cloud Function)
    if (ride != null) {
      PaymentService.initiateCheckout(
        phone: auth.currentUser?.phoneNumber ?? '',
        amount: ride.fare > 0 ? ride.fare : _calculatedFare,
        rideId: ride.id,
        userRole: 'rider',
      );
    }

    // Simulate delay for UI feedback
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        setState(() => _selectedPaymentMethod = provider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate('stk_sent_msg', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  Widget _buildSearchingPanel(
      String vehicleName, String pickup, String dropoff) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.surfaceGrey, Colors.black],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          // Handle Indicator
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.white12, borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 25),
          // From - Distance - To Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildLocTileSimple(Icons.location_on, Colors.green,
                      LocalizationService.translate('pickup', lang), pickup),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      const Icon(Icons.compare_arrows,
                          size: 14, color: Colors.white24),
                      Text(
                        _distance > 0
                            ? "${_distance.toStringAsFixed(1)} KM"
                            : "-- KM",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildLocTileSimple(Icons.location_on, Colors.red,
                      LocalizationService.translate('dropoff', lang), dropoff),
                ),
              ],
            ),
          ),
          const SizedBox(height: 35),
          Text(
            LocalizationService.translate('searching_driver', lang)
                .toUpperCase(),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 1.5,
              color: AppTheme.primaryGold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LocalizationService.translate('connecting_drivers', lang),
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 35),
          // Improved Animated Searching Circle
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer Glow
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryGold.withValues(alpha: 0.05),
                ),
              ),
              // Rotating Indicators
              SizedBox(
                width: 130,
                height: 130,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppTheme.primaryGold),
                ),
              ),
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGold.withValues(alpha: 0.3)),
                ),
              ),
              // Center Vehicle Info
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceGrey,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black45, blurRadius: 15, spreadRadius: 2)
                  ],
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      vehicleName.toUpperCase() == 'BODABODA'
                          ? Icons.motorcycle
                          : Icons.directions_car,
                      color: AppTheme.primaryGold,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicleName.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 45),
          // Cancel Button - Styled as a prominent action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () {
                  setState(() => _isRequesting = false);
                  Provider.of<RideProvider>(context, listen: false)
                      .cancelRide();
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  LocalizationService.translate('cancel_request', lang)
                      .toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLocTileSimple(
      IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(15),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              "$label $value",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRoundBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          color: color ?? AppTheme.surfaceGrey,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Icon(icon,
            color: color != null ? Colors.white : AppTheme.primaryGold,
            size: 32),
      ),
    );
  }

  void _showSosDialog() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        title: Text(LocalizationService.translate('emergency_sos_rider', lang),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(LocalizationService.translate('sos_danger_msg', lang),
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LocalizationService.translate('cancel_caps', lang),
                  style: const TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.red),
            onPressed: () async {
              final authProv =
                  Provider.of<AuthProvider>(context, listen: false);
              final rideProv =
                  Provider.of<RideProvider>(context, listen: false);

              rideProv.sendSos(authProv.currentUser?.id ?? '', _pickupLatLng);

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
            child: Text(LocalizationService.translate('send_sos_caps', lang)),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmPanel(
      String vehicleName, String pickup, String dropoff, double fare) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 25),
          // Location Inputs Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Expanded(
                    child: _buildLocTile(
                        Icons.location_on,
                        Colors.green,
                        LocalizationService.translate('pickup_point', lang),
                        pickup,
                        () => _searchAddress(isPickup: true),
                        isPickup: true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildLocTile(
                        Icons.location_on,
                        Colors.red,
                        LocalizationService.translate('where_to', lang),
                        dropoff,
                        () => _searchAddress(isPickup: false),
                        isPickup: false)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          // Info Box
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 15),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppTheme.primaryGold.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildInfoColumn(
                        LocalizationService.translate(
                            'vehicle_type_caps', lang),
                        LocalizationService.translate(
                                vehicleName.toLowerCase().replaceAll(' ', '_'),
                                lang)
                            .toUpperCase()),
                    _buildInfoColumn(
                        LocalizationService.translate('price_caps', lang),
                        "${NumberFormat('#,###').format(fare)} Tsh",
                        isBold: true),
                    _buildInfoColumn(
                        LocalizationService.translate('distance_caps', lang),
                        _distance > 0
                            ? "${_distance.toStringAsFixed(1)} KM"
                            : "-- KM"),
                  ],
                ),
                Divider(height: 25, color: Colors.white.withValues(alpha: 0.1)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet,
                            size: 16, color: AppTheme.primaryGold),
                        const SizedBox(width: 8),
                        Text(
                            LocalizationService.translate('payment_caps', lang),
                            style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 5),
                        Text(
                            _selectedPaymentMethod == "Cash"
                                ? LocalizationService.translate('cash', lang)
                                : _selectedPaymentMethod,
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppTheme.primaryGold,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                    TextButton(
                      onPressed: _showPaymentMethodSelector,
                      child: Text(
                          LocalizationService.translate('change_caps', lang),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGold)),
                    )
                  ],
                ),
                Divider(height: 25, color: Colors.white.withValues(alpha: 0.1)),
                // Guest Ride Toggle
                Theme(
                  data: Theme.of(context).copyWith(
                    unselectedWidgetColor: Colors.white70,
                  ),
                  child: CheckboxListTile(
                    title: Text(
                      LocalizationService.translate('request_for_guest', lang),
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 13),
                    ),
                    value: _isGuestRide,
                    activeColor: AppTheme.primaryGold,
                    checkColor: Colors.black,
                    onChanged: (val) {
                      setState(() {
                        _isGuestRide = val ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                if (_isGuestRide) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _guestNameController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: LocalizationService.translate('guest_name', lang),
                            hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _guestPhoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: LocalizationService.translate('guest_phone', lang),
                            hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildNavBtn(
                      LocalizationService.translate('change_vehicle', lang),
                      Colors.black87,
                      () => Navigator.pop(context)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: _buildNavBtn(
                      LocalizationService.translate('cancel', lang),
                      const Color(0xFFA00000),
                      () => Navigator.pop(context)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 3,
                  child: _buildNavBtn(
                      LocalizationService.translate('confirm_ride', lang),
                      AppTheme.primaryGold,
                      _isRequesting ? null : _handleRequest,
                      isPrimary: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, {bool isBold = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54)),
          Text(value,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
                  color: isBold ? AppTheme.primaryGold : Colors.white)),
        ],
      ),
    );
  }

  void _showPaymentMethodSelector() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(LocalizationService.translate('payment_method_caps', lang),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.money),
              title: Text(LocalizationService.translate('cash_full', lang)),
              onTap: () {
                setState(() => _selectedPaymentMethod = "Cash");
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.green),
              title: Text(
                  LocalizationService.translate('mobile_money_full', lang)),
              onTap: () {
                Navigator.pop(context);
                _showMobileMoneyOptions();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocTile(IconData icon, Color color, String label, String value,
      VoidCallback onTap,
      {bool isPickup = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70)),
                  ),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ],
              ),
            ),
            // Grouping icons to prevent overflow
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSmallActionBtn(
                  icon: Icons.location_searching,
                  onPressed: () {
                    if (!_isMapReady) return;
                    try {
                      final center = _mapController.camera.center;
                      setState(() {
                        if (isPickup) {
                          _pickupLatLng = center;
                        } else {
                          _dropoffLatLng = center;
                        }
                      });
                      _getPlaceName(center.latitude, center.longitude,
                          isPickup: isPickup);
                      _loadRoute();
                    } catch (e) {
                      debugPrint("Map camera access failed: $e");
                    }
                  },
                ),
                _buildSmallActionBtn(
                  icon: Icons.mic,
                  onPressed: () => _startVoiceSearch(isPickup: isPickup),
                ),
                _buildSmallActionBtn(
                  icon: Icons.camera_alt,
                  onPressed: () => _triggerVisualAI(isPickup: isPickup),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallActionBtn(
      {required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: 16, color: AppTheme.primaryGold),
      ),
    );
  }

  Widget _buildNavBtn(String text, Color color, VoidCallback? onTap,
      {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: isPrimary
            ? Shimmer.fromColors(
                baseColor: Colors.black,
                highlightColor: Colors.white.withOpacity(0.5),
                period: const Duration(seconds: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
      ),
    );
  }

  void _listenToIncomingCalls() {
    final rideId = _rideProvider?.currentRide?.id;
    if (rideId != null) {
      if (_callSubscription != null) return;

      _callSubscription = CallService.listenToCall(rideId).listen((snapshot) {
        if (!snapshot.exists || !mounted) return;
        final data = snapshot.data() as Map<String, dynamic>;
        final activeCall = data['activeCall'];

        if (activeCall != null && activeCall['status'] == 'ringing') {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          // Only show dialog if we are NOT the caller
          if (activeCall['callerId'] != auth.currentUser?.id) {
            _showIncomingCallDialog(
              rideId,
              activeCall['callerName'] ?? 'Driver',
            );
          }
        }
      });
    } else {
      _callSubscription?.cancel();
      _callSubscription = null;
    }
  }

  void _showIncomingCallDialog(String rideId, String callerName) {
    if (ModalRoute.of(context)?.isCurrent == false) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.primaryGold,
              child: Icon(Icons.person, size: 50, color: Colors.black),
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "Incoming In-App Call...",
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
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
}

class AddressSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF1E1E1E),
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white38),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => Container();

  @override
  Widget buildSuggestions(BuildContext context) {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    if (query.length < 2) {
      return Center(
          child: Text(LocalizationService.translate('search_location', lang),
              style: const TextStyle(color: Colors.white70)));
    }
    return Container(
      color: const Color(0xFF1E1E1E),
      child: FutureBuilder<List<dynamic>>(
        future: _fetchSuggestions(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text("No locations found",
                    style: TextStyle(color: Colors.white54)));
          }
          return ListView.separated(
            itemCount: snapshot.data!.length,
            separatorBuilder: (context, index) =>
                const Divider(color: Colors.white10),
            itemBuilder: (context, index) {
              final item = snapshot.data![index];
              final props = item['properties'];
              final name = props['name'] ?? "Unknown";
              final city = props['city'] ?? props['state'] ?? "";
              final street = props['street'] ?? "";

              return ListTile(
                leading: const Icon(Icons.location_on,
                    color: AppTheme.primaryGold, size: 20),
                title: Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("$street $city".trim(),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () => close(context, {
                  'name': name,
                  'lat': item['geometry']['coordinates'][1],
                  'lng': item['geometry']['coordinates'][0],
                }),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<dynamic>> _fetchSuggestions(String text) async {
    if (text.isEmpty) return [];
    try {
      // Tunaboresha bias kuelekea Tanzania (Arusha/Dar)
      // Tunatumia Photon API ambayo ni rafiki kwa Autocomplete
      final String url = 'https://photon.komoot.io/api/?q=${Uri.encodeComponent(text)}&limit=15&lat=-3.37&lon=36.68&location_bias_scale=0.5';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'STA_Ride_App_V1'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['features'] ?? [];
      }
    } catch (e) {
      debugPrint("Search suggestions error: $e");
    }
    return [];
  }
}
