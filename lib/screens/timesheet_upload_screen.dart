// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Timesheet Upload Screen
// Corporation personnel can:
//   1. Download a blank Excel template pre-filled with worker details
//   2. Upload a completed Excel timesheet (drag-and-drop or file picker)
//   3. Preview parsed data and submit timesheets into the pipeline
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../models/timesheet_model.dart';
import '../services/worker_data_store.dart';
import '../services/timesheet_data_store.dart';
import '../services/excel_template_service.dart';
import '../services/excel_import_service.dart';
import '../services/security_utils.dart';

class TimesheetUploadScreen extends StatefulWidget {
  const TimesheetUploadScreen({super.key});

  @override
  State<TimesheetUploadScreen> createState() => _TimesheetUploadScreenState();
}

class _TimesheetUploadScreenState extends State<TimesheetUploadScreen>
    with SingleTickerProviderStateMixin {
  final WorkerDataStore _workerStore = WorkerDataStore();
  final TimesheetDataStore _timesheetStore = TimesheetDataStore();

  // Template download state
  String? _selectedCorpId;
  String? _selectedWorkerId;
  String _groupNumber = '1';
  DateTime _fortnightStart = _getLastMonday();
  bool _downloadingTemplate = false;

  // Upload state
  bool _isDragHovering = false;
  bool _uploading = false;
  String? _uploadedFileName;
  Uint8List? _uploadedFileBytes;
  ExcelImportResult? _importResult;
  bool _submitting = false;
  bool _submitted = false;

  late AnimationController _pulseController;

  static DateTime _getLastMonday() {
    final now = DateTime.now();
    final daysFromMonday = (now.weekday - DateTime.monday) % 7;
    return DateTime(now.year, now.month, now.day - daysFromMonday);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _corporations {
    final corps = <String, String>{};
    for (final w in _workerStore.workers) {
      corps[w.corporationId] = w.corporationName;
    }
    return corps.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  List<Worker> get _corpWorkers {
    if (_selectedCorpId == null) return [];
    return _workerStore.getByCorpId(_selectedCorpId!);
  }

  Worker? get _selectedWorker {
    if (_selectedWorkerId == null) return null;
    return _workerStore.getById(_selectedWorkerId!);
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

  // ── Template Download ──────────────────────────────────────────────────

  void _downloadTemplate({bool batch = false}) async {
    if (_selectedCorpId == null) return;
    final corpName =
        _corporations.firstWhere((c) => c.key == _selectedCorpId).value;

    setState(() => _downloadingTemplate = true);

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      late final Uint8List bytes;
      late final String fileName;
      final dateStr = DateFormat('yyyyMMdd').format(_fortnightStart);

      if (!batch && _selectedWorker != null) {
        bytes = ExcelTemplateService.generateWorkerTemplate(
          worker: _selectedWorker!,
          groupNumber: _groupNumber,
          corporationName: corpName,
          fortnightStart: _fortnightStart,
        );
        final safeName = SecurityUtils.sanitizeFileName(
          _selectedWorker!.fullName.replaceAll(' ', '_'),
        );
        fileName = 'NPUPS_Template_${safeName}_$dateStr';
      } else {
        bytes = ExcelTemplateService.generateBatchTemplate(
          workers: _corpWorkers,
          groupNumber: _groupNumber,
          corporationName: corpName,
          fortnightStart: _fortnightStart,
        );
        final safeCorpName = SecurityUtils.sanitizeFileName(
          corpName.replaceAll(' ', '_'),
        );
        fileName = 'NPUPS_Template_Batch_${safeCorpName}_$dateStr';
      }

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      setState(() => _downloadingTemplate = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template downloaded: $fileName.xlsx'),
          backgroundColor: NpupsColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      setState(() => _downloadingTemplate = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: NpupsColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── File Upload ────────────────────────────────────────────────────────

  void _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not read file data.'),
            backgroundColor: NpupsColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }

      _processUploadedFile(file.name, file.bytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: $e'),
          backgroundColor: NpupsColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _processUploadedFile(String fileName, Uint8List bytes) {
    setState(() {
      _uploading = true;
      _uploadedFileName = fileName;
      _uploadedFileBytes = bytes;
      _importResult = null;
      _submitted = false;
    });

    // Slight delay for UX feedback
    Future.delayed(const Duration(milliseconds: 600), () {
      final result = ExcelImportService.parseTimesheetFile(bytes);
      if (mounted) {
        setState(() {
          _uploading = false;
          _importResult = result;
        });
      }
    });
  }

  void _clearUpload() {
    setState(() {
      _uploadedFileName = null;
      _uploadedFileBytes = null;
      _importResult = null;
      _submitted = false;
    });
  }

  // ── Submit Timesheets ──────────────────────────────────────────────────

  void _submitTimesheets() async {
    if (_importResult == null || !_importResult!.success) return;

    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 800));

    int created = 0;
    for (final entry in _importResult!.entries) {
      if (entry.daysWorked == 0) continue;

      // Try to match with a registered worker
      Worker? matchedWorker;
      if (entry.workerId != null) {
        matchedWorker = _workerStore.getById(entry.workerId!);
      }
      if (matchedWorker == null && entry.nisNumber != null) {
        try {
          matchedWorker = _workerStore.workers
              .firstWhere((w) => w.nisNumber == entry.nisNumber);
        } catch (_) {}
      }

      final ts = Timesheet(
        id: 'TS-UPL-${DateTime.now().millisecondsSinceEpoch}-$created',
        workerId: matchedWorker?.id ?? entry.workerId ?? 'UNKNOWN',
        workerName: matchedWorker?.fullName ?? entry.workerName ?? 'Unknown',
        position: matchedWorker?.position ?? entry.position ?? 'General Worker',
        idNumber: matchedWorker?.idNumber ?? entry.idNumber ?? '',
        nisNumber: matchedWorker?.nisNumber ?? entry.nisNumber ?? '',
        wageRate: matchedWorker?.wageRate ?? entry.wageRate ?? 150.0,
        colaRate: matchedWorker?.colaRate ?? entry.colaRate ?? 25.0,
        allowanceRate:
            matchedWorker?.allowanceRate ?? entry.allowanceRate ?? 40.0,
        corporationId: matchedWorker?.corporationId ?? _selectedCorpId ?? '',
        corporationName: matchedWorker?.corporationName ??
            entry.corporationName ??
            '',
        electoralDistrict: matchedWorker?.electoralDistrict ?? '',
        groupNumber: entry.groupNumber ?? _groupNumber,
        fortnightStart: entry.fortnightStart ?? _fortnightStart,
        fortnightEnd: entry.fortnightEnd ??
            _fortnightStart.add(const Duration(days: 13)),
        bankName: matchedWorker?.bankInfo.bankName ?? '',
        accountNumber: matchedWorker?.bankInfo.accountNumber ?? '',
        branchName: matchedWorker?.bankInfo.branchName ?? '',
        dailyEntries: entry.dailyEntries,
        allowanceDays: entry.allowanceDays,
        remarks: entry.remarks,
        stage: TimesheetStage.submitted,
      );

      _timesheetStore.addTimesheet(ts);
      created++;
    }

    setState(() {
      _submitting = false;
      _submitted = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '$created timesheet${created != 1 ? 's' : ''} submitted to pipeline.'),
        backgroundColor: NpupsColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fortnightEnd = _fortnightStart.add(const Duration(days: 13));

    return Scaffold(
      backgroundColor: NpupsColors.surface,
      appBar: AppBar(
        backgroundColor: NpupsColors.primary,
        title: const Text('Timesheet Upload',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Step 1: Download Template ────────────────────────────────
            _buildSectionHeader(
              icon: Icons.download,
              title: 'Step 1: Download Template',
              subtitle:
                  'Generate a blank timesheet with worker details pre-filled',
            ),
            const SizedBox(height: 12),
            _buildTemplateDownloadCard(fortnightEnd),
            const SizedBox(height: 24),

            // ── Step 2: Upload Completed Timesheet ──────────────────────
            _buildSectionHeader(
              icon: Icons.upload_file,
              title: 'Step 2: Upload Completed Timesheet',
              subtitle: 'Upload the filled-out Excel file',
            ),
            const SizedBox(height: 12),
            _buildUploadDropZone(),
            const SizedBox(height: 16),

            // ── Step 3: Review & Submit ──────────────────────────────────
            if (_importResult != null) ...[
              _buildSectionHeader(
                icon: Icons.preview,
                title: 'Step 3: Review & Submit',
                subtitle: _importResult!.success
                    ? '${_importResult!.entries.length} timesheet${_importResult!.entries.length != 1 ? 's' : ''} found'
                    : 'Errors found in uploaded file',
              ),
              const SizedBox(height: 12),
              _buildImportResultCard(),
              const SizedBox(height: 16),
              if (_importResult!.success && !_submitted) _buildSubmitButton(),
              if (_submitted) _buildSuccessBanner(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: NpupsColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: NpupsColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: NpupsColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Template Download Card ─────────────────────────────────────────────

  Widget _buildTemplateDownloadCard(DateTime fortnightEnd) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Corporation
          const Text('Corporation',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: NpupsColors.textSecondary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedCorpId,
            decoration: const InputDecoration(hintText: 'Select a corporation'),
            items: _corporations
                .map((c) => DropdownMenuItem(
                    value: c.key,
                    child:
                        Text(c.value, style: const TextStyle(fontSize: 14))))
                .toList(),
            onChanged: (v) => setState(() {
              _selectedCorpId = v;
              _selectedWorkerId = null;
            }),
          ),
          const SizedBox(height: 14),

          // Worker selector (optional — for single template)
          if (_selectedCorpId != null) ...[
            const Text('Worker (optional — leave blank for batch template)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: NpupsColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedWorkerId,
              decoration:
                  const InputDecoration(hintText: 'All workers (batch)'),
              items: [
                const DropdownMenuItem(
                    value: null,
                    child: Text('All workers (batch)',
                        style: TextStyle(fontSize: 14))),
                ..._corpWorkers.map((w) => DropdownMenuItem(
                      value: w.id,
                      child: Text('${w.fullName} — ${w.position}',
                          style: const TextStyle(fontSize: 14)),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedWorkerId = v),
            ),
            const SizedBox(height: 14),
          ],

          // Group Number
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Group #',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: NpupsColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: _groupNumber,
                      decoration: const InputDecoration(hintText: 'e.g. 1'),
                      onChanged: (v) => _groupNumber = v,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fortnight Period',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: NpupsColors.textSecondary)),
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
                            const Icon(Icons.calendar_today,
                                size: 18, color: NpupsColors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${DateFormat('d MMM').format(_fortnightStart)} - ${DateFormat('d MMM yyyy').format(fortnightEnd)}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const Icon(Icons.edit,
                                size: 16, color: NpupsColors.textHint),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Download buttons
          Row(
            children: [
              if (_selectedCorpId != null && _selectedWorkerId != null)
                Expanded(
                  child: _buildDownloadButton(
                    icon: Icons.person,
                    label: 'Download Single Template',
                    onTap: () => _downloadTemplate(batch: false),
                  ),
                ),
              if (_selectedCorpId != null && _selectedWorkerId != null)
                const SizedBox(width: 10),
              if (_selectedCorpId != null)
                Expanded(
                  child: _buildDownloadButton(
                    icon: Icons.groups,
                    label: 'Download Batch Template',
                    onTap: () => _downloadTemplate(batch: true),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: NpupsColors.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _downloadingTemplate ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_downloadingTemplate)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(icon, size: 18, color: NpupsColors.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: NpupsColors.accent),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Upload Drop Zone ───────────────────────────────────────────────────

  Widget _buildUploadDropZone() {
    if (_uploadedFileName != null && !_uploading) {
      return _buildUploadedFileCard();
    }

    return GestureDetector(
      onTap: _uploading ? null : _pickFile,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseValue = _pulseController.value;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: _isDragHovering
                  ? NpupsColors.accent.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isDragHovering
                    ? NpupsColors.accent
                    : NpupsColors.border
                        .withValues(alpha: 0.6 + pulseValue * 0.4),
                width: _isDragHovering ? 2 : 1.5,
                strokeAlign: BorderSide.strokeAlignCenter,
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                if (_uploading) ...[
                  const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: 16),
                  const Text('Processing file...',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NpupsColors.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_upload_outlined,
                        size: 40, color: NpupsColors.accent),
                  ),
                  const SizedBox(height: 16),
                  const Text('Click to upload Excel timesheet',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    'Supports .xlsx files generated from NPUPS template',
                    style: TextStyle(
                        fontSize: 12, color: NpupsColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: NpupsColors.accent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text('Browse Files',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadedFileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NpupsColors.success.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NpupsColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description,
                color: NpupsColors.success, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_uploadedFileName ?? '',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text(
                  _importResult?.success == true
                      ? '${_importResult!.entries.length} worker${_importResult!.entries.length != 1 ? 's' : ''} parsed successfully'
                      : 'File loaded',
                  style: TextStyle(
                    fontSize: 12,
                    color: _importResult?.success == true
                        ? NpupsColors.success
                        : NpupsColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _clearUpload,
            tooltip: 'Remove file',
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Replace', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── Import Results ─────────────────────────────────────────────────────

  Widget _buildImportResultCard() {
    final result = _importResult!;

    if (!result.success) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NpupsColors.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NpupsColors.error.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: NpupsColors.error, size: 20),
                SizedBox(width: 8),
                Text('Import Errors',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: NpupsColors.error)),
              ],
            ),
            const SizedBox(height: 12),
            ...result.errors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('  \u2022  ',
                          style: TextStyle(color: NpupsColors.error)),
                      Expanded(
                          child: Text(e,
                              style: const TextStyle(
                                  fontSize: 13, color: NpupsColors.error))),
                    ],
                  ),
                )),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary header
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: NpupsColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                '${result.entries.length} Timesheet${result.entries.length != 1 ? 's' : ''} Ready',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.errors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 14, color: NpupsColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(e,
                              style: const TextStyle(
                                  fontSize: 11, color: NpupsColors.warning))),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Worker entries preview
          ...result.entries.asMap().entries.map((mapEntry) {
            final idx = mapEntry.key;
            final entry = mapEntry.value;
            return _buildParsedEntryRow(idx + 1, entry);
          }),

          // Totals
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Grand Total:  ',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                '\$${result.entries.fold<double>(0, (sum, e) => sum + e.grandTotal).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: NpupsColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParsedEntryRow(int index, ParsedTimesheetEntry entry) {
    final matched = entry.workerId != null &&
        _workerStore.getById(entry.workerId!) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Index badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NpupsColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$index',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: NpupsColors.accent)),
          ),
          const SizedBox(width: 12),
          // Worker info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.workerName ?? 'Unknown Worker',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (matched)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: NpupsColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Matched',
                            style: TextStyle(
                                fontSize: 9,
                                color: NpupsColors.success,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                Text(
                  '${entry.position ?? "—"} | ${entry.daysWorked} days | ${entry.nisNumber ?? "No NIS"}',
                  style: const TextStyle(
                      fontSize: 11, color: NpupsColors.textSecondary),
                ),
              ],
            ),
          ),
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${entry.grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: NpupsColors.accent)),
              Text('${entry.daysWorked}d worked',
                  style: const TextStyle(
                      fontSize: 10, color: NpupsColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Submit Button ──────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    final validEntries =
        _importResult!.entries.where((e) => e.daysWorked > 0).length;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _submitting ? null : _submitTimesheets,
        icon: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send, size: 20),
        label: Text(
          _submitting
              ? 'Submitting...'
              : 'Submit $validEntries Timesheet${validEntries != 1 ? 's' : ''} to Pipeline',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: NpupsColors.accent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NpupsColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NpupsColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle,
              color: NpupsColors.success, size: 40),
          const SizedBox(height: 12),
          const Text('Timesheets Submitted Successfully',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NpupsColors.success)),
          const SizedBox(height: 6),
          const Text(
            'Timesheets have been added to the approval pipeline and are now pending coordinator review.',
            style: TextStyle(fontSize: 12, color: NpupsColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearUpload,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Upload Another'),
          ),
        ],
      ),
    );
  }
}
