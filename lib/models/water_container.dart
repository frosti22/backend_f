class WaterContainer {
  const WaterContainer({
    required this.id,
    required this.name,
    required this.capacityMl,
  });

  final String id;
  final String name;
  final double capacityMl;

  factory WaterContainer.fromJson(Map<String, dynamic> json) {
    return WaterContainer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Container',
      capacityMl: (json['capacityMl'] as num?)?.toDouble() ?? 0,
    );
  }
}
