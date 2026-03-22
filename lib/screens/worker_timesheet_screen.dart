// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Worker Timesheet View
// Workers see their own timesheet with pre-populated static fields (read-only)
// and fill in dynamic fields (hours, overtime, leave, allowances).
// Includes a progress tracker showing pipeline position.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../services/timesheet_data_store.dart';

class WorkerTimesheetScreen extends StatefulWidget {
  final NpupsUser user;
  const WorkerTimesheetScreen({super.key, required this.user});

  @override
  State<WorkerTimesheetScreen> createState() => _WorkerTimesheetScreenState();
}

class _WorkerTimesheetScreenState extends State<WorkerTimesheetScreen> {
  final TimesheetDataStore _store = TimesheetDataStore();

  List<Timesheet> get _myTimesheets => _store.getByWorker(
      widget.user.fullName == 'Kevin Rampersad' ? 'WRK-001' : widget.user.id);

  Timesheet? get _currentTimesheet {
    // Find the most recent timesheet for this worker
    final sheets = _myTimesheets;
    if (sheets.isEmpty) return null;
    sheets.sort((a, b) => b.fortnightStart.compareTo(a.fortnightStart));
    return sheets.first;
  }

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
            Text('My Timesheet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Fortnightly Attendance', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final ts = _currentTimesheet;
          if (ts == null) {
            return _buildNoTimesheet();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildProgressTracker(ts),
              const SizedBox(height: 16),
              _buildStaticInfoCard(ts),
              const SizedBox(height: 16),
              if (ts.isEditable) ...[
                _buildAttendanceEditor(ts),
                const SizedBox(height: 16),
                _buildAllowanceAndRemarks(ts),
                const SizedBox(height: 16),
                _buildTotalsCard(ts),
                const SizedBox(height: 16),
                _buildActionButtons(ts),
              ] else ...[
                _buildReadOnlyAttendance(ts),
                const SizedBox(height: 16),
                _buildTotalsCard(ts),
                const SizedBox(height: 16),
                _buildApprovalHistory(ts),
              ],
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNoTimesheet() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: NpupsColors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text('No Timesheet Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NpupsColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('No timesheet has been assigned for the current fortnight.', style: TextStyle(color: NpupsColors.textSecondary)),
        ],
      ),
    );
  }

  // ── Progress Tracker ───────────────────────────────────────────────────────

  Widget _buildProgressTracker(Timesheet ts) {
    final stages = TimesheetStage.values;
    final currentIdx = stages.indexOf(ts.stage);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.linear_scale, color: NpupsColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('Pipeline Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ts.stage.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(ts.stage.displayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ts.stage.color)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: stages.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final stage = entry.value;
                  final isPast = idx < currentIdx;
                  final isCurrent = idx == currentIdx;
                  return Row(
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPast ? NpupsColors.success : isCurrent ? stage.color : NpupsColors.border,
                            ),
                            child: Icon(
                              isPast ? Icons.check : stage.icon,
                              size: 14,
                              color: isPast || isCurrent ? Colors.white : NpupsColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 60,
                            child: Text(
                              stage.displayName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent ? stage.color : NpupsColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (idx < stages.length - 1)
                        Container(
                          width: 20,
                          height: 2,
                          color: isPast ? NpupsColors.success : NpupsColors.border,
                          margin: const EdgeInsets.only(bottom: 16),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Static Info Card (read-only) ──────────────────────────────────────────

  Widget _buildStaticInfoCard(Timesheet ts) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person, color: NpupsColors.accent, size: 20),
                SizedBox(width: 8),
                Text('Worker Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
                SizedBox(width: 8),
                Text('(Read Only)', style: TextStyle(fontSize: 11, color: NpupsColors.textSecondary, fontStyle: FontStyle.italic)),
              ],
            ),
            const Divider(height: 20),
            _infoRow('Name', ts.workerName),
            _infoRow('Position', ts.position),
            _infoRow('ID#', ts.idNumber),
            _infoRow('NIS#', ts.nisNumber),
            _infoRow('Corporation', ts.corporationName),
            _infoRow('District', ts.electoralDistrict),
            _infoRow('Group', ts.groupNumber),
            _infoRow('Fortnight', '${DateFormat('dd MMM').format(ts.fortnightStart)} - ${DateFormat('dd MMM yyyy').format(ts.fortnightEnd)}'),
            _infoRow('Wage Rate', '\$${ts.wageRate.toStringAsFixed(2)}/day'),
            _infoRow('COLA Rate', '\$${ts.colaRate.toStringAsFixed(2)}/day'),
            _infoRow('Allowance Rate', '\$${ts.allowanceRate.toStringAsFixed(2)}/day'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NpupsColors.textPrimary))),
        ],
      ),
    );
  }

  // ── Attendance Editor ─────────────────────────────────────────────────────

  Widget _buildAttendanceEditor(Timesheet ts) {
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_calendar, color: NpupsColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('Attendance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _quickFill(ts),
                  icon: const Icon(Icons.flash_on, size: 14),
                  label: const Text('Quick Fill', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int week = 0; week < 2; week++) ...[
              Text('Week ${week + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: NpupsColors.primary)),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(7, (d) {
                    final idx = week * 7 + d;
                    final entry = ts.dailyEntries[idx];
                    final isWeekend = d >= 5;
                    return Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 4, bottom: 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: entry.isPresent ? NpupsColors.success.withValues(alpha: 0.08)
                            : isWeekend ? Colors.grey.withValues(alpha: 0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: entry.isPresent ? NpupsColors.success.withValues(alpha: 0.3) : NpupsColors.border),
                      ),
                      child: Column(
                        children: [
                          Text(dayLabels[d], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isWeekend ? NpupsColors.textSecondary : NpupsColors.primary)),
                          Text(DateFormat('d').format(ts.fortnightStart.add(Duration(days: idx))), style: const TextStyle(fontSize: 9, color: NpupsColors.textSecondary)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _pickTime(ts, idx, true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              decoration: BoxDecoration(color: NpupsColors.inputFill, borderRadius: BorderRadius.circular(4)),
                              child: Center(child: Text(
                                entry.timeIn != null ? '${entry.timeIn!.hour.toString().padLeft(2, '0')}:${entry.timeIn!.minute.toString().padLeft(2, '0')}' : '--:--',
                                style: TextStyle(fontSize: 10, color: entry.timeIn != null ? NpupsColors.success : NpupsColors.textSecondary),
                              )),
                            ),
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () => _pickTime(ts, idx, false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              decoration: BoxDecoration(color: NpupsColors.inputFill, borderRadius: BorderRadius.circular(4)),
                              child: Center(child: Text(
                                entry.timeOut != null ? '${entry.timeOut!.hour.toString().padLeft(2, '0')}:${entry.timeOut!.minute.toString().padLeft(2, '0')}' : '--:--',
                                style: TextStyle(fontSize: 10, color: entry.timeOut != null ? NpupsColors.accent : NpupsColors.textSecondary),
                              )),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyAttendance(Timesheet ts) {
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_today, color: NpupsColors.accent, size: 20),
                SizedBox(width: 8),
                Text('Attendance (Submitted)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            for (int week = 0; week < 2; week++) ...[
              Text('Week ${week + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: NpupsColors.primary)),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(7, (d) {
                    final idx = week * 7 + d;
                    final entry = ts.dailyEntries[idx];
                    return Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 4, bottom: 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: entry.isPresent ? NpupsColors.success.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NpupsColors.border),
                      ),
                      child: Column(
                        children: [
                          Text(dayLabels[d], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
                          const SizedBox(height: 4),
                          Text(entry.timeIn != null ? '${entry.timeIn!.hour.toString().padLeft(2, '0')}:${entry.timeIn!.minute.toString().padLeft(2, '0')}' : '--', style: const TextStyle(fontSize: 10)),
                          Text(entry.timeOut != null ? '${entry.timeOut!.hour.toString().padLeft(2, '0')}:${entry.timeOut!.minute.toString().padLeft(2, '0')}' : '--', style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Allowance & Remarks ───────────────────────────────────────────────────

  Widget _buildAllowanceAndRemarks(Timesheet ts) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Additional Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: ts.allowanceDays > 0 ? ts.allowanceDays.toString() : '',
                    decoration: const InputDecoration(labelText: 'Allowance Days', isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setState(() => ts.allowanceDays = int.tryParse(v) ?? 0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: ts.remarks,
                    decoration: const InputDecoration(labelText: 'Remarks', isDense: true),
                    maxLength: 200,
                    onChanged: (v) => ts.remarks = v,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Totals Card ───────────────────────────────────────────────────────────

  Widget _buildTotalsCard(Timesheet ts) {
    return Card(
      elevation: 2,
      color: NpupsColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Pay Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _totalItem('Days', '${ts.daysWorked}'),
                _totalItem('Wage', '\$${ts.wageTotal.toStringAsFixed(2)}'),
                _totalItem('COLA', '\$${ts.colaTotal.toStringAsFixed(2)}'),
                _totalItem('Allowance', '\$${ts.allowanceTotal.toStringAsFixed(2)}'),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            Text('TOTAL: \$${ts.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _totalItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons(Timesheet ts) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              if (ts.stage == TimesheetStage.notStarted) {
                ts.stage = TimesheetStage.draft;
                ts.updatedAt = DateTime.now();
                _store.updateTimesheet(ts);
              }
              _store.updateTimesheet(ts);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Draft saved'), backgroundColor: NpupsColors.success),
              );
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NpupsColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              if (ts.daysWorked == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter at least one day of attendance'), backgroundColor: NpupsColors.error),
                );
                return;
              }
              // Advance from draft/notStarted to submitted
              ts.stage = TimesheetStage.submitted;
              ts.approvalHistory.add(ApprovalRecord(
                reviewerName: widget.user.fullName,
                reviewerRole: 'Worker',
                state: ApprovalState.approved,
                note: 'Submitted for review',
                timestamp: DateTime.now(),
              ));
              ts.updatedAt = DateTime.now();
              _store.updateTimesheet(ts);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Timesheet submitted for review'), backgroundColor: NpupsColors.success),
              );
            },
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Submit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NpupsColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Approval History ──────────────────────────────────────────────────────

  Widget _buildApprovalHistory(Timesheet ts) {
    if (ts.approvalHistory.isEmpty) return const SizedBox();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approval History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
            const SizedBox(height: 12),
            ...ts.approvalHistory.map((record) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    record.state == ApprovalState.approved ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: record.state == ApprovalState.approved ? NpupsColors.success : NpupsColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${record.reviewerName} (${record.reviewerRole})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if (record.note != null) Text(record.note!, style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(DateFormat('dd/MM HH:mm').format(record.timestamp), style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _quickFill(Timesheet ts) {
    setState(() {
      for (int i = 0; i < 14; i++) {
        if ((i % 7) < 5) {
          ts.dailyEntries[i].timeIn = const TimeOfDay(hour: 7, minute: 0);
          ts.dailyEntries[i].timeOut = const TimeOfDay(hour: 15, minute: 0);
        }
      }
    });
  }

  Future<void> _pickTime(Timesheet ts, int dayIndex, bool isTimeIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isTimeIn
          ? (ts.dailyEntries[dayIndex].timeIn ?? const TimeOfDay(hour: 7, minute: 0))
          : (ts.dailyEntries[dayIndex].timeOut ?? const TimeOfDay(hour: 15, minute: 0)),
    );
    if (picked != null) {
      setState(() {
        if (isTimeIn) {
          ts.dailyEntries[dayIndex].timeIn = picked;
        } else {
          ts.dailyEntries[dayIndex].timeOut = picked;
        }
      });
    }
  }
}
