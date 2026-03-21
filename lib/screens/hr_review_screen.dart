// ──────────────────────────────────────────────────────────────────────────────
// NPUPS HR Review Screen
// Receives coordinator-approved timesheets.
// Verifies compliance, leave, employee status.
// Approve forward to Accounts or reject back to Coordinator.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../services/timesheet_data_store.dart';

class HrReviewScreen extends StatefulWidget {
  final NpupsUser user;
  const HrReviewScreen({super.key, required this.user});

  @override
  State<HrReviewScreen> createState() => _HrReviewScreenState();
}

class _HrReviewScreenState extends State<HrReviewScreen> {
  final TimesheetDataStore _store = TimesheetDataStore();

  List<Timesheet> get _queue =>
      _store.getByStage(TimesheetStage.hrProcessing);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NpupsColors.surface,
      appBar: AppBar(
        backgroundColor: NpupsColors.primary,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HR Processing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Compliance & Leave Verification', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final queue = _queue;
          if (queue.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: NpupsColors.border),
                  SizedBox(height: 16),
                  Text('No Timesheets Pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('All coordinator-approved timesheets have been processed.', style: TextStyle(color: NpupsColors.textSecondary)),
                ],
              ),
            );
          }
          return Column(
            children: [
              _buildSummaryBar(queue),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: queue.length,
                  itemBuilder: (context, i) => _buildTimesheetCard(queue[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBar(List<Timesheet> queue) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: NpupsColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('${queue.length} pending', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NpupsColors.warning)),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: NpupsColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('Total: \$${queue.fold<double>(0, (s, t) => s + t.grandTotal).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NpupsColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimesheetCard(Timesheet ts) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Worker info header
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: NpupsColors.warning.withValues(alpha: 0.1),
                  child: const Icon(Icons.badge, color: NpupsColors.warning, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ts.workerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Text('${ts.position} | ${ts.corporationName}', style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Compliance checklist
            const Text('Compliance Checks', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
            const SizedBox(height: 8),
            _checkItem('Employee Status', 'Active', true),
            _checkItem('NIS Number', ts.nisNumber, true),
            _checkItem('ID Verified', ts.idNumber, true),
            _checkItem('Leave Balance', 'Within limits', true),
            _checkItem('Bank Details', '${ts.bankName} - ${ts.accountNumber}', true),
            const SizedBox(height: 12),

            // Financials
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _detailItem('Days', '${ts.daysWorked}'),
                _detailItem('Wage', '\$${ts.wageTotal.toStringAsFixed(0)}'),
                _detailItem('COLA', '\$${ts.colaTotal.toStringAsFixed(0)}'),
                _detailItem('Allow.', '\$${ts.allowanceTotal.toStringAsFixed(0)}'),
                _detailItem('Total', '\$${ts.grandTotal.toStringAsFixed(0)}', bold: true),
              ],
            ),
            const SizedBox(height: 8),
            Text('Fortnight: ${DateFormat('dd/MM').format(ts.fortnightStart)} - ${DateFormat('dd/MM').format(ts.fortnightEnd)} | Group: ${ts.groupNumber}',
                style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
            const SizedBox(height: 4),

            // Coordinator approval note
            if (ts.approvalHistory.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: NpupsColors.success.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: NpupsColors.success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Approved by ${ts.approvalHistory.last.reviewerName} (${ts.approvalHistory.last.reviewerRole})',
                        style: const TextStyle(fontSize: 11, color: NpupsColors.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectTimesheet(ts),
                    icon: const Icon(Icons.reply, size: 16, color: NpupsColors.error),
                    label: const Text('Reject to Coordinator', style: TextStyle(color: NpupsColors.error, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: NpupsColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveTimesheet(ts),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Forward to Accounts', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NpupsColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(String label, String value, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(passed ? Icons.check_circle : Icons.error, size: 14, color: passed ? NpupsColors.success : NpupsColors.error),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _detailItem(String label, String value, {bool bold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
      ],
    );
  }

  void _approveTimesheet(Timesheet ts) {
    _store.advanceStage(ts.id, widget.user.fullName, 'HR Department', note: 'Compliance verified, leave OK');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ts.workerName} forwarded to Accounts'), backgroundColor: NpupsColors.success),
    );
  }

  void _rejectTimesheet(Timesheet ts) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject to Coordinator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rejecting ${ts.workerName}\'s timesheet back to the Regional Coordinator.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason *', hintText: 'e.g., Leave balance exceeded'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              _store.rejectTimesheet(ts.id, widget.user.fullName, 'HR Department', controller.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${ts.workerName}\'s timesheet rejected to Coordinator'), backgroundColor: NpupsColors.warning),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
