import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';

class MonthlyAssessmentScreen extends StatefulWidget {
  const MonthlyAssessmentScreen({super.key});

  @override
  State<MonthlyAssessmentScreen> createState() =>
      _MonthlyAssessmentScreenState();
}

class _MonthlyAssessmentScreenState extends State<MonthlyAssessmentScreen> {
  final ApiService _api = ApiService();

  late DateTime _selectedMonth;
  Map<String, dynamic>? _assessment;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadAssessment();
  }

  String get _monthKey =>
      '${_selectedMonth.year.toString().padLeft(4, '0')}-'
      '${_selectedMonth.month.toString().padLeft(2, '0')}';

  String get _monthLabel {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
  }

  Future<void> _loadAssessment() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _api.getMonthlyAssessment(_monthKey);

      if (!mounted) return;

      setState(() {
        _assessment = result;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not connect to ${ApiConfig.baseUrl}.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeMonth(int offset) async {
    final next = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + offset,
    );
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);

    if (next.isAfter(current)) return;

    setState(() {
      _selectedMonth = next;
      _assessment = null;
    });

    await _loadAssessment();
  }

  Map<String, dynamic> _section(String key) {
    final value = _assessment?[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  String _number(dynamic value, {int decimals = 1}) {
    if (value == null) return 'Not available';

    final number = value is num
        ? value.toDouble()
        : double.tryParse(value.toString());

    if (number == null) return 'Not available';
    if (number == number.roundToDouble()) return number.toInt().toString();

    return number.toStringAsFixed(decimals);
  }

  String _percentage(dynamic value) {
    if (value == null) return 'Not available';

    final number = value is num
        ? value.toDouble()
        : double.tryParse(value.toString());

    if (number == null) return 'Not available';

    return '${(number * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final period = _section('period');
    final food = _section('food');
    final water = _section('water');
    final wearable = _section('wearable');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Assessment'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAssessment,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAssessment,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _loading ? null : () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _monthLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: _isCurrentMonth || _loading
                          ? null
                          : () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              ),
            ],
            if (_assessment != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Coverage uses ${_number(period['assessmentDays'])} day(s) '
                    'in this assessment window. Averages use only days with '
                    'valid data, so missing days are not treated as zero.',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Food nutrient averages'),
              _metricGrid([
                _AssessmentMetric(
                  label: 'Average daily calories',
                  value:
                      '${_number(food['averageDailyCaloriesKcal'])} kcal/day',
                  icon: Icons.local_fire_department_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average daily sodium',
                  value: '${_number(food['averageDailySodiumMg'])} mg/day',
                  icon: Icons.restaurant_rounded,
                ),
                _AssessmentMetric(
                  label: 'Average daily protein',
                  value: '${_number(food['averageDailyProteinG'])} g/day',
                  icon: Icons.fitness_center_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average daily carbohydrates',
                  value:
                      '${_number(food['averageDailyCarbohydratesG'])} g/day',
                  icon: Icons.bakery_dining_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average daily fat',
                  value: '${_number(food['averageDailyFatG'])} g/day',
                  icon: Icons.opacity_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average daily potassium',
                  value:
                      '${_number(food['averageDailyPotassiumMg'])} mg/day',
                  icon: Icons.eco_outlined,
                ),
              ]),
              const SizedBox(height: 12),
              _sectionTitle('Food data availability'),
              _metricGrid([
                _AssessmentMetric(
                  label: 'Diet coverage',
                  value: _percentage(food['dietCoverage']),
                  icon: Icons.fact_check_outlined,
                ),
                _AssessmentMetric(
                  label: 'Days with food logs',
                  value: _number(food['daysWithFoodLogs']),
                  icon: Icons.calendar_today_outlined,
                ),
                _AssessmentMetric(
                  label: 'Days with calorie data',
                  value: _number(food['daysWithCaloriesData']),
                  icon: Icons.data_usage_rounded,
                ),
                _AssessmentMetric(
                  label: 'Days with sodium data',
                  value: _number(food['daysWithSodiumData']),
                  icon: Icons.data_usage_rounded,
                ),
                _AssessmentMetric(
                  label: 'Days with protein data',
                  value: _number(food['daysWithProteinData']),
                  icon: Icons.data_usage_rounded,
                ),
                _AssessmentMetric(
                  label: 'Days with carbohydrate data',
                  value: _number(food['daysWithCarbohydratesData']),
                  icon: Icons.data_usage_rounded,
                ),
                _AssessmentMetric(
                  label: 'Days with fat data',
                  value: _number(food['daysWithFatData']),
                  icon: Icons.data_usage_rounded,
                ),
                _AssessmentMetric(
                  label: 'Days with potassium data',
                  value: _number(food['daysWithPotassiumData']),
                  icon: Icons.data_usage_rounded,
                ),
              ]),
              const SizedBox(height: 20),
              _sectionTitle('Water'),
              _metricGrid([
                _AssessmentMetric(
                  label: 'Average daily water',
                  value: '${_number(water['averageDailyWaterMl'])} mL/day',
                  icon: Icons.water_drop_outlined,
                ),
                _AssessmentMetric(
                  label: 'Water coverage',
                  value: _percentage(water['waterCoverage']),
                  icon: Icons.fact_check_outlined,
                ),
                _AssessmentMetric(
                  label: 'Days with water logs',
                  value: _number(water['daysWithWaterLogs']),
                  icon: Icons.calendar_today_outlined,
                ),
              ]),
              const SizedBox(height: 20),
              _sectionTitle('Wearable'),
              _metricGrid([
                _AssessmentMetric(
                  label: 'Average daily steps',
                  value: '${_number(wearable['averageDailySteps'])} steps/day',
                  icon: Icons.directions_walk_rounded,
                ),
                _AssessmentMetric(
                  label: 'Average active minutes',
                  value:
                      '${_number(wearable['averageActiveMinutes'])} min/day',
                  icon: Icons.timer_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average sleep',
                  value: '${_number(wearable['averageSleepHours'])} h/day',
                  icon: Icons.bedtime_outlined,
                ),
                _AssessmentMetric(
                  label: 'Average sedentary time',
                  value:
                      '${_number(wearable['averageSedentaryHours'])} h/day',
                  icon: Icons.chair_outlined,
                ),
                _AssessmentMetric(
                  label: 'Wearable coverage',
                  value: _percentage(wearable['wearableCoverage']),
                  icon: Icons.watch_outlined,
                ),
                _AssessmentMetric(
                  label: 'Days with wearable data',
                  value: _number(wearable['daysWithWearableData']),
                  icon: Icons.calendar_today_outlined,
                ),
              ]),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sedentary hours remain Not available because the current '
                    'wearable integration does not collect a reliable sedentary-time record.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _metricGrid(List<_AssessmentMetric> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 700 ? (width - 24) / 3 : (width - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: itemWidth,
                  child: _AssessmentMetricCard(metric: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _AssessmentMetric {
  const _AssessmentMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _AssessmentMetricCard extends StatelessWidget {
  const _AssessmentMetricCard({required this.metric});

  final _AssessmentMetric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon),
            const SizedBox(height: 12),
            Text(
              metric.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              metric.value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
