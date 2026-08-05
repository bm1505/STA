import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sta/providers/driver_ride_provider.dart';
import 'package:sta/models/user.dart';

void main() {
  group('DriverRideProvider Fare Calculation Logic Tests', () {
    late DriverRideProvider provider;

    setUp(() {
      provider = DriverRideProvider();
    });

    test('Initial fare should be based on currentRideData fare', () {
      provider.acceptRide(
          {
            'rideId': 'ride_001',
            'riderId': 'rider_001',
            'fare': 1500.0,
          },
          UserModel(
            id: 'driver123',
            name: 'Test Driver',
            email: 'test@driver.com',
            phoneNumber: '123456',
            role: UserRole.driver,
            createdAt: DateTime.now(),
          ));

      expect(provider.currentFare, 1500.0);
    });

    test('Fare should increase as distance increases during tripInProgress',
        () {
      provider.acceptRide(
          {
            'rideId': 'ride_001',
            'riderId': 'rider_001',
            'fare': 2000.0,
          },
          UserModel(
            id: 'driver123',
            name: 'Test Driver',
            email: 'test@driver.com',
            phoneNumber: '123456',
            role: UserRole.driver,
            createdAt: DateTime.now(),
          ));

      // 1. MUST set initial location BEFORE starting trip so _lastTripLatLng is set in _startTripCounters
      provider.updateLocation(
          Position(
            latitude: -6.7924,
            longitude: 39.2083,
            timestamp: DateTime.now(),
            accuracy: 1,
            altitude: 1,
            heading: 1,
            speed: 1,
            speedAccuracy: 1,
            altitudeAccuracy: 1,
            headingAccuracy: 1,
          ),
          'driver123',
          false // Offline so it doesn't try to emit
          );

      // 2. Start the trip (this sets _lastTripLatLng = _currentLocation)
      provider.updateRideStatus(DriverRideStatus.tripInProgress);

      // 3. Move 1km away
      provider.updateLocation(
          Position(
            latitude: -6.8014, // Roughly 1km south
            longitude: 39.2083,
            timestamp: DateTime.now(),
            accuracy: 1,
            altitude: 1,
            heading: 1,
            speed: 1,
            speedAccuracy: 1,
            altitudeAccuracy: 1,
            headingAccuracy: 1,
          ),
          'driver123',
          false);

      // distance should be approx 1000 meters
      expect(provider.tripDistance, closeTo(1000.0, 50.0));

      // Expected fare: base (2000) + (1km * 500) = 2500
      expect(provider.currentFare, closeTo(2500.0, 50.0));
    });
  });
}
