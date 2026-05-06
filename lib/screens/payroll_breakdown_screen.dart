// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Payroll Breakdown — pivot view of every paid timesheet with NIS, Health
// Surcharge and Salary columns. Supports four grouping axes:
//   • Per Person
//   • Per Month
//   • Per Corporation
//   • Per Batch (fortnight)
//
// Uses the same statutory-deduction computation that the worker payslip,
// pay sheet, and the audit trail rely on so figures reconcile end-to-end.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../services/timesheet_data_store.dart';
import '../theme/app_theme.dart';

enum _BreakdownAxis {
  person('Person', Icons.person_outline),
  month('Month', Icons.calendar_month_outlined),
  corporation('Corporation', Icons.account_balance_outlined),
  batch('Batch (Fortnight)', Icons.event_note_outlined);

  const _BreakdownAxis(this.label, this.icon);
  final String label;
  final IconData icon;
}

class PayrollBreakdownScreen extends StatefulWidget {
  final AppUser currentUser;

  const PayrollBreakdownScreen({super.key, required this.currentUser});

  @override
  State<PayrollBreakdownScreen> createState() =>
      _PayrollBreakdownScreenState();
}

class _PayrollBreakdownScreenState extends State<PayrollBreakdownScreen> {
  final TimesheetDataStore _store = TimesheetDataStore();
  final _money = NumberFormat.currency(symbol: 'TT\$ ', decimalDigits: 2);
  final _monthFmt = DateFormat('MMM yyyy');
  final _dateFmt = DateFormat('dd MMM yyyy');

