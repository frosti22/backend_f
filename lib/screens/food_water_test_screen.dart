import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/food_log_entry.dart';
import '../models/food_suggestion.dart';
import '../models/water_container.dart';
import '../models/water_log_entry.dart';
import '../services/api_service.dart';
import 'checkup_records_screen.dart';

class FoodWaterTestScreen extends StatefulWidget {
  const FoodWaterTestScreen({super.key});

  @override
  State<FoodWaterTestScreen> createState() => _FoodWaterTestScreenState();
}

class _FoodWaterTestScreenState extends State<FoodWaterTestScreen> {
  static const _mealTypes = <String>[
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'other',
  ];

  final _api = ApiService();
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController(text: '100');

  List<WaterContainer> _waterContainers = const [];

  Timer? _searchDebounce;
  Timer? _nutritionDebounce;

  String _selectedMealType = 'breakfast';
  FoodSuggestion? _selectedFood;
  List<FoodSuggestion> _suggestions = const [];
  Map<String, dynamic>? _nutritionPreview;
  List<FoodLogEntry> _foodLogs = const [];
  List<WaterLogEntry> _waterLogs = const [];
  Map<String, dynamic> _foodSummary = const {};
  Map<String, dynamic> _waterSummary = const {};

  bool _searching = false;
  bool _calculating = false;
  bool _savingFood = false;
  bool _savingWater = false;
  bool _savingContainer = false;
  bool _refreshing = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nutritionDebounce?.cancel();
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  double? _parsePositiveNumber(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return 'Could not connect to ${ApiConfig.baseUrl}. Start the Node.js backend and check the API address.';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _connectionError = null;
    });

    try {
      await _api.checkHealth();
      final results = await Future.wait([
        _api.getFoodLogs(),
        _api.getFoodSummary(),
        _api.getWaterLogs(),
        _api.getWaterSummary(),
        _api.getWaterContainers(),
      ]);

      if (!mounted) return;
      setState(() {
        _foodLogs = results[0] as List<FoodLogEntry>;
        _foodSummary = results[1] as Map<String, dynamic>;
        _waterLogs = results[2] as List<WaterLogEntry>;
        _waterSummary = results[3] as Map<String, dynamic>;
        _waterContainers = results[4] as List<WaterContainer>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _connectionError = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    if (_selectedFood != null && value != _selectedFood!.name) {
      setState(() {
        _selectedFood = null;
        _nutritionPreview = null;
      });
    }

    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      setState(() => _searching = true);
      try {
        final results = await _api.searchFoods(query);
        if (!mounted || _searchController.text.trim() != query) return;
        setState(() {
          _suggestions = results;
          _connectionError = null;
        });
      } catch (error) {
        if (!mounted) return;
        _showMessage(_friendlyError(error), error: true);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectFood(FoodSuggestion food) async {
    setState(() {
      _selectedFood = food;
      _searchController.text = food.name;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
      _suggestions = const [];
    });
    await _calculatePreview();
  }

  void _onQuantityChanged(String _) {
    _nutritionDebounce?.cancel();
    _nutritionDebounce = Timer(
      const Duration(milliseconds: 300),
      _calculatePreview,
    );
  }

  Future<void> _calculatePreview() async {
    final food = _selectedFood;
    final grams = _parsePositiveNumber(_quantityController.text);
    if (food == null || grams == null) {
      setState(() => _nutritionPreview = null);
      return;
    }

    setState(() => _calculating = true);
    try {
      final preview = await _api.calculateNutrition(
        fdcId: food.fdcId,
        consumedGrams: grams,
      );
      if (!mounted || _selectedFood?.fdcId != food.fdcId) return;
      setState(() => _nutritionPreview = preview);
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _addSelectedFood() async {
    final food = _selectedFood;
    final grams = _parsePositiveNumber(_quantityController.text);
    if (food == null) {
      _showMessage('Select a food from the suggestions first.', error: true);
      return;
    }
    if (grams == null) {
      _showMessage('Enter a valid quantity in grams.', error: true);
      return;
    }

    setState(() => _savingFood = true);
    try {
      await _api.addDatasetFood(
        fdcId: food.fdcId,
        consumedGrams: grams,
        mealType: _selectedMealType,
      );
      _searchController.clear();
      _quantityController.text = '100';
      setState(() {
        _selectedFood = null;
        _nutritionPreview = null;
        _suggestions = const [];
      });
      await _refreshAll();
      _showMessage('Food added to ${_label(_selectedMealType)}.');
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingFood = false);
    }
  }

  Future<void> _showManualFoodDialog() async {
    final result = await showDialog<_ManualFoodInput>(
      context: context,
      builder: (context) => _ManualFoodDialog(mealType: _selectedMealType),
    );

    if (result == null) return;

    setState(() => _savingFood = true);
    try {
      await _api.addManualFood(
        name: result.name,
        mealType: _selectedMealType,
        consumedGrams: result.consumedGrams,
        nutrients: result.nutrients,
      );
      await _refreshAll();
      _showMessage('Manual food added to ${_label(_selectedMealType)}.');
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingFood = false);
    }
  }

  Future<void> _showWaterContainerDialog() async {
    final result = await showDialog<_WaterContainerInput>(
      context: context,
      builder: (context) => const _WaterContainerDialog(),
    );

    if (result == null) return;

    setState(() => _savingContainer = true);

    try {
      final container = await _api.saveWaterContainer(
        name: result.name,
        capacityMl: result.capacityMl,
      );

      await _refreshAll();
      _showMessage(
        '${container.name} (${_number(container.capacityMl)} mL) was saved.',
      );
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingContainer = false);
    }
  }

  Future<void> _addWaterFromContainer(WaterContainer container) async {
    if (_savingWater) return;

    setState(() => _savingWater = true);

    try {
      await _api.addWaterFromContainer(container.id);
      await _refreshAll();
      _showMessage(
        '${container.name}: ${_number(container.capacityMl)} mL added.',
      );
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingWater = false);
    }
  }

  Future<void> _deleteFoodLog(FoodLogEntry item) async {
    try {
      await _api.deleteFoodLog(item.id);
      await _refreshAll();
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    }
  }

  Future<void> _deleteWaterLog(WaterLogEntry item) async {
    try {
      await _api.deleteWaterLog(item.id);
      await _refreshAll();
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    }
  }

  Future<void> _showApiAddressDialog() async {
    final controller = TextEditingController(text: ApiConfig.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend API address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://192.168.1.10:3000',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Android emulator: http://10.0.2.2:3000\n'
              'Windows/iOS simulator: http://localhost:3000\n'
              'Physical phone: http://192.168.0.72:3000',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null || value.isEmpty) return;
    ApiConfig.baseUrl = value.replaceAll(RegExp(r'/$'), '');
    await _refreshAll();
  }

  String _label(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _number(dynamic value, {int decimals = 1}) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) return '—';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(decimals);
  }

  bool _hasNutrient(Map<String, dynamic> nutrients, String key) {
    final value = nutrients[key];

    if (value == null || value == '') return false;

    final number = value is num
        ? value.toDouble()
        : double.tryParse(value.toString());

    return number != null && number.isFinite;
  }

  String _time(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food & Water Test'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CheckupRecordsScreen(),
                ),
              );
            },
            tooltip: 'Periodic checkups',
            icon: const Icon(Icons.medical_information_outlined),
          ),
          IconButton(
            onPressed: _showApiAddressDialog,
            tooltip: 'Backend address',
            icon: const Icon(Icons.settings_ethernet_rounded),
          ),
          IconButton(
            onPressed: _refreshing ? null : _refreshAll,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            if (_connectionError != null) _connectionCard(),
            _sectionTitle('Food log', 'Search, calculate, and add meals'),
            _mealSelector(),
            const SizedBox(height: 12),
            _foodSearchCard(),
            const SizedBox(height: 20),
            _nutritionSummaryCard(),
            const SizedBox(height: 12),
            _foodLogList(),
            const SizedBox(height: 28),
            _sectionTitle('Water intake', 'Manual entries only'),
            _waterCard(),
            const SizedBox(height: 12),
            _waterLogList(),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(_connectionError!)),
            TextButton(
              onPressed: _showApiAddressDialog,
              child: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _mealSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _mealTypes.map((meal) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_label(meal)),
              selected: _selectedMealType == meal,
              onSelected: (_) => setState(() => _selectedMealType = meal),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _foodSearchCard() {
    final calculated = Map<String, dynamic>.from(
      _nutritionPreview?['calculatedNutrients'] as Map? ??
          const <String, dynamic>{},
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                labelText: 'Search food',
                hintText: 'Type a food name, such as apple',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _selectedFood = null;
                                  _suggestions = const [];
                                  _nutritionPreview = null;
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null),
              ),
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final food = _suggestions[index];
                    final nutrients = food.nutrientsPer100g;
                    final optionalNutrients = <String>[];

                    if (_hasNutrient(nutrients, 'carbohydratesG')) {
                      optionalNutrients.add(
                        'Carbs: ${_number(nutrients['carbohydratesG'])} g',
                      );
                    }

                    if (_hasNutrient(nutrients, 'potassiumMg')) {
                      optionalNutrients.add(
                        'Potassium: ${_number(nutrients['potassiumMg'])} mg',
                      );
                    }

                    return ListTile(
                      title: Text(
                        food.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'Calories: ${_number(nutrients['energyKcal'])} kcal'
                            ' • Sodium: ${_number(nutrients['sodiumMg'])} mg',
                          ),
                          if (optionalNutrients.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(optionalNutrients.join(' • ')),
                          ],
                          const SizedBox(height: 2),
                          const Text(
                            'Values per 100 g',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.north_west_rounded, size: 18),
                      onTap: () => _selectFood(food),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    onChanged: _onQuantityChanged,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      suffixText: 'g',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _savingFood ? null : _addSelectedFood,
                    icon: _savingFood
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text('Add to ${_label(_selectedMealType)}'),
                  ),
                ),
              ],
            ),
            if (_selectedFood != null) ...[
              const SizedBox(height: 14),
              Text(
                _selectedFood!.name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (_calculating)
                const LinearProgressIndicator()
              else if (_nutritionPreview != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _nutrientPill('Calories', calculated['energyKcal'], 'kcal'),
                    _nutrientPill('Sodium', calculated['sodiumMg'], 'mg'),
                    if (_hasNutrient(calculated, 'carbohydratesG'))
                      _nutrientPill('Carbs', calculated['carbohydratesG'], 'g'),
                    if (_hasNutrient(calculated, 'potassiumMg'))
                      _nutrientPill(
                        'Potassium',
                        calculated['potassiumMg'],
                        'mg',
                      ),
                    if (_hasNutrient(calculated, 'proteinG'))
                      _nutrientPill('Protein', calculated['proteinG'], 'g'),
                    if (_hasNutrient(calculated, 'fatG'))
                      _nutrientPill('Fat', calculated['fatG'], 'g'),
                  ],
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _savingFood ? null : _showManualFoodDialog,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Food not found? Add manually'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutrientPill(String label, dynamic value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text('$label: ${_number(value)} $unit'),
    );
  }

  Widget _nutritionSummaryCard() {
    final totals = Map<String, dynamic>.from(
      _foodSummary['totals'] as Map? ?? const <String, dynamic>{},
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved nutrition total',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryTile('Calories', totals['energyKcal'], 'kcal'),
                _summaryTile('Sodium', totals['sodiumMg'], 'mg'),
                if (_hasNutrient(totals, 'carbohydratesG'))
                  _summaryTile('Carbs', totals['carbohydratesG'], 'g'),
                if (_hasNutrient(totals, 'potassiumMg'))
                  _summaryTile('Potassium', totals['potassiumMg'], 'mg'),
                if (_hasNutrient(totals, 'proteinG'))
                  _summaryTile('Protein', totals['proteinG'], 'g'),
                if (_hasNutrient(totals, 'fatG'))
                  _summaryTile('Fat', totals['fatG'], 'g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String label, dynamic value, String unit) {
    return Container(
      width: 142,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            '${_number(value)} $unit',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _foodLogList() {
    if (_foodLogs.isEmpty) {
      return const _EmptyCard(message: 'No saved food records yet.');
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < _foodLogs.length; index++) ...[
            _foodLogTile(_foodLogs[index]),
            if (index != _foodLogs.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _foodLogTile(FoodLogEntry item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(child: Text(_label(item.mealType)[0])),
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_label(item.mealType)} • ${_number(item.consumedGrams)} g • '
        '${_number(item.nutrients['energyKcal'])} kcal • ${_time(item.consumedAt)}',
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: () => _deleteFoodLog(item),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }

  Widget _waterCard() {
    final total = _waterSummary['totalMl'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_number(total)} mL',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Text(
              'Saved water total',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reusable containers',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _savingContainer
                      ? null
                      : _showWaterContainerDialog,
                  icon: _savingContainer
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_waterContainers.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'No container saved yet. Tap New and enter a name and '
                  'capacity, such as Blue Tumbler — 750 mL.',
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _waterContainers.map((container) {
                  return FilledButton.tonalIcon(
                    onPressed: _savingWater
                        ? null
                        : () => _addWaterFromContainer(container),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: Text(
                      '${container.name}\n${_number(container.capacityMl)} mL',
                      textAlign: TextAlign.center,
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            const Text(
              'Tap a saved container to add its full capacity to the water log.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waterLogList() {
    if (_waterLogs.isEmpty) {
      return const _EmptyCard(message: 'No saved water entries yet.');
    }

    return Card(
      child: Column(
        children: [
          for (var index = 0; index < _waterLogs.length; index++) ...[
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.water_drop_rounded),
              ),
              title: Text(
                _waterLogs[index].containerName?.trim().isNotEmpty == true
                    ? _waterLogs[index].containerName!
                    : 'Water',
              ),
              subtitle: Text(
                '${_number(_waterLogs[index].amountMl)} mL'
                ' • ${_time(_waterLogs[index].loggedAt)}',
              ),
              trailing: IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteWaterLog(_waterLogs[index]),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
            if (index != _waterLogs.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ManualFoodInput {
  const _ManualFoodInput({
    required this.name,
    required this.consumedGrams,
    required this.nutrients,
  });

  final String name;
  final double consumedGrams;
  final Map<String, double?> nutrients;
}

class _ManualFoodDialog extends StatefulWidget {
  const _ManualFoodDialog({required this.mealType});

  final String mealType;

  @override
  State<_ManualFoodDialog> createState() => _ManualFoodDialogState();
}

class _ManualFoodDialogState extends State<_ManualFoodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _grams = TextEditingController(text: '100');
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _sodium = TextEditingController();
  final _potassium = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      _name,
      _grams,
      _calories,
      _protein,
      _carbs,
      _fat,
      _sodium,
      _potassium,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _nullableNumber(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final nutrients = <String, double?>{
      'energyKcal': _nullableNumber(_calories),
      'proteinG': _nullableNumber(_protein),
      'carbohydratesG': _nullableNumber(_carbs),
      'fatG': _nullableNumber(_fat),
      'sodiumMg': _nullableNumber(_sodium),
      'potassiumMg': _nullableNumber(_potassium),
    };

    if (nutrients.values.every((value) => value == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one nutrient value.')),
      );
      return;
    }

    Navigator.pop(
      context,
      _ManualFoodInput(
        name: _name.text.trim(),
        consumedGrams: double.parse(_grams.text.trim()),
        nutrients: nutrients,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Manual ${widget.mealType} food'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Food name'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Enter the food name.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _grams,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    suffixText: 'g',
                  ),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    return number == null || number <= 0
                        ? 'Enter a valid quantity.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nutrients for the full quantity entered',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                _numberField(_calories, 'Calories', 'kcal'),
                _numberField(_protein, 'Protein', 'g'),
                _numberField(_carbs, 'Carbohydrates', 'g'),
                _numberField(_fat, 'Fat', 'g'),
                _numberField(_sodium, 'Sodium', 'mg'),
                _numberField(_potassium, 'Potassium', 'mg'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add food')),
      ],
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: unit),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return null;
          final number = double.tryParse(value.trim());
          return number == null || number < 0
              ? 'Use zero or a positive number.'
              : null;
        },
      ),
    );
  }
}

class _WaterContainerInput {
  const _WaterContainerInput({required this.name, required this.capacityMl});

  final String name;
  final double capacityMl;
}

class _WaterContainerDialog extends StatefulWidget {
  const _WaterContainerDialog();

  @override
  State<_WaterContainerDialog> createState() => _WaterContainerDialogState();
}

class _WaterContainerDialogState extends State<_WaterContainerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _WaterContainerInput(
        name: _nameController.text.trim(),
        capacityMl: double.parse(_capacityController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save water container'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Container name',
                hintText: 'Example: Blue tumbler',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 2) return 'Enter a container name.';
                if (text.length > 80) {
                  return 'Use 80 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Capacity',
                suffixText: 'mL',
                hintText: 'Example: 750',
              ),
              validator: (value) {
                final number = double.tryParse(value?.trim() ?? '');
                if (number == null || number <= 0 || number > 10000) {
                  return 'Enter a capacity from 1 to 10,000 mL.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save container')),
      ],
    );
  }
}
