import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Timesheet Entry Screen
// Digitizes the paper timesheet template (template.xlsx) for Regional Coordinators
// Implements §5.4 Digital Timesheet, §6 Timesheet Data Collection, §7 Wireframe
//
// Tech: Flutter + Supabase (replace mock data with Supabase client calls)
// ──────────────────────────────────────────────────────────────────────────────

// ── DATA MODELS ──────────────────────────────────────────────────────────────

class Corporation {
  final String id;
  final String name;
  final List<String> electoralDistricts;
  Corporation({required this.id, required this.name, required this.electoralDistricts});
}

class RegisteredWorker {
  final String id;
  final String name;
  final String position;
  final String idNumber;
  final String nisNumber;
  final double wageRate;
  final double colaRate;
  final double allowanceRate;
  RegisteredWorker({
    required this.id,
    required this.name,
    required this.position,
    required this.idNumber,
    required this.nisNumber,
    required this.wageRate,
    required this.colaRate,
    required this.allowanceRate,
  });
}

class DailyAttendance {
  TimeOfDay? timeIn;
  TimeOfDay? timeOut;
  DailyAttendance({this.timeIn, this.timeOut});
  bool get isPresent => timeIn != null && timeOut != null;
}

class WorkerTimesheetEntry {
  RegisteredWorker? worker;
  List<DailyAttendance> attendance;
  int allowanceDays;
  String remarks;

  WorkerTimesheetEntry()
      : attendance = List.generate(14, (_) => DailyAttendance()),
        allowanceDays = 0,
        remarks = '';

  int get daysWorked => attendance.where((d) => d.isPresent).length;
  double get wageTotal => worker != null ? daysWorked * worker!.wageRate : 0;
  double get colaTotal => worker != null ? daysWorked * worker!.colaRate : 0;
  double get allowanceTotal => worker != null ? allowanceDays * worker!.allowanceRate : 0;
  double get grandTotal => wageTotal + colaTotal + allowanceTotal;
}

// ── TIMESHEET SCREEN ─────────────────────────────────────────────────────────

class TimesheetEntryScreen extends StatefulWidget {
  const TimesheetEntryScreen({super.key});

  @override
  State<TimesheetEntryScreen> createState() => _TimesheetEntryScreenState();
}