  _BreakdownAxis _axis = _BreakdownAxis.person;
  String? _expandedKey;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final timesheets = _payableTimesheets();
        final groups = _group(timesheets);
        final totals = _totals(timesheets);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Payroll Breakdown'),
          ),
          body: Column(
            children: [
              _buildAxisSelector(isDark),
              _buildSearch(isDark),
              _buildSummaryStrip(totals, isDark),
              const Divider(height: 1),
              Expanded(
                child: groups.isEmpty
                    ? _buildEmpty(isDark)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) =>
                            _buildGroupCard(groups[i], isDark),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAxisSelector(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _BreakdownAxis.values.map((a) {
            final selected = a == _axis;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(a.icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary)),
                label: Text(a.label),
                selected: selected,
                labelStyle: TextStyle(
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary),
                  fontSize: 12,
                ),
                selectedColor: AppColors.accent,
                onSelected: (_) => setState(() {
                  _axis = a;
                  _expandedKey = null;
                }),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearch(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkCard : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search ${_axis.label.toLowerCase()}…',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildSummaryStrip(_Totals t, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isDark ? AppColors.darkBackground : AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _kpi('Salaries', _money.format(t.salaries),
                color: AppColors.success),
            _kpi('NIS (Worker)', _money.format(t.nisEmployee),
                color: AppColors.info),
            _kpi('NIS (Employer)', _money.format(t.nisEmployer),
                color: AppColors.accentDark),
            _kpi('Health Surcharge', _money.format(t.healthSurcharge),
                color: AppColors.warning),
            _kpi('Net Pay', _money.format(t.netPay),
                color: AppColors.primary, bold: true),
            _kpi('Total Cost', _money.format(t.totalEmployerCost),
                color: AppColors.error, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String label, String value,
      {required Color color, bool bold = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textHint)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildGroupCard(_Group g, bool isDark) {
    final isExpanded = _expandedKey == g.key;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
                () => _expandedKey = isExpanded ? null : g.key),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_axis.icon,
                          size: 18,
                          color: isDark
                              ? AppColors.darkAccent
                              : AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(g.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      Text('${g.timesheets.length} ts',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                      Icon(
                          isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _miniStat('Salaries', g.totals.salaries),
                      _miniStat('NIS Worker', g.totals.nisEmployee,
                          color: AppColors.info),
                      _miniStat('NIS Employer', g.totals.nisEmployer,
                          color: AppColors.accentDark),
                      _miniStat('Health Surch.', g.totals.healthSurcharge,
                          color: AppColors.warning),
                      _miniStat('Net Pay', g.totals.netPay,
                          color: AppColors.success, bold: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            _buildLineItemTable(g, isDark),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, double value,
      {Color? color, bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 9, color: AppColors.textHint)),
        Text(_money.format(value),
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
      ],
    );
  }

  Widget _buildLineItemTable(_Group g, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 32,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 36,
          columns: const [
            DataColumn(label: Text('Worker')),
            DataColumn(label: Text('Fortnight')),
            DataColumn(label: Text('Days')),
            DataColumn(label: Text('Salary'), numeric: true),
            DataColumn(label: Text('NIS Wkr'), numeric: true),
            DataColumn(label: Text('NIS Emp'), numeric: true),
            DataColumn(label: Text('Health Surch.'), numeric: true),
            DataColumn(label: Text('Net'), numeric: true),
          ],
          rows: g.timesheets.map((t) {
            return DataRow(cells: [
              DataCell(Text(t.workerName,
                  style: const TextStyle(fontSize: 11))),
              DataCell(Text(_dateFmt.format(t.fortnightStart),
                  style: const TextStyle(fontSize: 11))),
              DataCell(Text('${t.daysWorked}',
                  style: const TextStyle(fontSize: 11))),
              DataCell(Text(_money.format(t.grossSalary),
                  style: const TextStyle(fontSize: 11))),
              DataCell(Text(_money.format(t.nisEmployee),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.info))),
              DataCell(Text(_money.format(t.nisEmployer),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.accentDark))),
              DataCell(Text(_money.format(t.healthSurcharge),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.warning))),
              DataCell(Text(_money.format(t.netPay),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No payroll data matches your filters yet.',
          style: TextStyle(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary),
        ),
      ),
    );
  }

  // ── Data shaping ─────────────────────────────────────────────────────────

  /// Only include timesheets that have actually been processed for payroll —
  /// from accountsProcessing onward.
  List<Timesheet> _payableTimesheets() {
    return _store.timesheets
        .where((t) =>
            t.daysWorked > 0 &&
            t.stage.index >= TimesheetStage.accountsProcessing.index)
        .toList();
  }

  List<_Group> _group(List<Timesheet> ts) {
    final m = <String, _Group>{};
    String key;
    String label;

    for (final t in ts) {
      switch (_axis) {
        case _BreakdownAxis.person:
          key = t.workerId;
          label = t.workerName;
          break;
        case _BreakdownAxis.month:
          key = '${t.fortnightStart.year}-${t.fortnightStart.month}';
          label = _monthFmt.format(t.fortnightStart);
          break;
        case _BreakdownAxis.corporation:
          key = t.corporationId;
          label = t.corporationName;
          break;
        case _BreakdownAxis.batch:
          key = '${t.corporationId}-${t.fortnightStart.toIso8601String()}';
          label =
              '${t.corporationName} • Fortnight ${_dateFmt.format(t.fortnightStart)}';
          break;
      }
      m.putIfAbsent(key, () => _Group(key: key, label: label, timesheets: []));
      m[key]!.timesheets.add(t);
    }

    final list = m.values.toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list.retainWhere((g) => g.label.toLowerCase().contains(q));
    }
    list.sort((a, b) => b.totals.salaries.compareTo(a.totals.salaries));
    return list;
  }

  _Totals _totals(List<Timesheet> ts) {
    double salaries = 0,
        nisEmp = 0,
        nisEr = 0,
        hs = 0,
        net = 0,
        cost = 0;
    for (final t in ts) {
      salaries += t.grossSalary;
      nisEmp += t.nisEmployee;
      nisEr += t.nisEmployer;
      hs += t.healthSurcharge;
      net += t.netPay;
      cost += t.deductions.totalEmployerCost + t.allowanceTotal;
    }
    return _Totals(
        salaries: salaries,
        nisEmployee: nisEmp,
        nisEmployer: nisEr,
        healthSurcharge: hs,
        netPay: net,
        totalEmployerCost: cost);
  }
}

class _Group {
  final String key;
  final String label;
  final List<Timesheet> timesheets;
  _Group({required this.key, required this.label, required this.timesheets});

  _Totals get totals {
    double s = 0, ne = 0, er = 0, h = 0, n = 0, c = 0;
    for (final t in timesheets) {
      s += t.grossSalary;
      ne += t.nisEmployee;
      er += t.nisEmployer;
      h += t.healthSurcharge;
      n += t.netPay;
      c += t.deductions.totalEmployerCost + t.allowanceTotal;
    }
    return _Totals(
        salaries: s,
        nisEmployee: ne,
        nisEmployer: er,
        healthSurcharge: h,
        netPay: n,
        totalEmployerCost: c);
  }
}

class _Totals {
  final double salaries;
  final double nisEmployee;
  final double nisEmployer;
  final double healthSurcharge;
  final double netPay;
  final double totalEmployerCost;
  _Totals({
    required this.salaries,
    required this.nisEmployee,
    required this.nisEmployer,
    required this.healthSurcharge,
    required this.netPay,
    required this.totalEmployerCost,
  });
}
