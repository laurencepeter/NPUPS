// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Accounts Review Screen
// Receives HR-approved timesheets. Verifies pay calculations, deductions,
// bank details. Approve for payment or reject back to HR.
// Triggers .xlsx export matching the exact NPUPS template format.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../services/timesheet_data_store.dart';
import '../services/excel_export_service.dart';
import 'package:file_saver/file_saver.dart';

class AccountsReviewScreen extends StatefulWidget {
  final NpupsUser user;
  const AccountsReviewScreen({super.key, required this.user});

  @override
  State<AccountsReviewScreen> createState() => _AccountsReviewScreenState();
}

class _AccountsReviewScreenState extends State<AccountsReviewScreen>
    with SingleTickerProviderStateMixin {
  final TimesheetDataStore _store = TimesheetDataStore();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Timesheet> get _pendingQueue => _store.getByStage(TimesheetStage.accountsProcessing);
  List<Timesheet> get _approvedQueue => _store.getByStage(TimesheetStage.approvedForPayment);
  List<Timesheet> get _exportedQueue {
    return _store.timesheets.where((t) =>
        t.stage == TimesheetStage.exported || t.stage == TimesheetStage.chequePrinting).toList();
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
            Text('Accounts Processing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Pay Verification & Export', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Exported'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildPendingTab(),
              _buildApprovedTab(),
              _buildExportedTab(),
            ],
          );
        },
      ),
    );
  }

  // ── Pending Tab ───────────────────────────────────────────────────────────

  Widget _buildPendingTab() {
    final queue = _pendingQueue;
    if (queue.isEmpty) {
      return const Center(child: Text('No timesheets pending verification', style: TextStyle(color: NpupsColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queue.length,
      itemBuilder: (context, i) => _buildPendingCard(queue[i]),
    );
  }

  Widget _buildPendingCard(Timesheet ts) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: NpupsColors.accent.withValues(alpha: 0.1),
                  child: const Icon(Icons.account_balance, color: NpupsColors.accent, size: 20),
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

            // Pay verification
            const Text('Pay Verification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
            const SizedBox(height: 8),
            _verifyRow('Days Worked', '${ts.daysWorked}'),
            _verifyRow('Wage', '${ts.daysWorked} x \$${ts.wageRate.toStringAsFixed(0)} = \$${ts.wageTotal.toStringAsFixed(2)}'),
            _verifyRow('COLA', '${ts.daysWorked} x \$${ts.colaRate.toStringAsFixed(0)} = \$${ts.colaTotal.toStringAsFixed(2)}'),
            _verifyRow('Allowance', '${ts.allowanceDays} x \$${ts.allowanceRate.toStringAsFixed(0)} = \$${ts.allowanceTotal.toStringAsFixed(2)}'),
            const Divider(height: 12),
            _verifyRow('GRAND TOTAL', '\$${ts.grandTotal.toStringAsFixed(2)}', bold: true),
            const SizedBox(height: 12),

            // Bank details
            const Text('Bank Details (Direct Deposit)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NpupsColors.primary)),
            const SizedBox(height: 4),
            _verifyRow('Bank', ts.bankName),
            _verifyRow('Account #', ts.accountNumber),
            _verifyRow('Branch', ts.branchName),
            const SizedBox(height: 12),

            // HR approval note
            if (ts.approvalHistory.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: NpupsColors.success.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: NpupsColors.success),
                    const SizedBox(width: 6),
                    Text('HR: ${ts.approvalHistory.last.note ?? 'Approved'}', style: const TextStyle(fontSize: 11, color: NpupsColors.success)),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectTimesheet(ts),
                    icon: const Icon(Icons.reply, size: 16, color: NpupsColors.error),
                    label: const Text('Reject to HR', style: TextStyle(color: NpupsColors.error, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: NpupsColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _store.advanceStage(ts.id, widget.user.fullName, 'Accounts', note: 'Pay calculations verified');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${ts.workerName} approved for payment'), backgroundColor: NpupsColors.success),
                      );
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve for Payment', style: TextStyle(fontSize: 12)),
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

  // ── Approved Tab ──────────────────────────────────────────────────────────

  Widget _buildApprovedTab() {
    final queue = _approvedQueue;
    if (queue.isEmpty) {
      return const Center(child: Text('No timesheets awaiting export', style: TextStyle(color: NpupsColors.textSecondary)));
    }
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('${queue.length} ready for export', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _exportToXlsx(queue),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export to .xlsx'),
                style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.accent, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: queue.length,
            itemBuilder: (context, i) {
              final ts = queue[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: NpupsColors.success),
                  title: Text(ts.workerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${ts.corporationName} | \$${ts.grandTotal.toStringAsFixed(2)}'),
                  trailing: Text('Group ${ts.groupNumber}', style: const TextStyle(color: NpupsColors.textSecondary)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Exported Tab ──────────────────────────────────────────────────────────

  Widget _buildExportedTab() {
    final queue = _exportedQueue;
    if (queue.isEmpty) {
      return const Center(child: Text('No exported timesheets', style: TextStyle(color: NpupsColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: queue.length,
      itemBuilder: (context, i) {
        final ts = queue[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              ts.stage == TimesheetStage.chequePrinting ? Icons.payments : Icons.download_done,
              color: ts.stage.color,
            ),
            title: Text(ts.workerName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${ts.stage.displayName} | \$${ts.grandTotal.toStringAsFixed(2)}'),
            trailing: ts.stage == TimesheetStage.exported
                ? TextButton(
                    onPressed: () {
                      _store.advanceStage(ts.id, widget.user.fullName, 'Accounts', note: 'Direct deposit initiated');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${ts.workerName} — direct deposit initiated'), backgroundColor: NpupsColors.success),
                      );
                    },
                    child: const Text('Initiate Deposit', style: TextStyle(fontSize: 12)),
                  )
                : const Icon(Icons.done_all, color: NpupsColors.success, size: 20),
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _verifyRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: NpupsColors.textSecondary, fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500))),
        ],
      ),
    );
  }

  void _rejectTimesheet(Timesheet ts) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject to HR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rejecting ${ts.workerName}\'s timesheet back to HR.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Reason *', hintText: 'e.g., Bank account mismatch'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              _store.rejectTimesheet(ts.id, widget.user.fullName, 'Accounts', controller.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${ts.workerName}\'s timesheet rejected to HR'), backgroundColor: NpupsColors.warning),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToXlsx(List<Timesheet> timesheets) async {
    if (timesheets.isEmpty) return;

    // Build Worker objects from timesheets for the export service
    final workers = timesheets.map((ts) => Worker(
      id: ts.workerId,
      fullName: ts.workerName,
      nisNumber: ts.nisNumber,
      dateOfBirth: DateTime(1990, 1, 1),
      position: ts.position,
      idNumber: ts.idNumber,
      corporationId: ts.corporationId,
      corporationName: ts.corporationName,
      electoralDistrict: ts.electoralDistrict,
      wageRate: ts.wageRate,
      colaRate: ts.colaRate,
      allowanceRate: ts.allowanceRate,
      bankInfo: BankInfo(bankName: ts.bankName, accountNumber: ts.accountNumber, branchName: ts.branchName),
      documents: {},
      dateRegistered: DateTime.now(),
    )).toList();

    final bytes = ExcelExportService.generateTimesheet(
      workers: workers,
      groupNumber: timesheets.first.groupNumber,
      corporationName: timesheets.first.corporationName,
      fortnightStart: timesheets.first.fortnightStart,
    );

    final fileName = 'NPUPS_Paysheet_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    await FileSaver.instance.saveFile(name: fileName, bytes: bytes, ext: 'xlsx', mimeType: MimeType.microsoftExcel);

    // Mark all as exported
    for (final ts in timesheets) {
      _store.advanceStage(ts.id, widget.user.fullName, 'Accounts', note: 'Exported to paysheet .xlsx');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${timesheets.length} timesheets exported to $fileName.xlsx'), backgroundColor: NpupsColors.success),
      );
    }
  }
}
