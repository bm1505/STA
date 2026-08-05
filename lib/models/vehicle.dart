enum VehicleType {
  motorbike,
  car,
  threeWheeler,
  xl,
  send,
}

class Vehicle {
  final String id;
  final String name;
  final VehicleType type;
  final String icon;
  final double baseFare;
  final double perKmRate;
  final double perMinuteRate;
  final int estimatedArrival;
  final String color;

  Vehicle({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.baseFare,
    required this.perKmRate,
    required this.perMinuteRate,
    required this.estimatedArrival,
    required this.color,
  });

  double calculateFare(double distanceKm, int durationMinutes) {
    double fare =
        baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinuteRate);

    // Round to the nearest 100 TZS for cash payment convenience
    // Example: 2,172 -> 2,200 | 3,840 -> 3,800
    return (fare / 100).round() * 100.0;
  }

  static List<Vehicle> getAvailableVehicles() {
    return [
      Vehicle(
        id: '1',
        name: 'Bodaboda',
        type: VehicleType.motorbike,
        icon: '🏍️',
        baseFare: 1500,
        perKmRate: 500,
        perMinuteRate: 50,
        estimatedArrival: 2,
        color: '#FF6B00',
      ),
      Vehicle(
        id: '2',
        name: 'Bajaji',
        type: VehicleType.threeWheeler,
        icon: '🛺',
        baseFare: 2500,
        perKmRate: 700,
        perMinuteRate: 80,
        estimatedArrival: 3,
        color: '#FF9800',
      ),
      Vehicle(
        id: '3',
        name: 'Car',
        type: VehicleType.car,
        icon: '🚗',
        baseFare: 3500,
        perKmRate: 1000,
        perMinuteRate: 120,
        estimatedArrival: 4,
        color: '#2196F3',
      ),
      Vehicle(
        id: '4',
        name: 'XL',
        type: VehicleType.xl,
        icon: '🚐',
        baseFare: 5000,
        perKmRate: 1500,
        perMinuteRate: 180,
        estimatedArrival: 6,
        color: '#4CAF50',
      ),
      Vehicle(
        id: '5',
        name: 'STA Send',
        type: VehicleType.send,
        icon: '📦',
        baseFare: 2000,
        perKmRate: 600,
        perMinuteRate: 60,
        estimatedArrival: 2,
        color: '#9C27B0',
      ),
    ];
  }

  static String getStandardizedType(String name) {
    // Map various inputs to a single standard set used in Firestore
    final lowerName = name.toLowerCase();
    if (lowerName.contains('bodaboda') || lowerName.contains('motorbike')) {
      return 'Bodaboda';
    }
    if (lowerName.contains('bajaji') || lowerName.contains('three')) {
      return 'Bajaji';
    }
    if (lowerName.contains('xl')) return 'XL';
    if (lowerName.contains('send')) return 'STA Send';
    return 'Car';
  }
}
