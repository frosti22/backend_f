class WaterLogEntry {
  const WaterLogEntry({
    required this.id,
    required this.amountMl,
    required this.loggedAt,
  });

  final String id;
  final double amountMl;
  final DateTime? loggedAt;

  factory WaterLogEntry.fromJson(Map<String, dynamic> json) {
    return WaterLogEntry(
      id: json['id']?.toString() ?? '',
      amountMl: (json['amountMl'] as num?)?.toDouble() ?? 0,
      loggedAt: DateTime.tryParse(json['loggedAt']?.toString() ?? ''),
    );
  }
}
