import 'dart:io';

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/wearable_snapshot.dart';

class HealthService {
  final Health _health = Health();

  // Estimated average stride used for normal daily distance.
  static const double _estimatedStrideMetersPerStep = 0.75;

  // These are the daily Health Connect records we currently read.
  // DISTANCE_DELTA is intentionally NOT read here because the main daily
  // distance is calculated from steps.
  static const List<HealthDataType> _dailyTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
  ];

  static const List<HealthDataType> _sleepTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_UNKNOWN,
  ];

  // Keep DISTANCE_DELTA permission available for future workout fallback,
  // but do not query/use it for the normal daily distance.
  List<HealthDataType> get _authorizationTypes => [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    ..._dailyTypes,
    ..._sleepTypes,
  ];

  List<HealthDataAccess> get _readPermissions =>
      _authorizationTypes.map((_) => HealthDataAccess.READ).toList();

  Future<void> configure() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'This proof of concept currently supports Android only.',
      );
    }

    await _health.configure();
    await _health.getHealthConnectSdkStatus();
  }

  Future<HealthConnectSdkStatus?> getStatus() async {
    return _health.getHealthConnectSdkStatus();
  }

  Future<bool> requestAccess() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Health Connect is available only on Android.');
    }

    final activityStatus = await Permission.activityRecognition.request();

    if (!activityStatus.isGranted) {
      throw Exception('Physical activity permission was not granted.');
    }

    return _health.requestAuthorization(
      _authorizationTypes,
      permissions: _readPermissions,
    );
  }

  Future<WearableSnapshot> readData() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    // Sleep may begin during the previous calendar day.
    final sleepStart = now.subtract(const Duration(hours: 36));

    final dailyRaw = await _health.getHealthDataFromTypes(
      types: _dailyTypes,
      startTime: startOfToday,
      endTime: now,
    );

    final sleepRaw = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: sleepStart,
      endTime: now,
    );

    final dailyData = _health.removeDuplicates(dailyRaw);
    final sleepData = _health.removeDuplicates(sleepRaw);

    // Read today's total steps once using Health Connect aggregation.
    final steps = await _health.getTotalStepsInInterval(startOfToday, now) ?? 0;

    // Main daily distance is estimated from total daily steps.
    // DISTANCE_DELTA is not used here.
    final distanceMeters = steps * _estimatedStrideMetersPerStep;

    final activeCalories = _sumNumericValues(
      dailyData,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    );

    final latestHeartRate = _findLatestNumericValue(
      dailyData,
      HealthDataType.HEART_RATE,
    );

    final workouts = _createWorkouts(dailyData);

    final lightSleep = _sumSleepMinutes(sleepData, HealthDataType.SLEEP_LIGHT);

    final deepSleep = _sumSleepMinutes(sleepData, HealthDataType.SLEEP_DEEP);

    final remSleep = _sumSleepMinutes(sleepData, HealthDataType.SLEEP_REM);

    final unspecifiedSleep = _sumSleepMinutes(
      sleepData,
      HealthDataType.SLEEP_ASLEEP,
    );

    final unknownSleep = _sumSleepMinutes(
      sleepData,
      HealthDataType.SLEEP_UNKNOWN,
    );

    final awakeMinutes = _sumSleepMinutes(
      sleepData,
      HealthDataType.SLEEP_AWAKE,
    );

    final sessionMinutes = _sumSleepMinutes(
      sleepData,
      HealthDataType.SLEEP_SESSION,
    );

    final calculatedSleep =
        lightSleep + deepSleep + remSleep + unspecifiedSleep + unknownSleep;

    final totalSleep = sessionMinutes > 0 ? sessionMinutes : calculatedSleep;

    final allData = [...dailyData, ...sleepData];

    final sources =
        allData
            .map((point) => '${point.sourceName} — ${point.sourceId}')
            .where((source) => source.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return WearableSnapshot(
      steps: steps,
      distanceMeters: distanceMeters,
      totalCaloriesKcal: activeCalories,
      latestHeartRate: latestHeartRate,
      totalSleepMinutes: totalSleep,
      lightSleepMinutes: lightSleep,
      deepSleepMinutes: deepSleep,
      remSleepMinutes: remSleep,
      awakeMinutes: awakeMinutes,
      workouts: workouts,
      sources: sources,
      loadedAt: now,
    );
  }

  double _sumNumericValues(List<HealthDataPoint> data, HealthDataType type) {
    return data.where((point) => point.type == type).fold<double>(0, (
      total,
      point,
    ) {
      final value = _numericValue(point);
      return total + (value ?? 0);
    });
  }

  double _sumSleepMinutes(List<HealthDataPoint> data, HealthDataType type) {
    return data.where((point) => point.type == type).fold<double>(0, (
      total,
      point,
    ) {
      final numeric = _numericValue(point);

      if (numeric != null && numeric > 0) {
        return total + numeric;
      }

      return total + point.dateTo.difference(point.dateFrom).inSeconds / 60;
    });
  }

  double? _findLatestNumericValue(
    List<HealthDataPoint> data,
    HealthDataType type,
  ) {
    final points = data.where((point) => point.type == type).toList()
      ..sort((first, second) => second.dateTo.compareTo(first.dateTo));

    for (final point in points) {
      final value = _numericValue(point);

      if (value != null) {
        return value;
      }
    }

    return null;
  }

  double? _numericValue(HealthDataPoint point) {
    final value = point.value;

    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }

    return null;
  }

  List<WearableWorkout> _createWorkouts(List<HealthDataPoint> data) {
    final workoutPoints =
        data.where((point) => point.type == HealthDataType.WORKOUT).toList()
          ..sort((first, second) => second.dateFrom.compareTo(first.dateFrom));

    return workoutPoints.map((point) {
      final summary = point.workoutSummary;

      return WearableWorkout(
        type: summary?.workoutType ?? 'Workout',
        startTime: point.dateFrom,
        endTime: point.dateTo,
        durationMinutes: point.dateTo.difference(point.dateFrom).inMinutes,

        // Keep actual workout distance from the workout summary.
        distanceMeters: summary?.totalDistance.toDouble() ?? 0,

        energyKcal: summary?.totalEnergyBurned.toDouble() ?? 0,
        steps: summary?.totalSteps.toInt() ?? 0,
        source: point.sourceName,
      );
    }).toList();
  }
}
