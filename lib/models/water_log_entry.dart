class WaterLogEntry {
  const WaterLogEntry({
    required this.id,
    required this.amountMl,
    required this.loggedAt,
    this.containerId,
    this.containerName,
  });

  final String id;
  final double amountMl;
  final DateTime? loggedAt;
  final String? containerId;
  final String? containerName;

  factory WaterLogEntry.fromJson(Map<String, dynamic> json) {
    return WaterLogEntry(
      id: json['id']?.toString() ?? '',
      amountMl: (json['amountMl'] as num?)?.toDouble() ?? 0,
      loggedAt: DateTime.tryParse(json['loggedAt']?.toString() ?? ''),
      containerId: json['containerId']?.toString(),
      containerName: json['containerName']?.toString(),
    );
  }
}
