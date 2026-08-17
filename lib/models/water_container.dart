class WaterContainer {
  const WaterContainer({
    required this.id,
    required this.name,
    required this.capacityMl,
    required this.capacityValue,
    required this.capacityUnit,
  });

  static const double millilitersPerUsFluidOunce = 29.5735295625;

  final String id;
  final String name;

  // Canonical value used for water totals.
  final double capacityMl;

  // Original amount entered by the user.
  final double capacityValue;

  // Either "ml" or "fl_oz".
  final String capacityUnit;

  String get capacityUnitLabel {
    return capacityUnit == 'fl_oz' ? 'fl oz' : 'mL';
  }

  String get formattedCapacity {
    final value = capacityValue == capacityValue.roundToDouble()
        ? capacityValue.toInt().toString()
        : capacityValue.toStringAsFixed(1);

    return '$value $capacityUnitLabel';
  }

  factory WaterContainer.fromJson(Map<String, dynamic> json) {
    final capacityMl = (json['capacityMl'] as num?)?.toDouble() ?? 0;

    final rawUnit = json['capacityUnit']?.toString().toLowerCase();

    final capacityUnit = rawUnit == 'fl_oz' ? 'fl_oz' : 'ml';

    final storedValue = (json['capacityValue'] as num?)?.toDouble();

    final fallbackValue = capacityUnit == 'fl_oz'
        ? capacityMl / millilitersPerUsFluidOunce
        : capacityMl;

    return WaterContainer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Container',
      capacityMl: capacityMl,
      capacityValue: storedValue ?? fallbackValue,
      capacityUnit: capacityUnit,
    );
  }
}
