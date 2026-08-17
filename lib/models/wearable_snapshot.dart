class WearableWorkout {
  const WearableWorkout({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.distanceMeters,
    required this.energyKcal,
    required this.steps,
    required this.source,
  });

  final String type;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final double distanceMeters;
  final double energyKcal;
  final int steps;
  final String source;
}

class WearableSnapshot {
  const WearableSnapshot({
    required this.steps,
    required this.distanceMeters,
    required this.totalCaloriesKcal,
    required this.latestHeartRate,
    required this.totalSleepMinutes,
    required this.lightSleepMinutes,
    required this.deepSleepMinutes,
    required this.remSleepMinutes,
    required this.awakeMinutes,
    required this.workouts,
    required this.sources,
    required this.loadedAt,
  });

  final int steps;
  final double distanceMeters;
  final double totalCaloriesKcal;
  final double? latestHeartRate;

  final double totalSleepMinutes;
  final double lightSleepMinutes;
  final double deepSleepMinutes;
  final double remSleepMinutes;
  final double awakeMinutes;

  final List<WearableWorkout> workouts;
  final List<String> sources;
  final DateTime loadedAt;

  factory WearableSnapshot.empty() {
    return WearableSnapshot(
      steps: 0,
      distanceMeters: 0,
      totalCaloriesKcal: 0,
      latestHeartRate: null,
      totalSleepMinutes: 0,
      lightSleepMinutes: 0,
      deepSleepMinutes: 0,
      remSleepMinutes: 0,
      awakeMinutes: 0,
      workouts: const [],
      sources: const [],
      loadedAt: DateTime.now(),
    );
  }
}
