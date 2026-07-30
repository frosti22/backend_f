class FoodLogEntry {
  const FoodLogEntry({
    required this.id,
    required this.name,
    required this.mealType,
    required this.consumedGrams,
    required this.nutrients,
    required this.consumedAt,
  });

  final String id;
  final String name;
  final String mealType;
  final double consumedGrams;
  final Map<String, dynamic> nutrients;
  final DateTime? consumedAt;

  factory FoodLogEntry.fromJson(Map<String, dynamic> json) {
    final food = Map<String, dynamic>.from(
      json['food'] as Map? ?? const <String, dynamic>{},
    );
    final quantity = Map<String, dynamic>.from(
      json['quantity'] as Map? ?? const <String, dynamic>{},
    );

    return FoodLogEntry(
      id: json['id']?.toString() ?? '',
      name: food['name']?.toString() ?? 'Unnamed food',
      mealType: json['mealType']?.toString() ?? 'other',
      consumedGrams: (quantity['consumedGrams'] as num?)?.toDouble() ?? 0,
      nutrients: Map<String, dynamic>.from(
        json['nutrients'] as Map? ?? const <String, dynamic>{},
      ),
      consumedAt: DateTime.tryParse(json['consumedAt']?.toString() ?? ''),
    );
  }
}
