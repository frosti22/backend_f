import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/checkup_record.dart';
import '../services/api_service.dart';

class CheckupRecordsScreen extends StatefulWidget {
  const CheckupRecordsScreen({super.key});

  @override
  State<CheckupRecordsScreen> createState() => _CheckupRecordsScreenState();
}

class _CheckupRecordsScreenState extends State<CheckupRecordsScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _egfrController = TextEditingController();

  final _creatinineController = TextEditingController();

  final _uacrController = TextEditingController();

  final _systolicController = TextEditingController();

  final _diastolicController = TextEditingController();

  final _glucoseController = TextEditingController();

  final _notesController = TextEditingController();

  DateTime _checkupDate = DateTime.now();

  String? _editingId;

  List<CheckupRecord> _records = const [];

  bool _loading = false;
  bool _saving = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _egfrController.dispose();
    _creatinineController.dispose();
    _uacrController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _glucoseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? _optionalNumber(TextEditingController controller) {
    final text = controller.text.trim();

    return text.isEmpty ? null : double.tryParse(text);
  }

  String _dateValue(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String _displayDate(DateTime date) {
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

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  String _number(double? value) {
    if (value == null) {
      return '—';
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return 'Could not connect to '
        '${ApiConfig.baseUrl}. '
        'Start the Node.js backend and '
        'check the API address.';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _loadRecords() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _connectionError = null;
    });

    try {
      final records = await _api.getCheckupRecords();

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectionError = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _checkupDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (selected != null) {
      setState(() {
        _checkupDate = selected;
      });
    }
  }

  String? _optionalNumberValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return null;
    }

    final number = double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid '
          'non-negative number.';
    }

    return null;
  }

  bool _hasAtLeastOneMeasurement() {
    return <TextEditingController>[
      _egfrController,
      _creatinineController,
      _uacrController,
      _systolicController,
      _diastolicController,
      _glucoseController,
    ].any((controller) => controller.text.trim().isNotEmpty);
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_hasAtLeastOneMeasurement()) {
      _showMessage(
        'Enter at least one '
        'measurement from the '
        'checkup report.',
        error: true,
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final values = <String, double?>{
        'egfr': _optionalNumber(_egfrController),
        'creatinine': _optionalNumber(_creatinineController),
        'uacr': _optionalNumber(_uacrController),
        'systolic': _optionalNumber(_systolicController),
        'diastolic': _optionalNumber(_diastolicController),
        'glucose': _optionalNumber(_glucoseController),
      };

      if (_editingId == null) {
        await _api.addCheckupRecord(
          checkupDate: _dateValue(_checkupDate),
          egfrMlMin173m2: values['egfr'],
          serumCreatinineMgDl: values['creatinine'],
          uacrMgG: values['uacr'],
          systolicBloodPressure: values['systolic'],
          diastolicBloodPressure: values['diastolic'],
          bloodGlucoseMgDl: values['glucose'],
          notes: _notesController.text.trim(),
        );
      } else {
        await _api.updateCheckupRecord(
          id: _editingId!,
          checkupDate: _dateValue(_checkupDate),
          egfrMlMin173m2: values['egfr'],
          serumCreatinineMgDl: values['creatinine'],
          uacrMgG: values['uacr'],
          systolicBloodPressure: values['systolic'],
          diastolicBloodPressure: values['diastolic'],
          bloodGlucoseMgDl: values['glucose'],
          notes: _notesController.text.trim(),
        );
      }

      final wasEditing = _editingId != null;

      _clearForm();
      await _loadRecords();

      _showMessage(
        wasEditing ? 'Checkup record updated.' : 'Checkup record saved.',
      );
    } catch (error) {
      _showMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();

    _egfrController.clear();
    _creatinineController.clear();
    _uacrController.clear();
    _systolicController.clear();
    _diastolicController.clear();
    _glucoseController.clear();
    _notesController.clear();

    setState(() {
      _editingId = null;
      _checkupDate = DateTime.now();
    });
  }

  void _editRecord(CheckupRecord record) {
    _egfrController.text = _numberForInput(record.egfrMlMin173m2);

    _creatinineController.text = _numberForInput(record.serumCreatinineMgDl);

    _uacrController.text = _numberForInput(record.uacrMgG);

    _systolicController.text = _numberForInput(record.systolicBloodPressure);

    _diastolicController.text = _numberForInput(record.diastolicBloodPressure);

    _glucoseController.text = _numberForInput(record.bloodGlucoseMgDl);

    _notesController.text = record.notes ?? '';

    setState(() {
      _editingId = record.id;
      _checkupDate = record.checkupDate;
    });

    final formContext = _formKey.currentContext;

    if (formContext != null) {
      Scrollable.ensureVisible(
        formContext,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  String _numberForInput(double? value) {
    if (value == null) {
      return '';
    }

    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  Future<void> _deleteRecord(CheckupRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete checkup record?'),
        content: Text(
          'Delete the record from '
          '${_displayDate(record.checkupDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _api.deleteCheckupRecord(record.id);

      if (_editingId == record.id) {
        _clearForm();
      }

      await _loadRecords();

      _showMessage('Checkup record deleted.');
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
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'http://192.168.1.10:3000',
          ),
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

    if (value == null || value.isEmpty) {
      return;
    }

    ApiConfig.baseUrl = value.replaceAll(RegExp(r'/$'), '');

    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Periodic Checkup Records'),
        actions: [
          IconButton(
            onPressed: _showApiAddressDialog,
            tooltip: 'Backend address',
            icon: const Icon(Icons.settings_ethernet_rounded),
          ),
          IconButton(
            onPressed: _loading ? null : _loadRecords,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            if (_connectionError != null) _connectionCard(),
            _formCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved records',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_records.isEmpty && !_loading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No checkup records '
                    'saved yet.',
                  ),
                ),
              )
            else
              ..._records.map(_recordCard),
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
        child: Text(_connectionError!),
      ),
    );
  }

  Widget _formCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editingId == null
                    ? 'Add checkup record'
                    : 'Edit checkup record',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter only values shown '
                'on the checkup or laboratory '
                'report. All measurement '
                'fields are optional, but at '
                'least one is required.',
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Checkup date'),
                subtitle: Text(_displayDate(_checkupDate)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: _pickDate,
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Kidney function',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _numberField(
                controller: _egfrController,
                label: 'eGFR',
                unit: 'mL/min/1.73 m²',
              ),
              const SizedBox(height: 12),
              _numberField(
                controller: _creatinineController,
                label: 'Serum creatinine',
                unit: 'mg/dL',
              ),
              const SizedBox(height: 12),
              _numberField(
                controller: _uacrController,
                label: 'UACR',
                unit: 'mg/g',
              ),
              const SizedBox(height: 18),
              Text(
                'Other measurements',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _numberField(
                      controller: _systolicController,
                      label: 'Systolic BP',
                      unit: 'mmHg',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _numberField(
                      controller: _diastolicController,
                      label: 'Diastolic BP',
                      unit: 'mmHg',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _numberField(
                controller: _glucoseController,
                label: 'Blood glucose',
                unit: 'mg/dL',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Notes — optional',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_editingId != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _clearForm,
                        child: const Text('Cancel edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveRecord,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _editingId == null ? 'Save record' : 'Update record',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String unit,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _optionalNumberValidator,
      decoration: InputDecoration(
        labelText: label,

        /*
         * The unit is shown permanently,
         * even before the field is clicked.
         */
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              unit,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Widget _recordCard(CheckupRecord record) {
    final values = <Widget>[
      if (record.egfrMlMin173m2 != null)
        _valueChip(
          'eGFR',
          '${_number(record.egfrMlMin173m2)} '
              'mL/min/1.73 m²',
        ),
      if (record.serumCreatinineMgDl != null)
        _valueChip(
          'Creatinine',
          '${_number(record.serumCreatinineMgDl)} '
              'mg/dL',
        ),
      if (record.uacrMgG != null)
        _valueChip(
          'UACR',
          '${_number(record.uacrMgG)} '
              'mg/g',
        ),
      if (record.systolicBloodPressure != null ||
          record.diastolicBloodPressure != null)
        _valueChip(
          'Blood pressure',
          '${_number(record.systolicBloodPressure)}'
              '/'
              '${_number(record.diastolicBloodPressure)} '
              'mmHg',
        ),
      if (record.bloodGlucoseMgDl != null)
        _valueChip(
          'Blood glucose',
          '${_number(record.bloodGlucoseMgDl)} '
              'mg/dL',
        ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayDate(record.checkupDate),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _editRecord(record),
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  onPressed: () => _deleteRecord(record),
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: values),
            if (record.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(record.notes!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _valueChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label: $value'),
    );
  }
}
