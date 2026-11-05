import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteService {
  // AI advice is generated server-side; provider credentials never ship in the app.
  static Future<String> getAISmartAdvice(
      RouteInfo route, String destinationName) async {
    try {
      final steps = route.steps
          .map((step) => step.instruction.trim())
          .where((instruction) => instruction.isNotEmpty)
          .take(30)
          .toList();
      if (steps.isEmpty) {
        return "Fuata maelekezo ya ramani na endesha kwa usalama.";
      }

      final response = await Supabase.instance.client.functions.invoke(
        'route-advice',
        body: {
          'destination': destinationName,
          'steps': steps,
        },
      );

      if (response.status != 200 || response.data is! Map) {
        return "Fuata ramani na zingatia alama za barabarani.";
      }
      final advice = (response.data['advice'] as String?)?.trim();
      return advice == null || advice.isEmpty
          ? "Fuata ramani na zingatia alama za barabarani."
          : advice;
    } catch (e) {
      debugPrint('Smart route advice unavailable: $e');
      return "Fuata ramani na zingatia alama za barabarani.";
    }
  }

  // Pata njia halisi kutoka OSRM (Bure na Sahihi)
  static Future<RouteInfo> getRouteInfo(
    String pickupLat,
    String pickupLng,
    String dropoffLat,
    String dropoffLng,
  ) async {
    try {
      final pLat = double.tryParse(pickupLat) ?? 0.0;
      final pLng = double.tryParse(pickupLng) ?? 0.0;
      final dLat = double.tryParse(dropoffLat) ?? 0.0;
      final dLng = double.tryParse(dropoffLng) ?? 0.0;

      if (!pLat.isFinite || !pLng.isFinite || !dLat.isFinite || !dLng.isFinite ||
          pLat < -90 || pLat > 90 || dLat < -90 || dLat > 90 ||
          pLng < -180 || pLng > 180 || dLng < -180 || dLng > 180) {
        throw ArgumentError('Invalid pickup or destination coordinates.');
      }

      final url =
          'https://router.project-osrm.org/route/v1/driving/$pLng,$pLat;$dLng,$dLat?overview=full&geometries=geojson&steps=true';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'];
        if (data['code'] != 'Ok' || routes is! List || routes.isEmpty) {
          throw StateError('No valid route was returned by the routing service.');
        }
        final route = routes.first as Map<String, dynamic>;

        final distanceMeter = route['distance'].toDouble();
        final durationSeconds = route['duration'].toDouble();

        // Geometries inatoa list ya Coordinates [lng, lat]
        final List<dynamic> coordinates = route['geometry']['coordinates'];
        final List<LatLng> polylinePoints = coordinates
            .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();

        // Parse steps for turn-by-turn instructions
        final List<RouteStep> steps = [];
        if (route['legs'] != null && route['legs'].isNotEmpty) {
          final legs = route['legs'][0];
          if (legs['steps'] != null) {
            for (var step in legs['steps']) {
              steps.add(RouteStep(
                instruction: step['maneuver']['instruction'] ?? '',
                distance: (step['distance'] as num).toDouble(),
                location: LatLng(
                  step['maneuver']['location'][1].toDouble(),
                  step['maneuver']['location'][0].toDouble(),
                ),
              ));
            }
          }
        }

        return RouteInfo(
          distance: distanceMeter / 1000, // Badili kwenda KM
          duration: (durationSeconds / 60).round(), // Badili kwenda Minutes
          trafficMultiplier: 1.0,
          polyline: polylinePoints,
          steps: steps,
        );
      } else {
        throw Exception('Failed to load route');
      }
    } catch (e) {
      // Never fabricate distance, duration, or a straight-line route: those
      // values can flow into fare estimates and mislead riders and drivers.
      debugPrint('Route calculation failed: $e');
      rethrow;
    }
  }
}

class RouteStep {
  final String instruction;
  final double distance;
  final LatLng location;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.location,
  });
}

class RouteInfo {
  final double distance;
  final int duration;
  final double trafficMultiplier;
  final List<LatLng> polyline;
  final List<RouteStep> steps;

  RouteInfo({
    required this.distance,
    required this.duration,
    required this.trafficMultiplier,
    required this.polyline,
    this.steps = const [],
  });

  String get formattedDistance {
    if (distance < 1) {
      return '${(distance * 1000).round()} m';
    }
    return '${distance.toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    if (duration < 60) {
      return '$duration min';
    }
    int hours = duration ~/ 60;
    int minutes = duration % 60;
    return '$hours hr $minutes min';
  }
}
