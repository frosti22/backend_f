import 'dart:async';

import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../models/wearable_snapshot.dart';
import '../services/api_service.dart';
import '../services/health_service.dart';

class WearableDashboardScreen extends StatefulWidget {
  const WearableDashboardScreen({super.key});

  @override
  State<WearableDashboardScreen> createState() =>
      _WearableDashboardScreenState();
}

class _WearableDashboardScreenState extends State<WearableDashboardScreen>
    with WidgetsBindingObserver {
  final HealthService _healthService = HealthService();
  final ApiService _api = ApiService();

  // Avoid aggressive Health Connect polling/rate limiting.
  static const Duration _autoSyncInterval = Duration(seconds: 100);

  WearableSnapshot _snapshot = WearableSnapshot.empty();

  bool _loading = true;
  bool _authorized = true;
  String _status = 'Press Connect Health Data to begin.';

  Timer? _autoSyncTimer;
  DateTime _snapshotDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHealth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_authorized) {
        _readDataSilently();
        _startAutoSync();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopAutoSync();
    }
  }

  Future<void> _initializeHealth() async {
    try {
      await _healthService.configure();
      final sdkStatus = await _healthService.getStatus();

      if (!mounted) return;

      setState(() {
        if (sdkStatus == HealthConnectSdkStatus.sdkAvailable) {
          _status = 'Health Connect is available.';
        } else {
          _status = 'Health Connect is unavailable or requires installation.';
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Initialization failed: $error';
      });
    }
  }

  Future<void> _connectAndRead() async {
    setState(() {
      _loading = true;
      _status = 'Requesting Health Connect permissions...';
    });

    try {
      final authorized = await _healthService.requestAccess();

      if (!authorized) {
        throw Exception('Health Connect access was not granted.');
      }

      if (!mounted) return;

      setState(() {
        _authorized = true;
        _status = 'Permission granted. Reading data...';
      });

      await _readData();
      _startAutoSync();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Connection failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startAutoSync() {
    if (!_authorized) return;

    _autoSyncTimer?.cancel();

    _autoSyncTimer = Timer.periodic(
      _autoSyncInterval,
      (_) => _readDataSilently(),
    );
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> _readDataSilently() async {
    if (!mounted || !_authorized || _loading) return;

    try {
      final oldSnapshot = _snapshot;
      final snapshot = await _healthService.readData();

      if (!mounted) return;

      if (_shouldKeepPreviousSnapshot(oldSnapshot, snapshot)) {
        debugPrint(
          'AUTO SYNC: ignored temporary zero/incomplete Health Connect read.',
        );
        return;
      }

      final changed = _hasWearableDataChanged(oldSnapshot, snapshot);

      setState(() {
        _acceptSnapshot(snapshot);
      });

      if (!changed) return;

      try {
        await _api.saveWearableSnapshot(snapshot);
      } catch (error) {
        debugPrint('AUTO SYNC BACKEND SAVE ERROR: $error');
      }
    } catch (error) {
      debugPrint('AUTO SYNC HEALTH CONNECT ERROR: $error');
    }
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _shouldKeepPreviousSnapshot(
    WearableSnapshot previous,
    WearableSnapshot incoming,
  ) {
    final now = DateTime.now();

    if (!_isSameCalendarDay(_snapshotDay, now)) {
      return false;
    }

    final previousHasUsefulData =
        previous.steps > 0 ||
        previous.distanceMeters > 0 ||
        previous.totalCaloriesKcal > 0 ||
        previous.latestHeartRate != null ||
        previous.totalSleepMinutes > 0 ||
        previous.lightSleepMinutes > 0 ||
        previous.deepSleepMinutes > 0 ||
        previous.remSleepMinutes > 0 ||
        previous.awakeMinutes > 0 ||
        previous.workouts.isNotEmpty;

    if (!previousHasUsefulData) {
      return false;
    }

    final incomingIsCompletelyEmpty =
        incoming.steps <= 0 &&
        incoming.distanceMeters <= 0 &&
        incoming.totalCaloriesKcal <= 0 &&
        incoming.latestHeartRate == null &&
        incoming.totalSleepMinutes <= 0 &&
        incoming.lightSleepMinutes <= 0 &&
        incoming.deepSleepMinutes <= 0 &&
        incoming.remSleepMinutes <= 0 &&
        incoming.awakeMinutes <= 0 &&
        incoming.workouts.isEmpty;

    if (incomingIsCompletelyEmpty) {
      return true;
    }

    final suspiciousDailyTotalReset =
        (previous.steps > 0 && incoming.steps == 0) ||
        (previous.distanceMeters > 0 && incoming.distanceMeters == 0) ||
        (previous.totalCaloriesKcal > 0 && incoming.totalCaloriesKcal == 0);

    return suspiciousDailyTotalReset;
  }

  void _acceptSnapshot(WearableSnapshot snapshot) {
    _snapshot = snapshot;
    _snapshotDay = DateTime.now();
  }

  bool _hasWearableDataChanged(
    WearableSnapshot oldValue,
    WearableSnapshot newValue,
  ) {
    if (oldValue.steps != newValue.steps) return true;
    if (oldValue.distanceMeters != newValue.distanceMeters) return true;
    if (oldValue.totalCaloriesKcal != newValue.totalCaloriesKcal) return true;
    if (oldValue.latestHeartRate != newValue.latestHeartRate) return true;
    if (oldValue.totalSleepMinutes != newValue.totalSleepMinutes) return true;
    if (oldValue.lightSleepMinutes != newValue.lightSleepMinutes) return true;
    if (oldValue.deepSleepMinutes != newValue.deepSleepMinutes) return true;
    if (oldValue.remSleepMinutes != newValue.remSleepMinutes) return true;
    if (oldValue.awakeMinutes != newValue.awakeMinutes) return true;
    if (oldValue.workouts.length != newValue.workouts.length) return true;

    final oldWorkoutMinutes = oldValue.workouts.fold<int>(
      0,
      (total, workout) => total + workout.durationMinutes,
    );

    final newWorkoutMinutes = newValue.workouts.fold<int>(
      0,
      (total, workout) => total + workout.durationMinutes,
    );

    return oldWorkoutMinutes != newWorkoutMinutes;
  }

  Future<void> _readData() async {
    setState(() {
      _loading = true;
      _status = 'Reading wearable data from Health Connect...';
    });

    try {
      final snapshot = await _healthService.readData();

      if (!mounted) return;

      if (_shouldKeepPreviousSnapshot(_snapshot, snapshot)) {
        setState(() {
          _status =
              'Health Connect returned an incomplete reading. '
              'Keeping the last valid wearable data.';
        });
        return;
      }

      setState(() {
        _acceptSnapshot(snapshot);
        _status = 'Health data loaded. Saving daily record...';
      });

      try {
        await _api.saveWearableSnapshot(snapshot);

        if (!mounted) return;

        setState(() {
          _status = 'Health data loaded and saved for the monthly assessment.';
        });
      } catch (error) {
        if (!mounted) return;

        setState(() {
          _status = 'Health data loaded, but the backend save failed: $error';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Unable to read health data: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _minutesToHours(double minutes) {
    final hours = minutes.floor() ~/ 60;
    final remaining = minutes.round() % 60;
    return '${hours}h ${remaining}m';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wearable Data')),
      body: RefreshIndicator(
        onRefresh: _authorized ? _readData : _connectAndRead,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_status),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _connectAndRead,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('Connect Health Data'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _connectAndRead,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('Disconnect Health Data'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !_authorized || _loading ? null : _readData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Data'),
            ),
            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 24),
            Text('Today', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _MetricCard(
              title: 'Steps',
              value: '${_snapshot.steps}',
              icon: Icons.directions_walk,
            ),

            _MetricCard(
              title: 'Distance',
              value: '${_snapshot.distanceMeters ~/ 1000} km',
              icon: Icons.directions_walk,
            ),

            _MetricCard(
              title: 'Active Seconds',
              value:
                  '${_snapshot.workouts.fold<int>(0, (total, workout) => total + workout.durationMinutes)} min',
              icon: Icons.timer_outlined,
            ),
            _MetricCard(
              title: 'Active Calories',
              value: '${_snapshot.totalCaloriesKcal.toStringAsFixed(1)} kcal',
              icon: Icons.local_fire_department,
            ),
            _MetricCard(
              title: 'Latest Heart Rate',
              value: _snapshot.latestHeartRate == null
                  ? 'No data'
                  : '${_snapshot.latestHeartRate!.toStringAsFixed(0)} bpm',
              icon: Icons.favorite,
            ),
            const SizedBox(height: 24),
            Text('Sleep', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            _MetricCard(
              title: 'Total Sleep',
              value: _minutesToHours(_snapshot.totalSleepMinutes),
              icon: Icons.bedtime,
            ),
            _MetricCard(
              title: 'Light Sleep',
              value: _minutesToHours(_snapshot.lightSleepMinutes),
              icon: Icons.nightlight,
            ),
            _MetricCard(
              title: 'Deep Sleep',
              value: _minutesToHours(_snapshot.deepSleepMinutes),
              icon: Icons.dark_mode,
            ),
            _MetricCard(
              title: 'REM Sleep',
              value: _minutesToHours(_snapshot.remSleepMinutes),
              icon: Icons.auto_awesome,
            ),
            _MetricCard(
              title: 'Awake During Sleep',
              value: _minutesToHours(_snapshot.awakeMinutes),
              icon: Icons.visibility,
            ),
            const SizedBox(height: 24),
            Text(
              'Workouts (${_snapshot.workouts.length})',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (_snapshot.workouts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No workout records were received.'),
                ),
              ),
            for (final workout in _snapshot.workouts)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text(workout.type),
                  subtitle: Text(
                    '${_formatTime(workout.startTime)}–'
                    '${_formatTime(workout.endTime)}\n'
                    '${workout.durationMinutes} minutes • '
                    '${(workout.distanceMeters / 1000).toStringAsFixed(2)} km\n'
                    '${workout.energyKcal.toStringAsFixed(1)} kcal • '
                    '${workout.steps} steps\n'
                    'Source: ${workout.source}',
                  ),
                  isThreeLine: true,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Detected Sources',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (_snapshot.sources.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No Health Connect sources detected.'),
                ),
              ),
            for (final source in _snapshot.sources)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.watch),
                  title: Text(source),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
