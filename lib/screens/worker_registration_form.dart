import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/auth_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Admin creates a new worker with full personal, employment, and bank details.
// All required fields are validated before submission.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerRegistrationForm extends StatefulWidget {
  /// If provided, pre-populates the form for editing an existing worker.
  final Worker? existingWorker;

  const WorkerRegistrationForm({super.key, this.existingWorker});

  @override
  State<WorkerRegistrationForm> createState() => _WorkerRegistrationFormState();
}

class _WorkerRegistrationFormState extends State<WorkerRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _store = WorkerDataStore();
  bool _isSaving = false;

  // ── Personal Info ──────────────────────────────────────────────────────────
  final _fullNameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  final _nisCtrl = TextEditingController();
  final _birCtrl = TextEditingController();
  final _driverPermitCtrl = TextEditingController();
  final _passportCtrl = TextEditingController();
  DateTime? _dateOfBirth;

  // ── Employment ─────────────────────────────────────────────────────────────
  String? _selectedCorporationId;
  String? _selectedCorporationName;
  String? _selectedDistrict;
  String? _selectedPosition;
  DateTime? _startDate;
  DateTime? _endDate;
  final _referenceNumberCtrl = TextEditingController();
  final _wageRateCtrl = TextEditingController(text: '150.00');
  // COLA is optional — leave blank or 0 to skip; can be set later from
  // the worker detail screen.
  final _colaRateCtrl = TextEditingController();
  final _allowanceRateCtrl = TextEditingController(text: '40.00');

  // ── Bank Info ──────────────────────────────────────────────────────────────
  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  // ── Reference Data ─────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _corporations = [
    {'id': '1', 'name': 'Arima Borough Corporation', 'districts': ['Arima North', 'Arima South', 'Arima Central']},
    {'id': '2', 'name': 'Chaguanas Borough Corporation', 'districts': ['Chaguanas East', 'Chaguanas West', 'Chaguanas North', 'Chaguanas South', 'Charlieville']},
    {'id': '3', 'name': 'San Fernando City Corporation', 'districts': ['San Fernando East', 'San Fernando West']},
    {'id': '4', 'name': 'Diego Martin Regional Corporation', 'districts': ['Diego Martin North', 'Diego Martin Central', 'Petit Valley']},
    {'id': '5', 'name': 'Mayaro-Rio Claro Regional Corporation', 'districts': ['Mayaro', 'Rio Claro', 'Biche']},
    {'id': '6', 'name': 'Penal-Debe Regional Corporation', 'districts': ['Penal', 'Debe', 'Barrackpore']},
    {'id': '7', 'name': 'Point Fortin Borough Corporation', 'districts': ['Point Fortin North', 'Point Fortin South']},
    {'id': '8', 'name': 'Port of Spain City Corporation', 'districts': ['Port of Spain North', 'Port of Spain South', 'Port of Spain East', 'Port of Spain West', 'Laventille', 'Morvant']},
    {'id': '9', 'name': 'Princes Town Regional Corporation', 'districts': ['Princes Town', 'Moruga', 'Tableland']},
    {'id': '10', 'name': 'Couva-Tabaquite-Talparo Regional Corporation', 'districts': ['Couva North', 'Couva South', 'Tabaquite', 'Talparo']},
    {'id': '11', 'name': 'San Juan-Laventille Regional Corporation', 'districts': ['San Juan', 'Barataria', 'El Socorro']},
    {'id': '12', 'name': 'Sangre Grande Regional Corporation', 'districts': ['Sangre Grande', 'Toco', 'Matura']},
    {'id': '13', 'name': 'Siparia Regional Corporation', 'districts': ['Siparia', 'Fyzabad', 'Oropouche']},
    {'id': '14', 'name': 'Tunapuna-Piarco Regional Corporation', 'districts': ['Tunapuna', 'Piarco', 'St. Augustine', 'Curepe']},
  ];

  static const List<String> _positions = [
    'General Worker',
    'Drain Cleaner',
    'Street Cleaner',
    'Landscaper',
    'Road Maintenance',
    'Supervisor',
    'Driver',
    'Security Officer',
    'Groundskeeper',
    'Maintenance Technician',
  ];

  static const List<String> _banks = [
    'Republic Bank',
    'First Citizens Bank',
    'Scotiabank',
    'JMMB Bank',
    'RBC Royal Bank',
    'Citibank',
    'Unit Trust Corporation',
  ];

  bool get _isEditing => widget.existingWorker != null;

  List<String> get _availableDistricts {
    if (_selectedCorporationId == null) return [];
    final corp = _corporations.firstWhere(
      (c) => c['id'] == _selectedCorporationId,
      orElse: () => {'districts': <String>[]},
    );
    return List<String>.from(corp['districts'] as List);
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFromWorker(widget.existingWorker!);
    }
  }

  void _populateFromWorker(Worker w) {
    _fullNameCtrl.text = w.fullName;
    _contactCtrl.text = w.contact ?? '';
    _addressCtrl.text = w.address ?? '';
    _idNumberCtrl.text = w.idNumber;
    _nisCtrl.text = w.nisNumber;
    _birCtrl.text = w.birNumber ?? '';
    _driverPermitCtrl.text = w.driverPermitNumber ?? '';
    _passportCtrl.text = w.passportNumber ?? '';
    _dateOfBirth = w.dateOfBirth;
    _selectedCorporationId = w.corporationId;
    _selectedCorporationName = w.corporationName;
    _selectedDistrict = w.electoralDistrict;
    _selectedPosition = w.position;
    _startDate = w.startDate;
    _endDate = w.endDate;
    _referenceNumberCtrl.text = w.referenceNumber ?? '';
    _wageRateCtrl.text = w.wageRate.toStringAsFixed(2);
    _colaRateCtrl.text = w.colaRate > 0 ? w.colaRate.toStringAsFixed(2) : '';
    _allowanceRateCtrl.text = w.allowanceRate.toStringAsFixed(2);
    _bankNameCtrl.text = w.bankInfo.bankName;
    _accountNumberCtrl.text = w.bankInfo.accountNumber;
    _branchCtrl.text = w.bankInfo.branchName;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    _idNumberCtrl.dispose();
    _nisCtrl.dispose();
    _birCtrl.dispose();
    _driverPermitCtrl.dispose();
    _passportCtrl.dispose();
    _referenceNumberCtrl.dispose();
    _wageRateCtrl.dispose();
    _colaRateCtrl.dispose();
    _allowanceRateCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, {required bool isDob, bool isEndDate = false}) async {
    final initial = isDob
        ? (_dateOfBirth ?? DateTime(1990))
        : isEndDate
            ? (_endDate ?? DateTime.now())
            : (_startDate ?? DateTime.now());

    final first = isDob ? DateTime(1950) : DateTime(2020);
    final last = isDob ? DateTime.now().subtract(const Duration(days: 365 * 16)) : DateTime(2035);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isDob) {
          _dateOfBirth = picked;
        } else if (isEndDate) {
          _endDate = picked;
        } else {
          _startDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      _showError('Please select a date of birth.');
      return;
    }
    if (_startDate == null) {
      _showError('Please select a start date.');
      return;
    }

    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final documents = {
      for (final name in Worker.requiredDocumentNames)
        name: WorkerDocument(name: name),
    };

    if (_isEditing) {
      for (final entry in widget.existingWorker!.documents.entries) {
        documents[entry.key] = entry.value;
      }
    }

    final worker = Worker(
      id: _isEditing ? widget.existingWorker!.id : _store.generateWorkerId(),
      fullName: _fullNameCtrl.text.trim(),
      nisNumber: _nisCtrl.text.trim(),
      dateOfBirth: _dateOfBirth!,
      position: _selectedPosition!,
      idNumber: _idNumberCtrl.text.trim(),
      corporationId: _selectedCorporationId!,
      corporationName: _selectedCorporationName!,
      electoralDistrict: _selectedDistrict!,
      wageRate: double.tryParse(_wageRateCtrl.text) ?? 150.0,
      colaRate: double.tryParse(_colaRateCtrl.text) ?? 0.0,
      allowanceRate: double.tryParse(_allowanceRateCtrl.text) ?? 40.0,
      bankInfo: BankInfo(
        bankName: _bankNameCtrl.text.trim(),
        accountNumber: _accountNumberCtrl.text.trim(),
        branchName: _branchCtrl.text.trim(),
      ),
      documents: documents,
      dateRegistered: _isEditing ? widget.existingWorker!.dateRegistered : DateTime.now(),
      customAllowances: _isEditing ? widget.existingWorker!.customAllowances : null,
      contact: _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      birNumber: _birCtrl.text.trim().isEmpty ? null : _birCtrl.text.trim(),
      driverPermitNumber: _driverPermitCtrl.text.trim().isEmpty ? null : _driverPermitCtrl.text.trim(),
      passportNumber: _passportCtrl.text.trim().isEmpty ? null : _passportCtrl.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      referenceNumber: _referenceNumberCtrl.text.trim().isEmpty ? null : _referenceNumberCtrl.text.trim(),
    );

    // ── Uniqueness check ───────────────────────────────────────────────────
    final conflicts = _store.checkUniqueIds(
      worker,
      excludeId: _isEditing ? widget.existingWorker!.id : null,
    );

    if (conflicts.isNotEmpty) {
      final actor = AuthService().currentUser;
      if (actor != null) {
        _store.logDuplicateIdAttempt(actor: actor, candidate: worker, conflicts: conflicts);
      }
      setState(() => _isSaving = false);
      if (!mounted) return;
      await _showDuplicateConflictDialog(conflicts);
      return;
    }

    if (_isEditing) {
      _store.updateWorker(worker);
    } else {
      _store.addWorker(worker);
    }

    setState(() => _isSaving = false);

    if (!mounted) return;
    Navigator.of(context).pop(true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? 'Worker updated successfully.' : 'Worker registered: ${worker.fullName}'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _showDuplicateConflictDialog(List<DuplicateIdConflict> conflicts) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Flexible(child: Text('Duplicate Credential Detected', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This registration was blocked because the following credential(s) are already registered to another worker. This attempt has been recorded in the audit log.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            ...conflicts.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.fieldName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.error),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Already registered to: ${c.conflictingWorkerName} (${c.conflictingWorkerId})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          _isEditing ? 'Edit Worker' : 'Register New Worker',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.white, size: 18),
              label: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Personal Information', Icons.person),
            const SizedBox(height: 12),
            _textField(
              controller: _fullNameCtrl,
              label: 'Full Name',
              hint: 'e.g. Kevin Rampersad',
              required: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            _datePicker(
              label: 'Date of Birth',
              value: _dateOfBirth,
              onTap: () => _pickDate(context, isDob: true),
              required: true,
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _idNumberCtrl,
              label: 'National ID Number',
              hint: 'e.g. ID-TT-199001010',
              required: true,
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _nisCtrl,
              label: 'NIS Number',
              hint: 'e.g. NIS-2024-00147',
              required: true,
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _birCtrl,
              label: 'BIR Number',
              hint: 'e.g. BIR-2024-00147',
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _driverPermitCtrl,
              label: "Driver's Permit Number",
              hint: 'e.g. DP-2024-00147',
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _passportCtrl,
              label: 'Passport Number',
              hint: 'e.g. TT123456',
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _contactCtrl,
              label: 'Contact Number',
              hint: 'e.g. 868-555-0101',
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\-\+\(\) ]'))],
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _addressCtrl,
              label: 'Home Address',
              hint: 'e.g. 14 Cipero Street, Port of Spain',
              maxLines: 2,
            ),

            const SizedBox(height: 24),
            _sectionHeader('Employment Details', Icons.work),
            const SizedBox(height: 12),

            // Corporation dropdown
            _dropdownField<String>(
              label: 'Corporation',
              value: _selectedCorporationName,
              items: _corporations.map((c) => c['name'] as String).toList(),
              onChanged: (val) {
                final corp = _corporations.firstWhere((c) => c['name'] == val);
                setState(() {
                  _selectedCorporationId = corp['id'] as String;
                  _selectedCorporationName = val;
                  _selectedDistrict = null;
                });
              },
              required: true,
            ),
            const SizedBox(height: 12),

            // Electoral District
            _dropdownField<String>(
              label: 'Electoral District',
              value: _selectedDistrict,
              items: _availableDistricts,
              onChanged: _selectedCorporationId == null ? null : (val) => setState(() => _selectedDistrict = val),
              required: true,
              disabled: _selectedCorporationId == null,
            ),
            const SizedBox(height: 12),

            // Position
            _dropdownField<String>(
              label: 'Position',
              value: _selectedPosition,
              items: _positions,
              onChanged: (val) => setState(() => _selectedPosition = val),
              required: true,
            ),
            const SizedBox(height: 12),

            _datePicker(
              label: 'Start Date',
              value: _startDate,
              onTap: () => _pickDate(context, isDob: false),
              required: true,
            ),
            const SizedBox(height: 12),
            _datePicker(
              label: 'End Date (if applicable)',
              value: _endDate,
              onTap: () => _pickDate(context, isDob: false, isEndDate: true),
            ),
            const SizedBox(height: 12),

            _textField(
              controller: _referenceNumberCtrl,
              label: 'EmployTT Reference Number',
              hint: 'e.g. ETT-2024-00147',
              helperText: 'Obtain this reference number from the EmployTT system before registering the worker.',
            ),
            const SizedBox(height: 12),

            // Rates row
            Row(
              children: [
                Expanded(child: _textField(
                  controller: _wageRateCtrl,
                  label: 'Wage Rate (\$/day)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  required: true,
                )),
                const SizedBox(width: 8),
                Expanded(child: _textField(
                  controller: _colaRateCtrl,
                  label: 'COLA Rate (\$/day, optional)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  required: false,
                )),
                const SizedBox(width: 8),
                Expanded(child: _textField(
                  controller: _allowanceRateCtrl,
                  label: 'Allowance (\$/day)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  required: true,
                )),
              ],
            ),

            const SizedBox(height: 24),
            _sectionHeader('Bank Information', Icons.account_balance),
            const SizedBox(height: 12),

            _dropdownField<String>(
              label: 'Bank Name',
              value: _bankNameCtrl.text.isEmpty ? null : _bankNameCtrl.text,
              items: _banks,
              onChanged: (val) => setState(() => _bankNameCtrl.text = val ?? ''),
              required: true,
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _accountNumberCtrl,
              label: 'Account Number',
              hint: 'e.g. 1102-4587-6321',
              required: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\-]'))],
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _branchCtrl,
              label: 'Branch Name',
              hint: 'e.g. Independence Square',
              required: true,
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _isSaving ? 'Saving...' : (_isEditing ? 'Update Worker' : 'Register Worker'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
    bool required = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 3,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'This field is required.' : null
          : null,
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?>? onChanged,
    bool required = false,
    bool disabled = false,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        filled: true,
        fillColor: disabled ? AppColors.inputFill : AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      items: items.map((item) => DropdownMenuItem<T>(value: item, child: Text(item.toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: disabled ? null : onChanged,
      validator: required ? (v) => v == null ? 'Please select an option.' : null : null,
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    bool required = false,
  }) {
    final fmt = DateFormat('d MMMM yyyy');
    final displayText = value != null ? fmt.format(value) : '';
    return GestureDetector(
      onTap: onTap,
      child: AbsorbPointer(
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            suffixIcon: const Icon(Icons.calendar_today, size: 18, color: AppColors.accent),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            errorText: (required && value == null) ? 'Please select a date.' : null,
          ),
          child: Text(
            displayText.isEmpty ? 'Tap to select date' : displayText,
            style: TextStyle(
              fontSize: 14,
              color: displayText.isEmpty ? AppColors.textHint : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
