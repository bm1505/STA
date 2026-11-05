import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteService {
  static Future<String> getAISmartAdvice(RouteInfo route, String destinationName) async {
    try {
      final steps = route.steps
          .map((step) => step.instruction.trim())
          .where((instruction) => instruction.isNotEmpty)
          .take(30)
          .toList();
      if (steps.isEmpty) return "Fuata maelekezo ya ramani na endesha kwa usalama.";
      final response = await Supabase.instance.client.functions.invoke(
        'route-advice',
        body: {'destination': destinationName, 'steps': steps},
      );
      if (response.status != 200 || response.data is! Map) {
        return "Fuata ramani na zingatia alama za barabarani.";
      }
      final advice = (response.data['advice'] as String?)?.trim();
      return advice == null || advice.isEmpty
          ? "Fuata ramani na zingatia alama za barabarani."
          : advice;
    } catch (error) {
      debugPrint('Smart route advice unavailable: $error');
      return "Fuata ramani na zingatia alama za barabarani.";
    }
  }

  static Future<RouteInfo> getRouteInfo(
    String pickupLat,
    String pickupLng,
    String dropoffLat,
    String dropoffLng,
  ) async {
    final pLat = double.tryParse(pickupLat);
    final pLng = double.tryParse(pickupLng);
    final dLat = double.tryParse(dropoffLat);
    final dLng = double.tryParse(dropoffLng);
    if (pLat == null || pLng == null || dLat == null || dLng == null ||
        !pLat.isFinite || !pLng.isFinite || !dLat.isFinite || !dLng.isFinite ||
        pLat < -90 || pLat > 90 || dLat < -90 || dLat > 90 ||
        pLng < -180 || pLng > 180 || dLng < -180 || dLng > 180) {
      throw ArgumentError('Invalid pickup or destination coordinates.');
    }

    // Prefer Google Routes traffic-aware results when the server key is configured.
    // The API key is held only in Supabase Function secrets.
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'traffic-route',
        body: {
          'origin': {'latitude': pLat, 'longitude': pLng},
          'destination': {'latitude': dLat, 'longitude': dLng},
        },
      );
      if (response.status == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final routes = data['routes'];
        if (routes is List && routes.isNotEmpty) {
          final parsed = routes.map((route) => _parseGoogleRoute(
            Map<String, dynamic>.from(route as Map),
          )).toList();
          final primary = parsed.first;
          return RouteInfo(
            distance: primary.distance,
            duration: primary.duration,
            trafficMultiplier: 1.0,
            polyline: primary.polyline,
            steps: primary.steps,
            trafficAware: true,
            trafficDelayMinutes: primary.trafficDelayMinutes,
            alternatives: parsed.skip(1).map((route) => RouteAlternative(
              distance: route.distance,
              duration: route.duration,
              polyline: route.polyline,
              trafficDelayMinutes: route.trafficDelayMinutes,
            )).toList(),
          );
        }
      }
    } catch (error) {
      debugPrint('Traffic-aware routing unavailable; trying OSRM: $error');
    }

    return _getOsrmRoute(pLat, pLng, dLat, dLng);
  }

  static RouteInfo _parseGoogleRoute(Map<String, dynamic> route) {
    final distanceMeters = (route['distanceMeters'] as num?)?.toDouble();
    final durationSeconds = _durationSeconds(route['duration']);
    final staticSeconds = _durationSeconds(route['staticDuration']);
    final geometry = route['polyline']?['geoJsonLinestring']?['coordinates'];
    if (distanceMeters == null || durationSeconds == null ||
        geometry is! List || geometry.isEmpty) {
      throw StateError('Google Routes returned incomplete route data.');
    }
    final points = geometry.map((coordinate) {
      if (coordinate is! List || coordinate.length < 2) {
        throw StateError('Invalid route coordinate.');
      }
      return LatLng(
        (coordinate[1] as num).toDouble(),
        (coordinate[0] as num).toDouble(),
      );
    }).toList();

    final steps = <RouteStep>[];
    for (final leg in (route['legs'] as List? ?? const [])) {
      for (final step in (leg['steps'] as List? ?? const [])) {
        final start = step['startLocation']?['latLng'];
        final lat = (start?['latitude'] as num?)?.toDouble();
        final lng = (start?['longitude'] as num?)?.toDouble();
        final instruction = step['navigationInstruction']?['instructions']?.toString() ?? '';
        if (lat == null || lng == null) continue;
        steps.add(RouteStep(
          instruction: instruction,
          distance: (step['distanceMeters'] as num?)?.toDouble() ?? 0,
          location: LatLng(lat, lng),
        ));
      }
    }

    final trafficDelay = staticSeconds == null
        ? 0
        : ((durationSeconds - staticSeconds).clamp(0, double.infinity) / 60).round();
    return RouteInfo(
      distance: distanceMeters / 1000,
      duration: (durationSeconds / 60).round(),
      trafficMultiplier: 1.0,
      polyline: points,
      steps: steps,
      trafficAware: true,
      trafficDelayMinutes: trafficDelay,
    );
  }

  static double? _durationSeconds(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    final seconds = double.tryParse(raw.endsWith('s') ? raw.substring(0, raw.length - 1) : raw);
    return seconds != null && seconds.isFinite && seconds >= 0 ? seconds : null;
  }

  static Future<RouteInfo> _getOsrmRoute(
    double pLat, double pLng, double dLat, double dLng,
  ) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$pLng,$pLat;$dLng,$dLat?overview=full&geometries=geojson&steps=true&alternatives=true',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Routing service returned HTTP ${response.statusCode}.');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final routes = data['routes'];
    if (data['code'] != 'Ok' || routes is! List || routes.isEmpty) {
      throw StateError('No valid route was returned by the routing service.');
    }
    final parsed = routes.map((route) => _parseOsrmRoute(
      Map<String, dynamic>.from(route as Map),
    )).toList();
    final primary = parsed.first;
    return RouteInfo(
      distance: primary.distance,
      duration: primary.duration,
      trafficMultiplier: 1.0,
      polyline: primary.polyline,
      steps: primary.steps,
      trafficAware: false,
      alternatives: parsed.skip(1).map((route) => RouteAlternative(
        distance: route.distance,
        duration: route.duration,
        polyline: route.polyline,
      )).toList(),
    );
  }

  static RouteInfo _parseOsrmRoute(Map<String, dynamic> route) {
    final distance = (route['distance'] as num?)?.toDouble();
    final duration = (route['duration'] as num?)?.toDouble();
    final coordinates = route['geometry']?['coordinates'];
    if (distance == null || duration == null || coordinates is! List || coordinates.isEmpty) {
      throw StateError('OSRM returned incomplete route data.');
    }
    final points = coordinates.map((coordinate) =>
      LatLng((coordinate[1] as num).toDouble(), (coordinate[0] as num).toDouble())
    ).toList();
    final steps = <RouteStep>[];
    for (final leg in (route['legs'] as List? ?? const [])) {
      for (final step in (leg['steps'] as List? ?? const [])) {
        final maneuver = step['maneuver'] as Map? ?? const {};
        final location = maneuver['location'] as List?;
        if (location == null || location.length < 2) continue;
        final instruction = _osrmInstruction(
          maneuver['type']?.toString() ?? '',
          maneuver['modifier']?.toString() ?? '',
          step['name']?.toString() ?? '',
        );
        steps.add(RouteStep(
          instruction: instruction,
          distance: (step['distance'] as num?)?.toDouble() ?? 0,
          location: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
        ));
      }
    }
    return RouteInfo(
      distance: distance / 1000,
      duration: (duration / 60).round(),
      trafficMultiplier: 1.0,
      polyline: points,
      steps: steps,
      trafficAware: false,
    );
  }

  static String _osrmInstruction(String type, String modifier, String road) {
    final direction = modifier.isEmpty ? '' : ' $modifier';
    final street = road.isEmpty ? '' : ' onto $road';
    switch (type) {
      case 'depart': return road.isEmpty ? 'Start your journey' : 'Start on $road';
      case 'arrive': return 'You have arrived at your destination';
      case 'turn': return 'Turn$direction$street';
      case 'continue': return 'Continue$direction$street';
      case 'new name': return road.isEmpty ? 'Continue' : 'Continue onto $road';
      case 'merge': return 'Merge$direction$street';
      case 'roundabout': return 'Enter the roundabout$street';
      case 'rotary': return 'Enter the rotary$street';
      case 'fork': return 'Keep$direction$street';
      case 'end of road': return 'At the end of the road, turn$direction$street';
      default: return road.isEmpty ? 'Continue along the route' : 'Continue on $road';
    }
  }
}