class _TimesheetEntryScreenState extends State<TimesheetEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Header fields
  Corporation? _selectedCorporation;
  String? _selectedDistrict;
  String _groupNumber = '';
  DateTime? _fortnightStart;
  DateTime? _fortnightEnd;

  // Worker entries (up to 12 per template — §6.2)
  final List<WorkerTimesheetEntry> _workerEntries = [WorkerTimesheetEntry()];

  // Submission state
  bool _isSubmitting = false;
  bool _isSupervisorConfirmed = false;

  // Entrance animation
  late final AnimationController _entranceController;

  // ── Mock data (replace with Supabase queries) ──────────────────────────────
  final List<Corporation> _corporations = [
    Corporation(id: '1', name: 'Arima Borough Corporation', electoralDistricts: ['Arima North', 'Arima South', 'Arima Central']),
    Corporation(id: '2', name: 'Chaguanas Borough Corporation', electoralDistricts: ['Chaguanas East', 'Chaguanas West', 'Charlieville']),
    Corporation(id: '3', name: 'Couva-Tabaquite-Talparo Regional Corporation', electoralDistricts: ['Couva North', 'Couva South', 'Tabaquite', 'Talparo']),
    Corporation(id: '4', name: 'Diego Martin Regional Corporation', electoralDistricts: ['Diego Martin North', 'Diego Martin Central', 'Petit Valley']),
    Corporation(id: '5', name: 'Mayaro-Rio Claro Regional Corporation', electoralDistricts: ['Mayaro', 'Rio Claro', 'Biche']),
    Corporation(id: '6', name: 'Penal-Debe Regional Corporation', electoralDistricts: ['Penal', 'Debe', 'Barrackpore']),
    Corporation(id: '7', name: 'Point Fortin Borough Corporation', electoralDistricts: ['Point Fortin North', 'Point Fortin South']),
    Corporation(id: '8', name: 'Port of Spain City Corporation', electoralDistricts: ['Port of Spain North', 'Port of Spain South', 'Laventille', 'Morvant']),
    Corporation(id: '9', name: 'Princes Town Regional Corporation', electoralDistricts: ['Princes Town', 'Moruga', 'Tableland']),
    Corporation(id: '10', name: 'San Fernando City Corporation', electoralDistricts: ['San Fernando East', 'San Fernando West']),
    Corporation(id: '11', name: 'San Juan-Laventille Regional Corporation', electoralDistricts: ['San Juan', 'Barataria', 'El Socorro']),
    Corporation(id: '12', name: 'Sangre Grande Regional Corporation', electoralDistricts: ['Sangre Grande', 'Toco', 'Matura']),
    Corporation(id: '13', name: 'Siparia Regional Corporation', electoralDistricts: ['Siparia', 'Fyzabad', 'Oropouche']),
    Corporation(id: '14', name: 'Tunapuna-Piarco Regional Corporation', electoralDistricts: ['Tunapuna', 'Piarco', 'St. Augustine', 'Curepe']),
  ];

  final List<RegisteredWorker> _registeredWorkers = [
    RegisteredWorker(id: 'W001', name: 'John Baptiste', position: 'General Worker', idNumber: 'TT-198504123', nisNumber: '***-***-4567', wageRate: 150.0, colaRate: 25.0, allowanceRate: 20.0),
    RegisteredWorker(id: 'W002', name: 'Maria Gonzales', position: 'Maintenance Worker', idNumber: 'TT-199201456', nisNumber: '***-***-7891', wageRate: 150.0, colaRate: 25.0, allowanceRate: 20.0),
    RegisteredWorker(id: 'W003', name: 'Kevin Rampersad', position: 'General Worker', idNumber: 'TT-198809789', nisNumber: '***-***-2345', wageRate: 150.0, colaRate: 25.0, allowanceRate: 20.0),
    RegisteredWorker(id: 'W004', name: 'Sasha Mohammed', position: 'Supervisor', idNumber: 'TT-199505234', nisNumber: '***-***-6789', wageRate: 200.0, colaRate: 30.0, allowanceRate: 25.0),
    RegisteredWorker(id: 'W005', name: 'David Charles', position: 'General Worker', idNumber: 'TT-199107567', nisNumber: '***-***-0123', wageRate: 150.0, colaRate: 25.0, allowanceRate: 20.0),
  ];

  final List<String> _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  String _formatCurrency(double amount) => '\$${amount.toStringAsFixed(2)}';

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _addWorkerEntry() {
    if (_workerEntries.length < 12) {
      setState(() => _workerEntries.add(WorkerTimesheetEntry()));
    }
  }

  void _removeWorkerEntry(int index) {
    if (_workerEntries.length > 1) {
      setState(() => _workerEntries.removeAt(index));
    }
  }

  Future<void> _selectFortnightStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: NpupsColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: NpupsColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _fortnightStart = picked;
        _fortnightEnd = picked.add(const Duration(days: 13));
      });
    }
  }

  Future<void> _pickTime(WorkerTimesheetEntry entry, int dayIndex, bool isTimeIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isTimeIn
          ? (entry.attendance[dayIndex].timeIn ?? const TimeOfDay(hour: 7, minute: 0))
          : (entry.attendance[dayIndex].timeOut ?? const TimeOfDay(hour: 15, minute: 0)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: NpupsColors.primary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isTimeIn) {
          entry.attendance[dayIndex].timeIn = picked;
        } else {
          entry.attendance[dayIndex].timeOut = picked;
        }
      });
    }
  }

  void _quickFillWeekday(WorkerTimesheetEntry entry) {
    setState(() {
      for (int i = 0; i < 14; i++) {
        if ((i % 7) < 5) {
          entry.attendance[i].timeIn = const TimeOfDay(hour: 7, minute: 0);
          entry.attendance[i].timeOut = const TimeOfDay(hour: 15, minute: 0);
        }
      }
    });
  }

  Future<void> _submitTimesheet() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isSupervisorConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maintenance Supervisor confirmation required'), backgroundColor: NpupsColors.error),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    // TODO: Replace with Supabase insert
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isSubmitting = false);
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: NpupsColors.success, size: 28),
              SizedBox(width: 8),
              Text('Timesheet Submitted'),
            ],
          ),
          content: const Text('Your timesheet has been submitted successfully. DMCR and HR have been notified.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: NpupsColors.primary)),
            ),
          ],
        ),
      );
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NpupsColors.surface,
      appBar: AppBar(
        backgroundColor: NpupsColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NPUPS Timesheet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Fortnightly Attendance Entry', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Draft',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Draft saved locally'), backgroundColor: NpupsColors.success),
              );
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 24),
              ..._workerEntries.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildWorkerCard(entry.key, entry.value),
                );
              }),
              _buildAddWorkerButton(),
              const SizedBox(height: 24),
              _buildTotalsCard(),
              const SizedBox(height: 24),
              _buildSignOffSection(),
              const SizedBox(height: 24),
              _buildSubmitButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER SECTION ─────────────────────────────────────────────────────────

  Widget _buildHeaderSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment, color: NpupsColors.accent, size: 22),
                SizedBox(width: 8),
                Text('Timesheet Header', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
              ],
            ),
            const Divider(height: 24),
            _buildLabel('Municipal Corporation *'),
            DropdownButtonFormField<Corporation>(
              value: _selectedCorporation,
              decoration: _inputDecoration('Select Corporation'),
              items: _corporations.map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: (val) => setState(() { _selectedCorporation = val; _selectedDistrict = null; }),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Electoral District *'),
                      DropdownButtonFormField<String>(
                        value: _selectedDistrict,
                        decoration: _inputDecoration('Select District'),
                        items: (_selectedCorporation?.electoralDistricts ?? []).map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 14)))).toList(),
                        onChanged: (val) => setState(() => _selectedDistrict = val),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Group #'),
                      TextFormField(
                        decoration: _inputDecoration('e.g. 1'),
                        onChanged: (v) => _groupNumber = v,
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Start of Fortnight *'),
                      InkWell(
                        onTap: _selectFortnightStart,
                        child: InputDecorator(
                          decoration: _inputDecoration('Select Monday'),
                          child: Text(
                            _fortnightStart != null ? DateFormat('dd MMM yyyy').format(_fortnightStart!) : 'Tap to select',
                            style: TextStyle(fontSize: 14, color: _fortnightStart != null ? NpupsColors.textPrimary : NpupsColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('End of Fortnight'),
                      InputDecorator(
                        decoration: _inputDecoration('Auto-calculated'),
                        child: Text(
                          _fortnightEnd != null ? DateFormat('dd MMM yyyy').format(_fortnightEnd!) : '--',
                          style: const TextStyle(fontSize: 14, color: NpupsColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── WORKER CARD ────────────────────────────────────────────────────────────

  Widget _buildWorkerCard(int index, WorkerTimesheetEntry entry) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: const RoundedRectangleBorder(),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: entry.worker != null ? NpupsColors.success : NpupsColors.border,
              child: Text('${index + 1}', style: TextStyle(color: entry.worker != null ? Colors.white : NpupsColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.worker?.name ?? 'Worker ${index + 1} (unassigned)',
                style: TextStyle(fontWeight: FontWeight.w600, color: entry.worker != null ? NpupsColors.textPrimary : NpupsColors.textSecondary),
              ),
            ),
            if (entry.worker != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: NpupsColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('${entry.daysWorked}d | ${_formatCurrency(entry.grandTotal)}', style: const TextStyle(fontSize: 12, color: NpupsColors.success, fontWeight: FontWeight.w600)),
              ),
            if (_workerEntries.length > 1)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: NpupsColors.error),
                onPressed: () => _removeWorkerEntry(index),
                tooltip: 'Remove worker',
              ),
          ],
        ),
        children: [
          _buildLabel('Worker Name *'),
          Autocomplete<RegisteredWorker>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable.empty();
              return _registeredWorkers.where((w) => w.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            displayStringForOption: (w) => w.name,
            onSelected: (worker) => setState(() => entry.worker = worker),
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextFormField(controller: controller, focusNode: focusNode, decoration: _inputDecoration('Start typing worker name...'), style: const TextStyle(fontSize: 14));
            },
          ),
          if (entry.worker != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: NpupsColors.inputFill, borderRadius: BorderRadius.circular(8), border: Border.all(color: NpupsColors.border)),
              child: Row(children: [_buildInfoChip('Position', entry.worker!.position), _buildInfoChip('ID#', entry.worker!.idNumber), _buildInfoChip('NIS#', entry.worker!.nisNumber)]),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _quickFillWeekday(entry),
                icon: const Icon(Icons.flash_on, size: 16, color: NpupsColors.accent),
                label: const Text('Quick fill Mon-Fri (7:00-15:00)', style: TextStyle(fontSize: 12, color: NpupsColors.accent)),
              ),
            ),
            _buildAttendanceGrid(entry),
            const SizedBox(height: 16),
            _buildWorkerTotals(entry),
          ],
        ],
      ),
    );
  }

  // ── ATTENDANCE GRID ────────────────────────────────────────────────────────

  Widget _buildAttendanceGrid(WorkerTimesheetEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Week 1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: NpupsColors.primary)),
        const SizedBox(height: 4),
        _buildWeekRow(entry, 0, 7),
        const SizedBox(height: 12),
        const Text('Week 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: NpupsColors.primary)),
        const SizedBox(height: 4),
        _buildWeekRow(entry, 7, 14),
      ],
    );
  }

  Widget _buildWeekRow(WorkerTimesheetEntry entry, int start, int end) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(end - start, (i) {
          final dayIndex = start + i;
          final att = entry.attendance[dayIndex];
          final isWeekend = (dayIndex % 7) >= 5;
          return Container(
            width: 72,
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: att.isPresent ? NpupsColors.success.withOpacity(0.08) : isWeekend ? Colors.grey.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: att.isPresent ? NpupsColors.success.withOpacity(0.3) : NpupsColors.border),
            ),
            child: Column(
              children: [
                Text(_dayLabels[dayIndex], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isWeekend ? NpupsColors.textSecondary : NpupsColors.primary)),
                if (_fortnightStart != null)
                  Text(DateFormat('d').format(_fortnightStart!.add(Duration(days: dayIndex))), style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _pickTime(entry, dayIndex, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    decoration: BoxDecoration(color: NpupsColors.inputFill, borderRadius: BorderRadius.circular(4)),
                    child: Text(_formatTime(att.timeIn), style: TextStyle(fontSize: 10, color: att.timeIn != null ? NpupsColors.success : NpupsColors.textSecondary, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () => _pickTime(entry, dayIndex, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    decoration: BoxDecoration(color: NpupsColors.inputFill, borderRadius: BorderRadius.circular(4)),
                    child: Text(_formatTime(att.timeOut), style: TextStyle(fontSize: 10, color: att.timeOut != null ? NpupsColors.accent : NpupsColors.textSecondary, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── WORKER TOTALS ──────────────────────────────────────────────────────────

  Widget _buildWorkerTotals(WorkerTimesheetEntry entry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NpupsColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NpupsColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Row(children: [
            _buildTotalItem('Days', '${entry.daysWorked}'),
            _buildTotalItem('Wage', _formatCurrency(entry.wageTotal)),
            _buildTotalItem('COLA', _formatCurrency(entry.colaTotal)),
            _buildTotalItem('Allow.', _formatCurrency(entry.allowanceTotal)),
            _buildTotalItem('TOTAL', _formatCurrency(entry.grandTotal), bold: true),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                decoration: _inputDecoration('Allowance days').copyWith(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => setState(() => entry.allowanceDays = int.tryParse(v) ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                decoration: _inputDecoration('Remarks (optional)').copyWith(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                style: const TextStyle(fontSize: 13),
                maxLength: 200,
                onChanged: (v) => entry.remarks = v,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── TOTALS CARD ────────────────────────────────────────────────────────────

  Widget _buildTotalsCard() {
    final totalWorkers = _workerEntries.where((e) => e.worker != null).length;
    final totalDays = _workerEntries.fold<int>(0, (sum, e) => sum + e.daysWorked);
    final totalWage = _workerEntries.fold<double>(0, (sum, e) => sum + e.wageTotal);
    final totalCola = _workerEntries.fold<double>(0, (sum, e) => sum + e.colaTotal);
    final totalAllowance = _workerEntries.fold<double>(0, (sum, e) => sum + e.allowanceTotal);
    final grandTotal = totalWage + totalCola + totalAllowance;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: NpupsColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Timesheet Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const Divider(color: Colors.white24, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Workers', '$totalWorkers'),
                _buildSummaryItem('Total Days', '$totalDays'),
                _buildSummaryItem('Wages', _formatCurrency(totalWage)),
                _buildSummaryItem('COLA', _formatCurrency(totalCola)),
                _buildSummaryItem('Allowance', _formatCurrency(totalAllowance)),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            Center(
              child: Text('GRAND TOTAL: ${_formatCurrency(grandTotal)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── SIGN-OFF SECTION ───────────────────────────────────────────────────────

  Widget _buildSignOffSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user, color: NpupsColors.accent, size: 22),
                SizedBox(width: 8),
                Text('Sign-Off & Approval', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
              ],
            ),
            const Divider(height: 24),
            CheckboxListTile(
              value: _isSupervisorConfirmed,
              onChanged: (v) => setState(() => _isSupervisorConfirmed = v ?? false),
              title: const Text('Maintenance Supervisor Confirmation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('I confirm that attendance records are accurate and verified.', style: TextStyle(fontSize: 12)),
              activeColor: NpupsColors.success,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person, color: NpupsColors.accent),
              title: const Text('Regional Coordinator', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Auto-captured from your login session', style: TextStyle(fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: NpupsColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Text('Authenticated', style: TextStyle(fontSize: 11, color: NpupsColors.success)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ADD WORKER BUTTON ──────────────────────────────────────────────────────

  Widget _buildAddWorkerButton() {
    return OutlinedButton.icon(
      onPressed: _workerEntries.length < 12 ? _addWorkerEntry : null,
      icon: const Icon(Icons.person_add, size: 18),
      label: Text('Add Worker (${_workerEntries.length}/12)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: NpupsColors.accent,
        side: BorderSide(color: NpupsColors.accent.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── SUBMIT BUTTON ──────────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitTimesheet,
        icon: _isSubmitting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, size: 20),
        label: Text(_isSubmitting ? 'Submitting...' : 'Submit Timesheet'),
        style: ElevatedButton.styleFrom(
          backgroundColor: NpupsColors.success,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── SHARED WIDGETS ─────────────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.textSecondary)),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: NpupsColors.textSecondary),
      filled: true,
      fillColor: NpupsColors.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NpupsColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NpupsColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NpupsColors.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NpupsColors.error)),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Expanded(
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.textPrimary)),
      ]),
    );
  }

  Widget _buildTotalItem(String label, String value, {bool bold = false}) {
    return Expanded(
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: bold ? NpupsColors.primary : NpupsColors.textPrimary)),
      ]),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
    ]);
  }
}
