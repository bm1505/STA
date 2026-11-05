enum UserRole { rider, driver, admin, it, support }

enum VerificationStatus { pending, verified, rejected }

class UserModel {
  final String id;
  final String email;
  final String name;
  final String phoneNumber;
  final UserRole role;
  final String? profileImageUrl;
  final double rating;
  final int totalRides;
  final bool isVerified;
  final VerificationStatus verificationStatus;
  final String? rejectionReason;
  final bool hasAcceptedTerms;
  final DateTime createdAt;
  final String? dob;
  final String? gender;
  final String? username;
  final String? carModel;
  final String? carPlate;
  final String? carColor;
  final String? carYear;
  final String? vehicleType;
  final String? licenseUrl;
  final String? insuranceUrl;
  final String? nationalIdUrl;
  final String? vehiclePhotoUrl;
  final String? region;
  final String? city;
  final DateTime? lastPhotoUpdate;
  final String? homeAddress;
  final String? workAddress;
  final String? fcmToken;
  final String? driverLevel;
  final double? earnings;
  final String? department;
  final String? payoutNumber;
  final String? payoutMethod;
  final String? profileEditStatus; // none, requested, allowed, submitted
  final bool isOnline;
  final Map<String, dynamic>? pendingUpdates;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.phoneNumber,
    required this.role,
    this.profileImageUrl,
    this.rating = 0.0,
    this.totalRides = 0,
    this.isVerified = false,
    this.verificationStatus = VerificationStatus.pending,
    this.rejectionReason,
    this.hasAcceptedTerms = false,
    required this.createdAt,
    this.dob,
    this.gender,
    this.username,
    this.carModel,
    this.carPlate,
    this.carColor,
    this.carYear,
    this.vehicleType,
    this.licenseUrl,
    this.insuranceUrl,
    this.nationalIdUrl,
    this.vehiclePhotoUrl,
    this.region,
    this.city,
    this.lastPhotoUpdate,
    this.homeAddress,
    this.workAddress,
    this.fcmToken,
    this.driverLevel,
    this.earnings,
    this.department,
    this.payoutNumber,
    this.payoutMethod,
    this.profileEditStatus = 'none',
    this.isOnline = false,
    this.pendingUpdates,
  });

  String get fullName => name;

  bool get isProfileComplete {
    if (role == UserRole.driver) {
      return phoneNumber.isNotEmpty &&
          carModel != null &&
          carPlate != null &&
          licenseUrl != null;
    }
    return phoneNumber.isNotEmpty;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    UserRole role = UserRole.rider;
    String r = (json['role'] ?? 'rider').toString().toLowerCase();
    if (r.contains('admin')) {
      role = UserRole.admin;
    } else if (r.contains('it')) {
      role = UserRole.it;
    } else if (r.contains('support')) {
      role = UserRole.support;
    } else if (r.contains('driver')) {
      role = UserRole.driver;
    }

    VerificationStatus vStatus = VerificationStatus.pending;
    String s =
        (json['verificationStatus'] ?? 'pending').toString().toLowerCase();
    if (s == 'verified') {
      vStatus = VerificationStatus.verified;
    } else if (s == 'rejected') {
      vStatus = VerificationStatus.rejected;
    }

    // Robust DateTime parsing helper
    DateTime parseDate(dynamic value, {bool required = false}) {
      if (value == null) return required ? DateTime.now() : DateTime.now();
      if (value is String) {
        return DateTime.tryParse(value) ?? (required ? DateTime.now() : DateTime.now());
      }
      return required ? DateTime.now() : DateTime.now();
    }

    DateTime? parseDateNullable(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // Robust Phone normalization
    String normalizePhone(dynamic val) {
      if (val == null) return '';
      String str = val.toString().trim();
      if (str.toLowerCase() == 'null' || str.isEmpty) return '';
      return str;
    }

    String phone = normalizePhone(json['phoneNumber']);
    if (phone.isEmpty) phone = normalizePhone(json['phone']);
    if (phone.isEmpty) phone = normalizePhone(json['phone_number']);

    // Robust Gender normalization (Male/Female)
    String? normalizeGender(dynamic val) {
      if (val == null) return null;
      String str = val.toString().trim().toLowerCase();
      if (str == 'null' || str.isEmpty) return null;
      if (str.startsWith('m')) return 'Male';
      if (str.startsWith('f')) return 'Female';
      return null;
    }

    String? gender = normalizeGender(json['gender']);
    String? dob = json['dob']?.toString();

    // Robust Boolean parsing helper
    bool parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is num) return value != 0;
      return false;
    }

    return UserModel(
      id: json['id']?.toString() ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      phoneNumber: phone,
      role: role,
      isVerified: parseBool(json['isVerified']),
      verificationStatus: vStatus,
      rejectionReason: json['rejectionReason'],
      profileImageUrl: json['profileImageUrl'],
      dob: dob,
      gender: gender,
      username: json['username'],
      carModel: json['carModel'],
      carPlate: json['carPlate'],
      carColor: json['carColor'],
      carYear: json['carYear']?.toString(),
      vehicleType: json['vehicleType'],
      licenseUrl: json['licenseUrl'],
      insuranceUrl: json['insuranceUrl'],
      nationalIdUrl: json['nationalIdUrl'],
      vehiclePhotoUrl: json['vehiclePhotoUrl'],
      region: json['region'],
      city: json['city'],
      lastPhotoUpdate: parseDateNullable(json['lastPhotoUpdate']),
      homeAddress: json['homeAddress'],
      workAddress: json['workAddress'],
      fcmToken: json['fcmToken'],
      driverLevel: json['driverLevel'],
      earnings: (json['earnings'] as num?)?.toDouble(),
      department: json['department'],
      payoutNumber: json['payoutNumber'],
      payoutMethod: json['payoutMethod'],
      profileEditStatus: json['profileEditStatus'] ?? 'none',
      isOnline: parseBool(json['isOnline']),
      pendingUpdates: json['pendingUpdates'],
      createdAt: parseDate(json['createdAt'], required: true),
    );
  }


  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'email': email,
      'name': name,
      'phoneNumber': phoneNumber,
      'phone': phoneNumber, // Added for backward compatibility with your DB
      'role': role.toString().split('.').last,
      'isVerified': isVerified,
      'isOnline': isOnline,
      'verificationStatus': verificationStatus.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'profileEditStatus': profileEditStatus,
    };

    if (pendingUpdates != null) data['pendingUpdates'] = pendingUpdates;
    if (dob != null) data['dob'] = dob;
    if (gender != null) data['gender'] = gender;
    if (profileImageUrl != null) data['profileImageUrl'] = profileImageUrl;
    if (carModel != null) data['carModel'] = carModel;
    if (carPlate != null) data['carPlate'] = carPlate;
    if (carColor != null) data['carColor'] = carColor;
    if (carYear != null) data['carYear'] = carYear;
    if (vehicleType != null) data['vehicleType'] = vehicleType;
    if (licenseUrl != null) data['licenseUrl'] = licenseUrl;
    if (insuranceUrl != null) data['insuranceUrl'] = insuranceUrl;
    if (nationalIdUrl != null) data['nationalIdUrl'] = nationalIdUrl;
    if (vehiclePhotoUrl != null) data['vehiclePhotoUrl'] = vehiclePhotoUrl;
    if (region != null) data['region'] = region;
    if (city != null) data['city'] = city;
    if (lastPhotoUpdate != null) {
      data['lastPhotoUpdate'] = lastPhotoUpdate!.toIso8601String();
    }
    if (homeAddress != null) data['homeAddress'] = homeAddress;
    if (workAddress != null) data['workAddress'] = workAddress;
    if (fcmToken != null) data['fcmToken'] = fcmToken;
    if (driverLevel != null) data['driverLevel'] = driverLevel;
    if (earnings != null) data['earnings'] = earnings;
    if (department != null) data['department'] = department;
    if (payoutNumber != null) data['payoutNumber'] = payoutNumber;
    if (payoutMethod != null) data['payoutMethod'] = payoutMethod;

    return data;
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    UserRole? role,
    String? dob,
    String? gender,
    String? profileImageUrl,
    String? carModel,
    String? carPlate,
    String? carColor,
    String? carYear,
    String? vehicleType,
    String? licenseUrl,
    String? insuranceUrl,
    String? nationalIdUrl,
    String? vehiclePhotoUrl,
    String? region,
    String? city,
    bool? isVerified,
    bool? isOnline,
    VerificationStatus? verificationStatus,
    DateTime? lastPhotoUpdate,
    String? homeAddress,
    String? workAddress,
    String? fcmToken,
    String? driverLevel,
    double? earnings,
    String? department,
    String? payoutNumber,
    String? payoutMethod,
    bool? hasAcceptedTerms,
    String? profileEditStatus,
    Map<String, dynamic>? pendingUpdates,
  }) {
    return UserModel(
      id: id,
      email: email ?? this.email,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      carModel: carModel ?? this.carModel,
      carPlate: carPlate ?? this.carPlate,
      carColor: carColor ?? this.carColor,
      carYear: carYear ?? this.carYear,
      vehicleType: vehicleType ?? this.vehicleType,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      insuranceUrl: insuranceUrl ?? this.insuranceUrl,
      nationalIdUrl: nationalIdUrl ?? this.nationalIdUrl,
      vehiclePhotoUrl: vehiclePhotoUrl ?? this.vehiclePhotoUrl,
      region: region ?? this.region,
      city: city ?? this.city,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      lastPhotoUpdate: lastPhotoUpdate ?? this.lastPhotoUpdate,
      homeAddress: homeAddress ?? this.homeAddress,
      workAddress: workAddress ?? this.workAddress,
      fcmToken: fcmToken ?? this.fcmToken,
      driverLevel: driverLevel ?? this.driverLevel,
      earnings: earnings ?? this.earnings,
      department: department ?? this.department,
      payoutNumber: payoutNumber ?? this.payoutNumber,
      payoutMethod: payoutMethod ?? this.payoutMethod,
      hasAcceptedTerms: hasAcceptedTerms ?? this.hasAcceptedTerms,
      profileEditStatus: profileEditStatus ?? this.profileEditStatus,
      pendingUpdates: pendingUpdates ?? this.pendingUpdates,
      createdAt: createdAt,
    );
  }
}
