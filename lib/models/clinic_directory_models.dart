class ClinicRegionOption {
  const ClinicRegionOption({
    required this.name,
    required this.hasProvinces,
    required this.hasRegionLevelLocalities,
    required this.hasSpecialAreas,
  });

  final String name;
  final bool hasProvinces;
  final bool hasRegionLevelLocalities;
  final bool hasSpecialAreas;

  factory ClinicRegionOption.fromJson(Map<String, dynamic> json) {
    return ClinicRegionOption(
      name: json['name']?.toString() ?? '',
      hasProvinces: json['hasProvinces'] == true,
      hasRegionLevelLocalities:
          json['hasRegionLevelLocalities'] == true,
      hasSpecialAreas: json['hasSpecialAreas'] == true,
    );
  }
}

class ClinicAreaOption {
  const ClinicAreaOption({
    required this.name,
    required this.type,
    this.localityType,
  });

  final String name;
  final String type;
  final String? localityType;

  factory ClinicAreaOption.fromJson(
    Map<String, dynamic> json, {
    required String defaultType,
  }) {
    return ClinicAreaOption(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? defaultType,
      localityType: json['localityType']?.toString(),
    );
  }
}

class ClinicLocalityOption {
  const ClinicLocalityOption({
    required this.name,
    required this.type,
  });

  final String name;
  final String type;

  factory ClinicLocalityOption.fromJson(Map<String, dynamic> json) {
    return ClinicLocalityOption(
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'locality',
    );
  }
}

class AccreditedClinic {
  const AccreditedClinic({
    required this.facilityNumber,
    required this.name,
    required this.facilityType,
    required this.region,
    required this.province,
    required this.cityMunicipality,
    required this.streetAddress,
    required this.barangay,
    required this.telephone,
    required this.email,
    required this.latitude,
    required this.longitude,
    required this.coordinateStatus,
    required this.exactClinicLocationVerified,
    required this.distanceKm,
    required this.accreditationExpiry,
    required this.googleMapsSearchUrl,
    required this.googleMapsDirectionsUrl,
  });

  final int? facilityNumber;
  final String name;
  final String facilityType;
  final String region;
  final String? province;
  final String cityMunicipality;
  final String? streetAddress;
  final String? barangay;
  final List<String> telephone;
  final List<String> email;
  final double? latitude;
  final double? longitude;
  final String coordinateStatus;
  final bool exactClinicLocationVerified;
  final double? distanceKm;
  final String? accreditationExpiry;
  final String googleMapsSearchUrl;
  final String googleMapsDirectionsUrl;

  factory AccreditedClinic.fromJson(Map<String, dynamic> json) {
    return AccreditedClinic(
      facilityNumber: _toInt(json['facilityNumber']),
      name: json['name']?.toString() ?? 'Unnamed clinic',
      facilityType:
          json['facilityType']?.toString() ?? 'healthcare_facility',
      region: json['region']?.toString() ?? '',
      province: json['province']?.toString(),
      cityMunicipality:
          json['cityMunicipality']?.toString() ?? '',
      streetAddress: json['streetAddress']?.toString(),
      barangay: json['barangay']?.toString(),
      telephone: _toStringList(json['telephone']),
      email: _toStringList(json['email']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      coordinateStatus:
          json['coordinateStatus']?.toString() ?? 'unresolved',
      exactClinicLocationVerified:
          json['exactClinicLocationVerified'] == true,
      distanceKm: _toDouble(json['distanceKm']),
      accreditationExpiry:
          json['accreditationExpiry']?.toString(),
      googleMapsSearchUrl:
          json['googleMapsSearchUrl']?.toString() ?? '',
      googleMapsDirectionsUrl:
          json['googleMapsDirectionsUrl']?.toString() ?? '',
    );
  }

  String get displayAddress {
    return [
      streetAddress,
      barangay,
      cityMunicipality,
      province,
    ]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(', ');
  }

  String get facilityTypeLabel {
    switch (facilityType) {
      case 'hospital':
        return 'Hospital';
      case 'freestanding_dialysis_clinic':
        return 'Freestanding dialysis clinic';
      default:
        return 'Healthcare facility';
    }
  }

  bool get hasVerifiedCoordinates {
    const verifiedStatuses = {
      'exact_clinic_pin',
      'exact_building',
      'manually_verified',
      'verified',
    };

    final lat = latitude;
    final lng = longitude;

    return lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        exactClinicLocationVerified &&
        verifiedStatuses.contains(coordinateStatus);
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
    }

    if (value != null && value.toString().trim().isNotEmpty) {
      return [value.toString()];
    }

    return const [];
  }
}

class ClinicMatchResult {
  const ClinicMatchResult({
    required this.matchLevel,
    required this.message,
    required this.isActualNearest,
    required this.facilities,
  });

  final String matchLevel;
  final String message;
  final bool isActualNearest;
  final List<AccreditedClinic> facilities;

  factory ClinicMatchResult.fromJson(Map<String, dynamic> json) {
    final facilitiesJson = json['facilities'] as List? ?? const [];

    return ClinicMatchResult(
      matchLevel: json['matchLevel']?.toString() ?? 'none',
      message: json['message']?.toString() ?? '',
      isActualNearest: json['isActualNearest'] == true,
      facilities: facilitiesJson
          .map(
            (item) => AccreditedClinic.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
