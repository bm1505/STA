import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Region Matching Logic Tests', () {
    test('Arusha matching should be exact', () {
      String driverRegion = "Arusha";
      String pickupRegion = "Arusha";

      expect(driverRegion == pickupRegion, isTrue);
    });

    test('Arusha matching should fail with mismatching region', () {
      String driverRegion = "Arusha";
      String pickupRegion = "Dar es Salaam";

      expect(driverRegion == pickupRegion, isFalse);
    });

    test('Case sensitivity check (Firestore is case-sensitive)', () {
      String driverRegion = "Arusha";
      String pickupRegion = "arusha";

      // If we use .where('region', isEqualTo: region), it MUST match exactly
      expect(driverRegion == pickupRegion, isFalse);
    });

    test('Simulate Komoot response mapping for Arusha', () {
      // Mocking the logic found in home_screen.dart
      final mockProps = {'state': 'Arusha Region', 'region': 'Arusha'};

      String? state = mockProps['state'] ?? mockProps['region'];
      // If Komoot returns "Arusha Region" but driver registered as "Arusha", matching fails
      expect(state == "Arusha", isFalse);
      expect(state!.contains("Arusha"), isTrue);
    });
  });
}
