class FoodSuggestion {
  const FoodSuggestion({
    required this.fdcId,
    required this.name,
    required this.category,
    required this.nutrientsPer100g,
  });

  final int fdcId;
  final String name;
  final String? category;
  final Map<String, dynamic> nutrientsPer100g;

  factory FoodSuggestion.fromJson(Map<String, dynamic> json) {
    return FoodSuggestion(
      fdcId: (json['fdcId'] as num).toInt(),
      name: json['name']?.toString() ?? 'Unnamed food',
      category: json['category']?.toString(),
      nutrientsPer100g: Map<String, dynamic>.from(
        json['nutrientsPer100g'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}