class RouteStep {
  final String instruction;
  final double distance;
  final LatLng location;
  RouteStep({required this.instruction, required this.distance, required this.location});
}

class RouteAlternative {
  final double distance;
  final int duration;
  final List<LatLng> polyline;
  final int trafficDelayMinutes;
  const RouteAlternative({
    required this.distance,
    required this.duration,
    required this.polyline,
    this.trafficDelayMinutes = 0,
  });
}

class RouteInfo {
  final double distance;
  final int duration;
  final double trafficMultiplier;
  final List<LatLng> polyline;
  final List<RouteStep> steps;
  final bool trafficAware;
  final int trafficDelayMinutes;
  final List<RouteAlternative> alternatives;

  RouteInfo({
    required this.distance,
    required this.duration,
    required this.trafficMultiplier,
    required this.polyline,
    this.steps = const [],
    this.trafficAware = false,
    this.trafficDelayMinutes = 0,
    this.alternatives = const [],
  });

  String get formattedDistance => distance < 1
      ? '${(distance * 1000).round()} m'
      : '${distance.toStringAsFixed(1)} km';

  String get formattedDuration {
    if (duration < 60) return '$duration min';
    final hours = duration ~/ 60;
    final minutes = duration % 60;
    return '$hours hr $minutes min';
  }
}
