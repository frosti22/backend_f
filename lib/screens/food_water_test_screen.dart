import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/food_log_entry.dart';
import '../models/food_suggestion.dart';
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
  final _customWaterController = TextEditingController(text: '250');

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
    _customWaterController.dispose();
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
      ]);

      if (!mounted) return;
      setState(() {
        _foodLogs = results[0] as List<FoodLogEntry>;
        _foodSummary = results[1] as Map<String, dynamic>;
        _waterLogs = results[2] as List<WaterLogEntry>;
        _waterSummary = results[3] as Map<String, dynamic>;
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

  Future<void> _addWater(double amountMl) async {
    if (_savingWater) return;
    setState(() => _savingWater = true);
    try {
      await _api.addWater(amountMl);
      await _refreshAll();
      _showMessage('${_number(amountMl)} mL water added.');
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _savingWater = false);
    }
  }

  Future<void> _addCustomWater() async {
    final amount = _parsePositiveNumber(_customWaterController.text);
    if (amount == null || amount > 10000) {
      _showMessage('Enter a water amount from 1 to 10,000 mL.', error: true);
      return;
    }
    await _addWater(amount);
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
              'Physical phone: use your computer LAN IP.',
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
                    final kcal = food.nutrientsPer100g['energyKcal'];
                    return ListTile(
                      title: Text(
                        food.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: kcal == null
                          ? null
                          : Text('${_number(kcal)} kcal per 100 g'),
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
                    _nutrientPill('Protein', calculated['proteinG'], 'g'),
                    _nutrientPill('Carbs', calculated['carbohydratesG'], 'g'),
                    _nutrientPill('Fat', calculated['fatG'], 'g'),
                    _nutrientPill('Sodium', calculated['sodiumMg'], 'mg'),
                    _nutrientPill('Potassium', calculated['potassiumMg'], 'mg'),
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
              'Session nutrition total',
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
                _summaryTile('Protein', totals['proteinG'], 'g'),
                _summaryTile('Sodium', totals['sodiumMg'], 'mg'),
                _summaryTile('Potassium', totals['potassiumMg'], 'mg'),
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
      return const _EmptyCard(
        message: 'No food records in this backend session yet.',
      );
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
              'Session water total',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [250, 350, 500].map((amount) {
                return FilledButton.tonal(
                  onPressed: _savingWater
                      ? null
                      : () => _addWater(amount.toDouble()),
                  child: Text('+$amount mL'),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customWaterController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Custom amount',
                      suffixText: 'mL',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _savingWater ? null : _addCustomWater,
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Add water'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _waterLogList() {
    if (_waterLogs.isEmpty) {
      return const _EmptyCard(
        message: 'No water entries in this backend session yet.',
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < _waterLogs.length; index++) ...[
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.water_drop_rounded),
              ),
              title: Text('${_number(_waterLogs[index].amountMl)} mL'),
              subtitle: Text(
                'Manual entry • ${_time(_waterLogs[index].loggedAt)}',
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
