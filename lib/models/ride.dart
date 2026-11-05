
class Ride {
  final String id;
  final String passengerId;
  final String? driverId;
  final Location pickupLocation;
  final Location dropoffLocation;
  final double fare;
  final double distance;
  final int duration;
  final String? vehicleType;
  final RideStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? cancellationReason;
  final PaymentMethod paymentMethod;
  final String? paymentStatus;
  final bool isGuestRide;
  final String? guestName;
  final String? guestPhone;

  Ride({
    required this.id,
    required this.passengerId,
    this.driverId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.fare,
    required this.distance,
    required this.duration,
    this.vehicleType,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.cancellationReason,
    required this.paymentMethod,
    this.paymentStatus,
    this.isGuestRide = false,
    this.guestName,
    this.guestPhone,
  });

  Ride copyWith({
    String? id,
    String? driverId,
    RideStatus? status,
    double? fare,
    double? distance,
    int? duration,
    String? vehicleType,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? cancellationReason,
    String? paymentStatus,
    bool? isGuestRide,
    String? guestName,
    String? guestPhone,
  }) {
    return Ride(
      id: id ?? this.id,
      passengerId: passengerId,
      driverId: driverId ?? this.driverId,
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      fare: fare ?? this.fare,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      vehicleType: vehicleType ?? this.vehicleType,
      status: status ?? this.status,
      createdAt: createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      isGuestRide: isGuestRide ?? this.isGuestRide,
      guestName: guestName ?? this.guestName,
      guestPhone: guestPhone ?? this.guestPhone,
    );
  }

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'] ?? '',
      passengerId: json['passengerId'] ?? '',
      driverId: json['driverId'],
      pickupLocation: Location.fromJson(json['pickupLocation'] ?? {}),
      dropoffLocation: Location.fromJson(json['dropoffLocation'] ?? {}),
      fare: (json['fare'] ?? 0).toDouble(),
      distance: (json['distance'] ?? 0).toDouble(),
      duration: json['duration'] ?? 0,
      vehicleType: json['vehicleType'],
      status: RideStatus.values.firstWhere(
        (e) =>
            e.name == json['status'] ||
            e.toString() == json['status'] ||
            e.toString().split('.').last == json['status'],
        orElse: () => RideStatus.requesting,
      ),
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'])
              : DateTime.parse(json['createdAt'].toString()))
          : DateTime.now(),
      acceptedAt: json['acceptedAt'] != null
          ? (json['acceptedAt'] is String
              ? DateTime.parse(json['acceptedAt'])
              : DateTime.parse(json['acceptedAt'].toString()))
          : null,
      startedAt: json['startedAt'] != null
          ? (json['startedAt'] is String
              ? DateTime.parse(json['startedAt'])
              : DateTime.parse(json['startedAt'].toString()))
          : null,
      completedAt: json['completedAt'] != null
          ? (json['completedAt'] is String
              ? DateTime.parse(json['completedAt'])
              : DateTime.parse(json['completedAt'].toString()))
          : null,
      cancellationReason: json['cancellationReason'],
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) =>
            e.name == json['paymentMethod'] ||
            e.toString() == json['paymentMethod'],
        orElse: () => PaymentMethod.cash,
      ),
      paymentStatus: json['paymentStatus'],
      isGuestRide: json['isGuestRide'] ?? false,
      guestName: json['guestName'],
      guestPhone: json['guestPhone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'passengerId': passengerId,
      'driverId': driverId,
      'pickupLocation': pickupLocation.toJson(),
      'dropoffLocation': dropoffLocation.toJson(),
      'fare': fare,
      'distance': distance,
      'duration': duration,
      'vehicleType': vehicleType,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'cancellationReason': cancellationReason,
      'paymentMethod': paymentMethod.name,
      'paymentStatus': paymentStatus,
      'isGuestRide': isGuestRide,
      'guestName': guestName,
      'guestPhone': guestPhone,
    };
  }

}

class Location {
  final double latitude;
  final double longitude;
  final String address;

  Location({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      address: json['address'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      };
}

enum RideStatus {
  requesting,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelled,
}

enum PaymentMethod {
  cash,
  card,
  wallet,
}
