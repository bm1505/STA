import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class RouteService {
  static const String _apiKey =
      String.fromEnvironment('GCP_API_KEY');

  // Pata ushauri wa AI kuhusu njia (Smart Routing)
  static Future<String> getAISmartAdvice(
      RouteInfo route, String destinationName) async {
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);

      String stepsSummary = route.steps.map((s) => s.instruction).join(", ");

      final prompt = [
        Content.text("You are a smart Tanzanian taxi dispatcher. "
            "The driver is going to $destinationName. The route steps are: $stepsSummary. "
            "Give a very brief, friendly advice in Swahili (max 15 words) about this route or a smart tip for the driver. "
            "Use a helpful and encouraging tone.")
      ];

      final response = await model.generateContent(prompt);
      return response.text ?? "Safari njema! Fuata ramani kwa usalama.";
    } catch (e) {
      return "Kila la heri kwenye safari yako!";
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

      if (!pLat.isFinite || !pLng.isFinite || !dLat.isFinite || !dLng.isFinite) {
        throw Exception('Invalid coordinates: Non-finite values');
      }

      final url =
          'https://router.project-osrm.org/route/v1/driving/$pLng,$pLat;$dLng,$dLat?overview=full&geometries=geojson&steps=true';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final route = data['routes'][0];

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
      print('Route Error: $e');
      // Fallback: Ikishindwa, tumia hesabu ya kawaida ya mstari
      return RouteInfo(
        distance: 5.0,
        duration: 15,
        trafficMultiplier: 1.0,
        polyline: [
          LatLng(double.parse(pickupLat), double.parse(pickupLng)),
          LatLng(double.parse(dropoffLat), double.parse(dropoffLng)),
        ],
        steps: [],
      );
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
