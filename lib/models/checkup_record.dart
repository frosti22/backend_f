class CheckupRecord {
  const CheckupRecord({
    required this.id,
    required this.checkupDate,
    required this.source,
    this.egfrMlMin173m2,
    this.serumCreatinineMgDl,
    this.uacrMgG,
    this.systolicBloodPressure,
    this.diastolicBloodPressure,
    this.bloodGlucoseMgDl,
    this.notes,
  });

  final String id;
  final DateTime checkupDate;
  final String source;
  final double? egfrMlMin173m2;
  final double? serumCreatinineMgDl;
  final double? uacrMgG;
  final double? systolicBloodPressure;
  final double? diastolicBloodPressure;
  final double? bloodGlucoseMgDl;
  final String? notes;

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  factory CheckupRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return CheckupRecord(
      id: json['id']?.toString() ?? '',
      checkupDate:
          DateTime.tryParse(json['checkupDate']?.toString() ?? '') ??
          DateTime.now(),
      source: json['source']?.toString() ?? 'manual',
      egfrMlMin173m2: _number(json['egfrMlMin173m2']),
      serumCreatinineMgDl:
          _number(json['serumCreatinineMgDl']),
      uacrMgG: _number(json['uacrMgG']),
      systolicBloodPressure:
          _number(json['systolicBloodPressure']),
      diastolicBloodPressure:
          _number(json['diastolicBloodPressure']),
      bloodGlucoseMgDl:
          _number(json['bloodGlucoseMgDl']),
      notes: json['notes']?.toString(),
    );
  }
}
