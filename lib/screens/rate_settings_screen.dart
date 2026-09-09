// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Statutory Rates admin — lets a System Admin edit the PAYE / NIS / Health
// Surcharge figures the payroll engine uses, at runtime, without a code change.
//
// Rate sets are effective-dated: adding a new set (with a future effective
// date) leaves already-processed fortnights on their original rates, so
// historical payslips stay reproducible. Non-admins see the same data
// read-only.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payroll_deductions_model.dart';
import '../models/user_model.dart';
import '../services/rate_table_service.dart';
import '../theme/app_theme.dart';

class RateSettingsScreen extends StatefulWidget {
  final AppUser currentUser;
  const RateSettingsScreen({super.key, required this.currentUser});

  @override
  State<RateSettingsScreen> createState() => _RateSettingsScreenState();
}

class _RateSettingsScreenState extends State<RateSettingsScreen> {
  final RateTableService _service = RateTableService();
  final _money = NumberFormat.currency(symbol: 'TT\$ ', decimalDigits: 2);
  final _dateFmt = DateFormat('dd MMM yyyy');

  bool get _canEdit => widget.currentUser.role == UserRole.systemAdmin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Statutory Rates')),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add),
              label: const Text('New rate set'),
            )
          : null,
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final tables = _service.tables;
          return Column(
            children: [
              _banner(isDark),
              Expanded(
                child: tables.isEmpty
                    ? Center(
                        child: Text('No rate sets yet.',
                            style: TextStyle(color: AppColors.textHint)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: tables.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _card(tables[i], i == 0),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner(bool isDark) {
    final msg = _canEdit
        ? 'Changes take effect from each set’s effective date. Add a new '
            'set when a rate changes — don’t edit past sets, so old '
            'payslips stay reproducible.'
        : 'Read-only. Only a System Admin can change statutory rates.';
    return Container(
      width: double.infinity,
      color: (_canEdit ? AppColors.info : AppColors.warning).withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(_canEdit ? Icons.info_outline : Icons.lock_outline,
              size: 16, color: _canEdit ? AppColors.info : AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _card(DeductionRateTable t, bool isCurrent) {
    final pct = NumberFormat('0.###');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.label ?? 'Rate set',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('IN FORCE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success)),
                  ),
                if (_canEdit) ...[
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _openEditor(t),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: AppColors.error),
                    onPressed: () => _confirmDelete(t),
                  ),
                ],
              ],
            ),
            Text(
              'Effective ${t.effectiveFrom != null ? _dateFmt.format(t.effectiveFrom!) : "—"}'
              '  ·  ${t.payPeriodsPerYear} pay periods/yr',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _stat('PAYE', '${pct.format(t.payeRateLow * 100)}% / '
                    '${pct.format(t.payeRateHigh * 100)}%'),
                _stat('Personal allowance',
                    _money.format(t.personalAllowanceAnnual) + '/yr'),
                _stat('PAYE band ceiling',
                    _money.format(t.payeBandThresholdAnnual) + '/yr'),
                _stat('NIS worker', '${pct.format(t.nisEmployeeRate * 100)}%'),
                _stat('NIS employer', '${pct.format(t.nisEmployerRate * 100)}%'),
                _stat('Health surcharge',
                    '${_money.format(t.healthSurchargeWeeklyHigh)} / '
                    '${_money.format(t.healthSurchargeWeeklyLow)} wk'),
                _stat('HS threshold',
                    _money.format(t.healthSurchargeHighThreshold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textHint)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _confirmDelete(DeductionRateTable t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete rate set?'),
        content: Text('“${t.label ?? t.id}” will be removed. Fortnights that '
            'resolved to it will fall back to the next earlier set.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && t.id != null) {
      try {
        await _service.remove(t.id!);
      } catch (e) {
        _snack('Delete failed: $e');
      }
    }
  }

  Future<void> _openEditor(DeductionRateTable? existing) async {
    final saved = await showDialog<DeductionRateTable>(
      context: context,
      builder: (_) => _RateEditorDialog(existing: existing),
    );
    if (saved == null) return;
    try {
      await _service.upsert(saved);
      _snack('Saved.');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

// ── Editor dialog ────────────────────────────────────────────────────────────

class _RateEditorDialog extends StatefulWidget {
  final DeductionRateTable? existing;
  const _RateEditorDialog({this.existing});

  @override
  State<_RateEditorDialog> createState() => _RateEditorDialogState();
}

class _RateEditorDialogState extends State<_RateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _effective;
  late TextEditingController _label;
  late TextEditingController _periods;
  // Percentages are edited as human-friendly percents, stored as fractions.
  late TextEditingController _nisEmp, _nisEr, _payeLow, _payeHigh;
  late TextEditingController _hsHigh, _hsLow, _hsThreshold;
  late TextEditingController _allowance, _bandCeiling;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _effective = e?.effectiveFrom ?? DateTime.now();
    _label = TextEditingController(text: e?.label ?? '');
    _periods = TextEditingController(text: '${e?.payPeriodsPerYear ?? 26}');
    _nisEmp = _pctCtl(e?.nisEmployeeRate ?? 0.034);
    _nisEr = _pctCtl(e?.nisEmployerRate ?? 0.065);
    _payeLow = _pctCtl(e?.payeRateLow ?? 0.25);
    _payeHigh = _pctCtl(e?.payeRateHigh ?? 0.30);
    _hsHigh = _numCtl(e?.healthSurchargeWeeklyHigh ?? 8.25);
    _hsLow = _numCtl(e?.healthSurchargeWeeklyLow ?? 4.80);
    _hsThreshold = _numCtl(e?.healthSurchargeHighThreshold ?? 469.99);
    _allowance = _numCtl(e?.personalAllowanceAnnual ?? 90000);
    _bandCeiling = _numCtl(e?.payeBandThresholdAnnual ?? 1000000);
  }

  TextEditingController _pctCtl(double frac) =>
      TextEditingController(text: _trim(frac * 100));
  TextEditingController _numCtl(double v) =>
      TextEditingController(text: _trim(v));
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [
      _label, _periods, _nisEmp, _nisEr, _payeLow, _payeHigh,
      _hsHigh, _hsLow, _hsThreshold, _allowance, _bandCeiling,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return AlertDialog(
      title: Text(widget.existing == null ? 'New rate set' : 'Edit rate set'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Label'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _effective,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _effective = picked);
                  },
                  child: InputDecorator(
                    decoration:
                        const InputDecoration(labelText: 'Effective from'),
                    child: Text(dateFmt.format(_effective)),
                  ),
                ),
                _field(_periods, 'Pay periods / year', isInt: true),
                const _SectionLabel('PAYE income tax'),
                _field(_allowance, 'Personal allowance (TT\$/yr)'),
                _field(_bandCeiling, 'Lower-band ceiling (TT\$/yr)'),
                _field(_payeLow, 'Lower-band rate (%)'),
                _field(_payeHigh, 'Higher-band rate (%)'),
                const _SectionLabel('National Insurance'),
                _field(_nisEmp, 'Employee rate (%)'),
                _field(_nisEr, 'Employer rate (%)'),
                const _SectionLabel('Health Surcharge'),
                _field(_hsHigh, 'Weekly — high band (TT\$)'),
                _field(_hsLow, 'Weekly — low band (TT\$)'),
                _field(_hsThreshold, 'Fortnightly gross threshold (TT\$)'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {bool isInt = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: false),
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final n = num.tryParse((v ?? '').trim());
          if (n == null) return 'Enter a number';
          if (n < 0) return 'Must be ≥ 0';
          if (isInt && n != n.roundToDouble()) return 'Whole number';
          return null;
        },
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    double p(TextEditingController c) => double.parse(c.text.trim());
    final base = widget.existing ??
        DeductionRateTable(
          id: 'RATE-${DateTime.now().millisecondsSinceEpoch}',
          year: _effective.year,
        );
    final result = base.copyWith(
      label: _label.text.trim(),
      effectiveFrom: _effective,
      payPeriodsPerYear: int.parse(_periods.text.trim()),
      nisEmployeeRate: p(_nisEmp) / 100,
      nisEmployerRate: p(_nisEr) / 100,
      payeRateLow: p(_payeLow) / 100,
      payeRateHigh: p(_payeHigh) / 100,
      healthSurchargeWeeklyHigh: p(_hsHigh),
      healthSurchargeWeeklyLow: p(_hsLow),
      healthSurchargeHighThreshold: p(_hsThreshold),
      personalAllowanceAnnual: p(_allowance),
      payeBandThresholdAnnual: p(_bandCeiling),
    );
    Navigator.pop(context, result);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.accent)),
      ),
    );
  }
}
