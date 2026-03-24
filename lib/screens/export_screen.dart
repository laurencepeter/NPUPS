import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/excel_export_service.dart';
import 'dart:typed_data';
import 'dart:html' as html;

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Excel Timesheet Export Screen
// Export by individual worker or batch export by corporation.
// Each worker gets their own full timesheet section in the document.
// ──────────────────────────────────────────────────────────────────────────────

enum ExportMode { singleWorker, batchCorporation }

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final WorkerDataStore _store = WorkerDataStore();
  ExportMode _exportMode = ExportMode.singleWorker;
  String? _selectedCorpId;
  String? _selectedWorkerId;
  String _groupNumber = '1';
  DateTime _fortnightStart = _getLastMonday();
  bool _exporting = false;
  bool _exported = false;

  static DateTime _getLastMonday() {
    final now = DateTime.now();
    final daysFromMonday = (now.weekday - DateTime.monday) % 7;
    return DateTime(now.year, now.month, now.day - daysFromMonday);
  }

  List<MapEntry<String, String>> get _corporations {
    final corps = <String, String>{};
    for (final w in _store.workers) {
      corps[w.corporationId] = w.corporationName;
    }
    return corps.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  List<Worker> get _corpWorkers {
    if (_selectedCorpId == null) return [];
    return _store.getByCorpId(_selectedCorpId!);
  }

  Worker? get _selectedWorker {
    if (_selectedWorkerId == null) return null;
    return _store.getById(_selectedWorkerId!);
  }

  void _pickFortnightStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fortnightStart,
      firstDate: DateTime(2023),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      final daysFromMonday = (picked.weekday - DateTime.monday) % 7;
      setState(() {
        _fortnightStart = picked.subtract(Duration(days: daysFromMonday));
      });
    }
  }

  void _export() async {
    final corpName = _corporations.firstWhere((c) => c.key == _selectedCorpId).value;

    if (_exportMode == ExportMode.singleWorker) {
      if (_selectedWorker == null) return;
    } else {
      if (_corpWorkers.isEmpty) return;
    }

    setState(() {
      _exporting = true;
      _exported = false;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    try {
      late final Uint8List bytes;
      late final String fileName;
      final dateStr = DateFormat('yyyyMMdd').format(_fortnightStart);

      if (_exportMode == ExportMode.singleWorker) {
        final worker = _selectedWorker!;
        bytes = ExcelExportService.generateSingleWorkerTimesheet(
          worker: worker,
          groupNumber: _groupNumber,
          corporationName: corpName,
          fortnightStart: _fortnightStart,
        );
        final safeName = worker.fullName.replaceAll(' ', '_');
        fileName = 'NPUPS_Timesheet_${safeName}_$dateStr.xlsx';
      } else {
        bytes = ExcelExportService.generateBatchTimesheet(
          workers: _corpWorkers,
          groupNumber: _groupNumber,
          corporationName: corpName,
          fortnightStart: _fortnightStart,
        );
        final safeCorpName = corpName.replaceAll(' ', '_');
        fileName = 'NPUPS_Timesheet_Batch_${safeCorpName}_Group${_groupNumber}_$dateStr.xlsx';
      }

      // Download via browser
      final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      setState(() {
        _exporting = false;
        _exported = true;
      });

      if (!mounted) return;
      final workerCount = _exportMode == ExportMode.singleWorker ? 1 : _corpWorkers.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported $workerCount timesheet${workerCount > 1 ? 's' : ''} successfully'),
          backgroundColor: NpupsColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: NpupsColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  bool get _canExport {
    if (_selectedCorpId == null || _exporting) return false;
    if (_exportMode == ExportMode.singleWorker) return _selectedWorker != null;
    return _corpWorkers.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final fortnightEnd = _fortnightStart.add(const Duration(days: 13));
    final workers = _corpWorkers;

    return Scaffold(
      backgroundColor: NpupsColors.surface,
      appBar: AppBar(
        backgroundColor: NpupsColors.primary,
        title: const Text('Export Timesheet', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Export mode selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.swap_horiz, color: NpupsColors.accent),
                      SizedBox(width: 10),
                      Text('Export Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeCard(
                          ExportMode.singleWorker,
                          'Single Worker',
                          'Export one worker\'s timesheet',
                          Icons.person,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildModeCard(
                          ExportMode.batchCorporation,
                          'Batch Export',
                          'All workers in a corporation',
                          Icons.groups,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Export config card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.table_chart, color: NpupsColors.accent),
                      SizedBox(width: 10),
                      Text('Export Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Corporation
                  const Text('Corporation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedCorpId,
                    decoration: const InputDecoration(hintText: 'Select a corporation'),
                    items: _corporations
                        .map((c) => DropdownMenuItem(value: c.key, child: Text(c.value, style: const TextStyle(fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedCorpId = v;
                      _selectedWorkerId = null;
                      _exported = false;
                    }),
                  ),
                  const SizedBox(height: 16),

                  // Worker selector (single mode only)
                  if (_exportMode == ExportMode.singleWorker && _selectedCorpId != null) ...[
                    const Text('Worker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedWorkerId,
                      decoration: const InputDecoration(hintText: 'Select a worker'),
                      items: workers
                          .map((w) => DropdownMenuItem(
                            value: w.id,
                            child: Text('${w.fullName} — ${w.position}', style: const TextStyle(fontSize: 14)),
                          ))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedWorkerId = v;
                        _exported = false;
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Group Number
                  const Text('Group Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextFormField(
                    initialValue: _groupNumber,
                    decoration: const InputDecoration(hintText: 'e.g. 1, 2, 3'),
                    onChanged: (v) => _groupNumber = v,
                  ),
                  const SizedBox(height: 16),

                  // Fortnight dates
                  const Text('Fortnight Period', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textSecondary)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickFortnightStart,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: NpupsColors.inputFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NpupsColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: NpupsColors.accent),
                          const SizedBox(width: 10),
                          Text(
                            '${DateFormat('d MMM yyyy').format(_fortnightStart)} - ${DateFormat('d MMM yyyy').format(fortnightEnd)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit, size: 16, color: NpupsColors.textHint),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Workers preview
            if (_selectedCorpId != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people, color: NpupsColors.accent),
                        const SizedBox(width: 10),
                        Text(
                          _exportMode == ExportMode.singleWorker
                              ? 'Selected Worker'
                              : 'Workers to Export (${workers.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_exportMode == ExportMode.singleWorker) ...[
                      if (_selectedWorker == null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Select a worker above to export their timesheet.', style: TextStyle(color: NpupsColors.textSecondary)),
                        )
                      else
                        _buildWorkerRow(_selectedWorker!),
                    ] else ...[
                      if (workers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No workers registered for this corporation.', style: TextStyle(color: NpupsColors.textSecondary)),
                        )
                      else
                        ...workers.map((w) => _buildWorkerRow(w)),
                    ],
                    if (_exportMode == ExportMode.batchCorporation && workers.isNotEmpty) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: NpupsColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Each worker will have their own complete timesheet section in the document for easy printing.',
                              style: TextStyle(fontSize: 12, color: NpupsColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Export button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _canExport ? _export : null,
                icon: _exporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_exported ? Icons.check_circle : Icons.download, size: 20),
                label: Text(
                  _exporting
                      ? 'Generating...'
                      : _exported
                          ? 'Exported Successfully'
                          : _exportMode == ExportMode.singleWorker
                              ? 'Export Worker Timesheet'
                              : 'Export All Workers (.xlsx)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _exported ? NpupsColors.success : NpupsColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(ExportMode mode, String title, String subtitle, IconData icon) {
    final isSelected = _exportMode == mode;
    return InkWell(
      onTap: () => setState(() {
        _exportMode = mode;
        _selectedWorkerId = null;
        _exported = false;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? NpupsColors.accent.withValues(alpha: 0.08) : NpupsColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? NpupsColors.accent : NpupsColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? NpupsColors.accent : NpupsColors.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? NpupsColors.accent : NpupsColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerRow(Worker w) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: NpupsColors.accent.withValues(alpha: 0.1),
            child: Text(w.initials, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: NpupsColors.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('${w.position}  •  ${w.nisNumber}', style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
              ],
            ),
          ),
          Text('\$${(10 * w.wageRate + 10 * w.colaRate).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.accent)),
        ],
      ),
    );
  }
}
