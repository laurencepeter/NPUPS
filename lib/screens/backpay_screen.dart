// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Backpay management screen.
//
// HR/Admin can:
//   1. Configure a retroactive wage-rate increase (effective date, old/new rate)
//   2. Calculate per-worker backpay across all qualifying timesheets
//   3. Approve and disburse — every step recorded in the tamper-evident audit
//      chain so the employer's compliance trail is complete.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/backpay_model.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../services/backpay_service.dart';
import '../services/worker_data_store.dart';
import '../theme/app_theme.dart';

class BackpayScreen extends StatefulWidget {
  final AppUser currentUser;
  const BackpayScreen({super.key, required this.currentUser});

  @override
  State<BackpayScreen> createState() => _BackpayScreenState();
}

class _BackpayScreenState extends State<BackpayScreen> {
  final BackpayService _service = BackpayService();
  final WorkerDataStore _workers = WorkerDataStore();
  final _money = NumberFormat.currency(symbol: 'TT\$ ', decimalDigits: 2);
  final _date = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Backpay'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_card_outlined),
                tooltip: 'New backpay calculation',
                onPressed: _openCalculatorSheet,
              ),
            ],
          ),
          body: _service.records.isEmpty
              ? _buildEmpty(isDark)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _service.records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildRecordCard(_service.records[i], isDark),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openCalculatorSheet,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calculate'),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off,
                size: 56,
                color: isDark ? AppColors.darkTextHint : AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'No backpay records yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'When salaries are increased retroactively, calculate the backpay '
              'owed and the system will compute the delta for every '
              'qualifying fortnight.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openCalculatorSheet,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Calculate Backpay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(BackpayRecord r, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.workerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                _statusChip(r.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${r.corporationName} • Effective ${_date.format(r.effectiveFrom)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _kv('Old Wage', _money.format(r.oldWageRate)),
                _kv('New Wage', _money.format(r.newWageRate),
                    color: AppColors.success),
                _kv('Fortnights', r.fortnightsAffected.toString()),
                _kv('Backpay', _money.format(r.totalAmount),
                    color: AppColors.accent, bold: true),
              ],
            ),
            if (r.lineItems.isNotEmpty) ...[
              const Divider(height: 20),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'Line items (${r.lineItems.length})',
                  style: const TextStyle(fontSize: 12),
                ),
                children: r.lineItems
                    .map((l) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_date.format(l.fortnightStart)} • ${l.daysWorked} days',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              Text(
                                _money.format(l.totalDelta),
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (r.status == BackpayStatus.calculated)
                  OutlinedButton.icon(
                    onPressed: () => _service.approve(r.id, widget.currentUser),
                    icon: const Icon(Icons.thumb_up_outlined, size: 14),
                    label: const Text('Approve'),
                  ),
                if (r.status == BackpayStatus.approved) ...[
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _service.disburse(r.id, widget.currentUser),
                    icon: const Icon(Icons.payments_outlined, size: 14),
                    label: const Text('Disburse'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BackpayStatus s) {
    final color = switch (s) {
      BackpayStatus.calculated => AppColors.warning,
      BackpayStatus.approved => AppColors.info,
      BackpayStatus.disbursed => AppColors.success,
      BackpayStatus.cancelled => AppColors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(s.displayName,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k,
            style:
                TextStyle(fontSize: 10, color: AppColors.textHint)),
        Text(v,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  // ── Calculator sheet ─────────────────────────────────────────────────────
  Future<void> _openCalculatorSheet() async {
    final workers = _workers.workers.where((w) => w.isActive).toList();
    if (workers.isEmpty) return;

    Worker? selected = workers.first;
    final oldWageCtrl =
        TextEditingController(text: selected.wageRate.toStringAsFixed(2));
    final newWageCtrl =
        TextEditingController(text: selected.wageRate.toStringAsFixed(2));
    final oldColaCtrl =
        TextEditingController(text: selected.colaRate.toStringAsFixed(2));
    final newColaCtrl =
        TextEditingController(text: selected.colaRate.toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    DateTime effectiveFrom =
        DateTime(DateTime.now().year, 1, 1);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Calculate Retroactive Backpay',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Worker>(
                      value: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Worker',
                          border: OutlineInputBorder()),
                      items: workers
                          .map((w) => DropdownMenuItem(
                                value: w,
                                child: Text(
                                  '${w.fullName} • ${w.corporationName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (w) => setSt(() {
                        selected = w;
                        oldWageCtrl.text = w!.wageRate.toStringAsFixed(2);
                        newWageCtrl.text = w.wageRate.toStringAsFixed(2);
                        oldColaCtrl.text = w.colaRate.toStringAsFixed(2);
                        newColaCtrl.text = w.colaRate.toStringAsFixed(2);
                      }),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: effectiveFrom,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSt(() => effectiveFrom = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Effective from',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(_date.format(effectiveFrom)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: oldWageCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Old wage / day',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: newWageCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'New wage / day',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: oldColaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Old COLA / day',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: newColaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'New COLA / day',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Note / Cabinet decision reference',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Calculate'),
                        onPressed: () {
                          final w = selected!;
                          final result = _service.calculateForWorker(
                            actor: widget.currentUser,
                            workerId: w.id,
                            workerName: w.fullName,
                            corporationId: w.corporationId,
                            corporationName: w.corporationName,
                            effectiveFrom: effectiveFrom,
                            oldWageRate:
                                double.tryParse(oldWageCtrl.text) ?? 0,
                            newWageRate:
                                double.tryParse(newWageCtrl.text) ?? 0,
                            oldColaRate:
                                double.tryParse(oldColaCtrl.text) ?? 0,
                            newColaRate:
                                double.tryParse(newColaCtrl.text) ?? 0,
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result == null
                                  ? 'No qualifying fortnights — backpay is 0'
                                  : 'Backpay calculated: ${_money.format(result.totalAmount)} across ${result.fortnightsAffected} fortnights'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
