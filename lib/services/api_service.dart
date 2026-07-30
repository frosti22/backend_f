import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/checkup_record.dart';
import '../models/food_log_entry.dart';
import '../models/food_suggestion.dart';
import '../models/water_log_entry.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiService {
  static const Map<String, String> _baseHeaders = {
    'Content-Type': 'application/json',
    'x-user-id': 'test-user',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(ApiConfig.baseUrl);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'The backend returned an unreadable response (${response.statusCode}).',
      );
    }

    final body = Map<String, dynamic>.from(decoded as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        body['message']?.toString() ?? 'Request failed (${response.statusCode}).',
      );
    }
    return body;
  }

  Future<void> checkHealth() async {
    final response = await http
        .get(_uri('/health'))
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<List<FoodSuggestion>> searchFoods(String query) async {
    final response = await http
        .get(
          _uri('/api/foods/search', {
            'q': query,
            'limit': '10',
          }),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];
    return data
        .map(
          (item) => FoodSuggestion.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> calculateNutrition({
    required int fdcId,
    required double consumedGrams,
  }) async {
    final response = await http
        .post(
          _uri('/api/nutrition/calculate'),
          headers: _baseHeaders,
          body: jsonEncode({
            'fdcId': fdcId,
            'consumedGrams': consumedGrams,
          }),
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> addDatasetFood({
    required int fdcId,
    required double consumedGrams,
    required String mealType,
  }) async {
    final response = await http
        .post(
          _uri('/api/food-logs'),
          headers: _baseHeaders,
          body: jsonEncode({
            'fdcId': fdcId,
            'consumedGrams': consumedGrams,
            'mealType': mealType,
            'consumedAt': DateTime.now().toIso8601String(),
            'clientRecordId':
                'food-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<void> addManualFood({
    required String name,
    required String mealType,
    required double consumedGrams,
    required Map<String, double?> nutrients,
  }) async {
    final response = await http
        .post(
          _uri('/api/food-logs/manual'),
          headers: _baseHeaders,
          body: jsonEncode({
            'name': name,
            'category': null,
            'consumedGrams': consumedGrams,
            'mealType': mealType,
            'consumedAt': DateTime.now().toIso8601String(),
            'nutrients': nutrients,
            'clientRecordId':
                'manual-food-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<List<FoodLogEntry>> getFoodLogs() async {
    final response = await http
        .get(_uri('/api/food-logs'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    final data = body['data'] as List? ?? const [];
    return data
        .map(
          (item) => FoodLogEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getFoodSummary() async {
    final response = await http
        .get(_uri('/api/food-logs/summary'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteFoodLog(String id) async {
    final response = await http
        .delete(_uri('/api/food-logs/$id'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<void> addWater(double amountMl) async {
    final response = await http
        .post(
          _uri('/api/water-logs'),
          headers: _baseHeaders,
          body: jsonEncode({
            'amountMl': amountMl,
            'loggedAt': DateTime.now().toIso8601String(),
            'source': 'manual',
            'clientRecordId':
                'water-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<List<WaterLogEntry>> getWaterLogs() async {
    final response = await http
        .get(_uri('/api/water-logs'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    final data = body['data'] as List? ?? const [];
    return data
        .map(
          (item) => WaterLogEntry.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getWaterSummary() async {
    final response = await http
        .get(_uri('/api/water-logs/summary'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    final body = _decode(response);
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteWaterLog(String id) async {
    final response = await http
        .delete(_uri('/api/water-logs/$id'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<List<CheckupRecord>> getCheckupRecords() async {
    final response = await http
        .get(
          _uri('/api/checkup-records'),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];
    return data
        .map(
          (item) => CheckupRecord.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<void> addCheckupRecord({
    required String checkupDate,
    double? egfrMlMin173m2,
    double? serumCreatinineMgDl,
    double? uacrMgG,
    double? systolicBloodPressure,
    double? diastolicBloodPressure,
    double? bloodGlucoseMgDl,
    String? notes,
  }) async {
    final response = await http
        .post(
          _uri('/api/checkup-records'),
          headers: _baseHeaders,
          body: jsonEncode({
            'checkupDate': checkupDate,
            'egfrMlMin173m2': egfrMlMin173m2,
            'serumCreatinineMgDl': serumCreatinineMgDl,
            'uacrMgG': uacrMgG,
            'systolicBloodPressure': systolicBloodPressure,
            'diastolicBloodPressure': diastolicBloodPressure,
            'bloodGlucoseMgDl': bloodGlucoseMgDl,
            'notes': notes,
            'clientRecordId':
                'checkup-${DateTime.now().microsecondsSinceEpoch}',
          }),
        )
        .timeout(const Duration(seconds: 12));

    _decode(response);
  }

  Future<void> updateCheckupRecord({
    required String id,
    required String checkupDate,
    double? egfrMlMin173m2,
    double? serumCreatinineMgDl,
    double? uacrMgG,
    double? systolicBloodPressure,
    double? diastolicBloodPressure,
    double? bloodGlucoseMgDl,
    String? notes,
  }) async {
    final response = await http
        .patch(
          _uri('/api/checkup-records/$id'),
          headers: _baseHeaders,
          body: jsonEncode({
            'checkupDate': checkupDate,
            'egfrMlMin173m2': egfrMlMin173m2,
            'serumCreatinineMgDl': serumCreatinineMgDl,
            'uacrMgG': uacrMgG,
            'systolicBloodPressure': systolicBloodPressure,
            'diastolicBloodPressure': diastolicBloodPressure,
            'bloodGlucoseMgDl': bloodGlucoseMgDl,
            'notes': notes,
          }),
        )
        .timeout(const Duration(seconds: 12));

    _decode(response);
  }

  Future<void> deleteCheckupRecord(String id) async {
    final response = await http
        .delete(
          _uri('/api/checkup-records/$id'),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    _decode(response);
  }

}
