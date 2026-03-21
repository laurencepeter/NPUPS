import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/excel_export_service.dart';
import 'dart:html' as html;

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Excel Timesheet Export Screen
// Select corporation, group, fortnight dates, and export matching template.
// ──────────────────────────────────────────────────────────────────────────────

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final WorkerDataStore _store = WorkerDataStore();
  String? _selectedCorpId;
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

  List<Worker> get _selectedWorkers {
    if (_selectedCorpId == null) return [];
    return _store.getByCorpId(_selectedCorpId!);
  }

  void _pickFortnightStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fortnightStart,
      firstDate: DateTime(2023),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      // Snap to Monday
      final daysFromMonday = (picked.weekday - DateTime.monday) % 7;
      setState(() {
        _fortnightStart = picked.subtract(Duration(days: daysFromMonday));
      });
    }
  }

  void _export() async {
    if (_selectedCorpId == null || _selectedWorkers.isEmpty) return;

    setState(() {
      _exporting = true;
      _exported = false;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final corpName = _corporations.firstWhere((c) => c.key == _selectedCorpId).value;
      final bytes = ExcelExportService.generateTimesheet(
        workers: _selectedWorkers,
        groupNumber: _groupNumber,
        corporationName: corpName,
        fortnightStart: _fortnightStart,
      );

      // Download via browser
      final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final dateStr = DateFormat('yyyyMMdd').format(_fortnightStart);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'NPUPS_Timesheet_Group${_groupNumber}_$dateStr.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);

      setState(() {
        _exporting = false;
        _exported = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Timesheet exported successfully'),
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

  @override
  Widget build(BuildContext context) {
    final fortnightEnd = _fortnightStart.add(const Duration(days: 13));
    final workers = _selectedWorkers;

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
                    onChanged: (v) => setState(() => _selectedCorpId = v),
                  ),
                  const SizedBox(height: 16),

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
                        Text('Workers to Export (${workers.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (workers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No workers registered for this corporation.', style: TextStyle(color: NpupsColors.textSecondary)),
                      )
                    else
                      ...workers.map((w) => Padding(
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
                      )),
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
                onPressed: _selectedCorpId == null || workers.isEmpty || _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_exported ? Icons.check_circle : Icons.download, size: 20),
                label: Text(
                  _exporting ? 'Generating...' : _exported ? 'Exported Successfully' : 'Export .xlsx Timesheet',
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
}
