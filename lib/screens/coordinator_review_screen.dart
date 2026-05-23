// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Shows submitted timesheets for the coordinator's region.
// Approve individually, batch approve, or reject back to worker with a note.
// Only shows timesheets at submitted/coordinatorReview stage.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../services/timesheet_data_store.dart';

class CoordinatorReviewScreen extends StatefulWidget {
  final AppUser user;
  const CoordinatorReviewScreen({super.key, required this.user});

  @override
  State<CoordinatorReviewScreen> createState() => _CoordinatorReviewScreenState();
}

class _CoordinatorReviewScreenState extends State<CoordinatorReviewScreen> {
  final TimesheetDataStore _store = TimesheetDataStore();
  final Set<String> _selectedIds = {};
  List<Timesheet>? _cachedQueue;
  int _lastTimesheetVersion = -1;

  List<Timesheet> get _queue {
    final currentVersion = _store.timesheets.length;
    if (_cachedQueue == null || _lastTimesheetVersion != currentVersion) {
      _lastTimesheetVersion = currentVersion;
      _cachedQueue = _store.timesheets.where((t) =>
        (t.stage == TimesheetStage.submitted || t.stage == TimesheetStage.coordinatorReview) &&
        (widget.user.corporationId == null || t.corporationId == widget.user.corporationId)
      ).toList();
    }
    return _cachedQueue!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coordinator Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.user.corporationName ?? 'All Regions', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton.icon(
              onPressed: _batchApprove,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
              label: Text('Approve (${_selectedIds.length})', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final queue = _queue;
          if (queue.isEmpty) {
            return _buildEmptyQueue();
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

  Widget _buildEmptyQueue() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: AppColors.border),
          SizedBox(height: 16),
          Text('No Timesheets to Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          SizedBox(height: 8),
          Text('All submitted timesheets have been processed.', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(List<Timesheet> queue) {
    final totalWorkers = queue.length;
    final totalPay = queue.fold<double>(0, (sum, t) => sum + t.grandTotal);
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _summaryChip('Pending', '$totalWorkers', AppColors.warning),
          const SizedBox(width: 12),
          _summaryChip('Total Pay', '\$${totalPay.toStringAsFixed(0)}', AppColors.accent),
          const Spacer(),
          if (queue.length > 1)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == queue.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.addAll(queue.map((t) => t.id));
                  }
                });
              },
              child: Text(_selectedIds.length == queue.length ? 'Deselect All' : 'Select All', style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTimesheetCard(Timesheet ts) {
    final isSelected = _selectedIds.contains(ts.id);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? const BorderSide(color: AppColors.accent, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onLongPress: () => setState(() {
          isSelected ? _selectedIds.remove(ts.id) : _selectedIds.add(ts.id);
        }),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (v) => setState(() {
                      v == true ? _selectedIds.add(ts.id) : _selectedIds.remove(ts.id);
                    }),
                    activeColor: AppColors.accent,
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                    child: Text(ts.workerName.split(' ').map((n) => n[0]).take(2).join(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ts.workerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('${ts.position} | ${ts.electoralDistrict}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: ts.stage.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(ts.stage.displayName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ts.stage.color)),
                  ),
                ],
              ),
              const Divider(height: 20),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Fortnight: ${DateFormat('dd/MM').format(ts.fortnightStart)} - ${DateFormat('dd/MM').format(ts.fortnightEnd)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('Group: ${ts.groupNumber}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectTimesheet(ts),
                      icon: const Icon(Icons.reply, size: 16, color: AppColors.error),
                      label: const Text('Reject', style: TextStyle(color: AppColors.error, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveTimesheet(ts),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
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
      ),
    );
  }

  Widget _detailItem(String label, String value, {bool bold = false}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
      ],
    );
  }

  void _approveTimesheet(Timesheet ts) {
    // Move from submitted -> coordinatorReview, then coordinatorReview -> hrProcessing
    if (ts.stage == TimesheetStage.submitted) {
      _store.advanceStage(ts.id, widget.user.fullName, 'Regional Coordinator', actor: widget.user);
    }
    _store.advanceStage(ts.id, widget.user.fullName, 'Regional Coordinator', note: 'Attendance verified', actor: widget.user);
    _selectedIds.remove(ts.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ts.workerName} approved and forwarded to HR'), backgroundColor: AppColors.success),
    );
  }

  void _batchApprove() {
    final count = _selectedIds.length;
    for (final id in _selectedIds.toList()) {
      final ts = _store.getById(id);
      if (ts != null) {
        if (ts.stage == TimesheetStage.submitted) {
          _store.advanceStage(ts.id, widget.user.fullName, 'Regional Coordinator', actor: widget.user);
        }
        _store.advanceStage(ts.id, widget.user.fullName, 'Regional Coordinator', note: 'Batch approved', actor: widget.user);
      }
    }
    _selectedIds.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count timesheets approved and forwarded to HR'), backgroundColor: AppColors.success),
    );
  }

  void _rejectTimesheet(Timesheet ts) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Timesheet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rejecting ${ts.workerName}\'s timesheet back to the worker.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason for rejection *', hintText: 'e.g., Missing Friday attendance'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              _store.rejectTimesheet(ts.id, widget.user.fullName, 'Regional Coordinator', controller.text.trim(), actor: widget.user);
              _selectedIds.remove(ts.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${ts.workerName}\'s timesheet rejected'), backgroundColor: AppColors.warning),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}
