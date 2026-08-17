import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/checkup_record.dart';
import '../models/clinic_directory_models.dart';
import '../models/food_log_entry.dart';
import '../models/food_suggestion.dart';
import '../models/water_container.dart';
import '../models/water_log_entry.dart';
import '../models/wearable_snapshot.dart';

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

    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'The backend returned an unreadable response '
        '(${response.statusCode}).',
      );
    }

    final body = Map<String, dynamic>.from(decoded as Map);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        body['message']?.toString() ??
            'Request failed '
                '(${response.statusCode}).',
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
          _uri('/api/foods/search', {'q': query, 'limit': '10'}),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];

    return data
        .map(
          (item) =>
              FoodSuggestion.fromJson(Map<String, dynamic>.from(item as Map)),
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
          body: jsonEncode({'fdcId': fdcId, 'consumedGrams': consumedGrams}),
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
                'food-'
                '${DateTime.now().microsecondsSinceEpoch}',
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
                'manual-food-'
                '${DateTime.now().microsecondsSinceEpoch}',
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
          (item) =>
              FoodLogEntry.fromJson(Map<String, dynamic>.from(item as Map)),
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

  Future<WaterContainer> saveWaterContainer({
    required String name,
    required double capacityValue,
    required String capacityUnit,
  }) async {
    final response = await http
        .post(
          _uri('/api/water-logs/containers'),
          headers: _baseHeaders,
          body: jsonEncode({
            'name': name,
            'capacityValue': capacityValue,
            'capacityUnit': capacityUnit,
          }),
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);

    return WaterContainer.fromJson(
      Map<String, dynamic>.from(body['data'] as Map),
    );
  }

  Future<List<WaterContainer>> getWaterContainers() async {
    final response = await http
        .get(_uri('/api/water-logs/containers'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];

    return data
        .map(
          (item) =>
              WaterContainer.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> addWaterFromContainer(String containerId) async {
    final response = await http
        .post(
          _uri('/api/water-logs'),
          headers: _baseHeaders,
          body: jsonEncode({
            'containerId': containerId,
            'loggedAt': DateTime.now().toIso8601String(),
            'source': 'manual',
            'clientRecordId':
                'water-'
                '${DateTime.now().microsecondsSinceEpoch}',
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
          (item) =>
              WaterLogEntry.fromJson(Map<String, dynamic>.from(item as Map)),
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
        .get(_uri('/api/checkup-records'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];

    return data
        .map(
          (item) =>
              CheckupRecord.fromJson(Map<String, dynamic>.from(item as Map)),
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
                'checkup-'
                '${DateTime.now().microsecondsSinceEpoch}',
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
        .delete(_uri('/api/checkup-records/$id'), headers: _baseHeaders)
        .timeout(const Duration(seconds: 12));

    _decode(response);
  }

  Future<void> saveWearableSnapshot(
    WearableSnapshot snapshot,
  ) async {
    final localDate = snapshot.loadedAt.toLocal();
    final date =
        '${localDate.year.toString().padLeft(4, '0')}-'
        '${localDate.month.toString().padLeft(2, '0')}-'
        '${localDate.day.toString().padLeft(2, '0')}';

    final activeMinutes = snapshot.workouts.fold<int>(
      0,
      (total, workout) => total + workout.durationMinutes,
    );

    final response = await http
        .post(
          _uri('/api/wearable-records/daily'),
          headers: _baseHeaders,
          body: jsonEncode({
            'date': date,
            'steps': snapshot.steps,
            'distanceMeters': snapshot.distanceMeters > 0
                ? snapshot.distanceMeters
                : null,
            'activeCaloriesKcal': snapshot.totalCaloriesKcal > 0
                ? snapshot.totalCaloriesKcal
                : null,
            'activeMinutes': activeMinutes,
            'sedentaryHours': null,
            'sleepMinutes': snapshot.totalSleepMinutes > 0
                ? snapshot.totalSleepMinutes
                : null,
            'lightSleepMinutes': snapshot.lightSleepMinutes > 0
                ? snapshot.lightSleepMinutes
                : null,
            'deepSleepMinutes': snapshot.deepSleepMinutes > 0
                ? snapshot.deepSleepMinutes
                : null,
            'remSleepMinutes': snapshot.remSleepMinutes > 0
                ? snapshot.remSleepMinutes
                : null,
            'awakeMinutes': snapshot.awakeMinutes > 0
                ? snapshot.awakeMinutes
                : null,
            'latestHeartRateBpm': snapshot.latestHeartRate,
            'sources': snapshot.sources,
            'sourcePlatform': 'health_connect',
            'syncedAt': snapshot.loadedAt.toIso8601String(),
            'workouts': snapshot.workouts
                .map(
                  (workout) => {
                    'type': workout.type,
                    'startTime': workout.startTime.toIso8601String(),
                    'endTime': workout.endTime.toIso8601String(),
                    'durationMinutes': workout.durationMinutes,
                    'distanceMeters': workout.distanceMeters,
                    'energyKcal': workout.energyKcal,
                    'steps': workout.steps,
                    'source': workout.source,
                  },
                )
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    _decode(response);
  }

  Future<Map<String, dynamic>> getMonthlyAssessment(
    String month,
  ) async {
    final response = await http
        .get(
          _uri('/api/monthly-assessments', {'month': month}),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);

    return Map<String, dynamic>.from(body['data'] as Map);
  }



  Future<List<ClinicRegionOption>> getClinicRegions() async {
    final response = await http
        .get(
          _uri('/api/locations/regions'),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = body['data'] as List? ?? const [];

    return data
        .map(
          (item) => ClinicRegionOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<({
    List<ClinicAreaOption> combinedAreas,
    List<ClinicAreaOption> provinces,
    List<ClinicAreaOption> regionLevelLocalities,
    List<ClinicAreaOption> specialAreas,
    bool hasRegionLevelLocalities,
  })> getClinicAreas(String region) async {
    final response = await http
        .get(
          _uri('/api/locations/provinces', {
            'region': region,
          }),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = Map<String, dynamic>.from(body['data'] as Map);
    final combinedAreasJson =
        data['combinedAreas'] as List? ?? const [];
    final provincesJson = data['provinces'] as List? ?? const [];
    final regionLevelLocalitiesJson =
        data['regionLevelLocalities'] as List? ?? const [];
    final specialAreasJson = data['specialAreas'] as List? ?? const [];

    return (
      combinedAreas: combinedAreasJson
          .map(
            (item) => ClinicAreaOption.fromJson(
              Map<String, dynamic>.from(item as Map),
              defaultType: 'province',
            ),
          )
          .toList(),
      provinces: provincesJson
          .map(
            (item) => ClinicAreaOption.fromJson(
              Map<String, dynamic>.from(item as Map),
              defaultType: 'province',
            ),
          )
          .toList(),
      regionLevelLocalities: regionLevelLocalitiesJson
          .map(
            (item) => ClinicAreaOption.fromJson(
              Map<String, dynamic>.from(item as Map),
              defaultType: 'region_level_locality',
            ),
          )
          .toList(),
      specialAreas: specialAreasJson
          .map(
            (item) => ClinicAreaOption.fromJson(
              Map<String, dynamic>.from(item as Map),
              defaultType: 'special_area',
            ),
          )
          .toList(),
      hasRegionLevelLocalities:
          data['hasRegionLevelLocalities'] == true,
    );
  }

  Future<List<ClinicLocalityOption>> getClinicLocalities({
    required String region,
    ClinicAreaOption? area,
  }) async {
    final query = <String, String>{
      'region': region,
    };

    if (area != null && area.type == 'province') {
      query['province'] = area.name;
    } else if (area != null && area.type == 'special_area') {
      query['specialArea'] = area.name;
    }

    final response = await http
        .get(
          _uri('/api/locations/localities', query),
          headers: _baseHeaders,
        )
        .timeout(const Duration(seconds: 12));

    final body = _decode(response);
    final data = Map<String, dynamic>.from(body['data'] as Map);
    final localitiesJson = data['localities'] as List? ?? const [];

    return localitiesJson
        .map(
          (item) => ClinicLocalityOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<ClinicMatchResult> matchAccreditedClinics({
    required String region,
    required String cityMunicipality,
    String? province,
    int limit = 50,
  }) async {
    final response = await http
        .post(
          _uri('/api/facilities/match'),
          headers: _baseHeaders,
          body: jsonEncode({
            'region': region,
            'province': province,
            'cityMunicipality': cityMunicipality,
            'limit': limit,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final body = _decode(response);
    final data = Map<String, dynamic>.from(body['data'] as Map);

    return ClinicMatchResult.fromJson(data);
  }

}
