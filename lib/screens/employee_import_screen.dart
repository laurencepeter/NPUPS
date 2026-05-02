// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Upload an Excel workbook with worker biodata. Parses required columns,
// shows a validation preview, and bulk-imports to the worker registry.
// Expected columns (header row 1):
//   Full Name | NIS Number | Date of Birth (dd/mm/yyyy) | Position |
//   ID Number | Corporation ID | Corporation Name | Electoral District |
//   Wage Rate | COLA Rate | Allowance Rate |
//   Bank Name | Account Number | Branch Name |
//   Phone | Address | BIR Number | Start Date | Reference Number
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/audit_service.dart';
import '../models/audit_model.dart';
import '../theme/app_theme.dart';

class EmployeeImportScreen extends StatefulWidget {
  final AppUser currentUser;

  const EmployeeImportScreen({super.key, required this.currentUser});

  @override
  State<EmployeeImportScreen> createState() => _EmployeeImportScreenState();
}

class _EmployeeImportScreenState extends State<EmployeeImportScreen> {
  final WorkerDataStore _workerStore = WorkerDataStore();
  final AuditService _auditService = AuditService();

  _ImportState _importState = _ImportState.idle;
  String? _fileName;
  List<_ParsedEmployee> _parsed = [];
  List<String> _parseErrors = [];
  final Set<int> _selectedRows = {};
  bool _allSelected = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Employees from Excel'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInstructions(isDark),
            const SizedBox(height: 16),
            _buildUploadArea(isDark),
            if (_importState == _ImportState.parsed ||
                _importState == _ImportState.importing) ...[
              const SizedBox(height: 16),
              _buildPreview(isDark),
            ],
            if (_importState == _ImportState.done)
              _buildDoneCard(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Text('Excel Format Requirements',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Row 1 must be the header row with column names'),
            _infoRow('Required: Full Name, NIS Number, Date of Birth, Position, ID Number, Corporation Name'),
            _infoRow('Optional: Corp ID, Electoral District, Wage/COLA/Allowance Rates, Bank info, Phone, Address, BIR Number, Start Date, Reference Number'),
            _infoRow('Date format: DD/MM/YYYY'),
            _infoRow('Duplicate NIS numbers will be flagged and skipped'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 13)),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildUploadArea(bool isDark) {
    return GestureDetector(
      onTap: _importState == _ImportState.importing ? null : _pickFile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _importState == _ImportState.idle
                ? (isDark ? AppColors.darkBorder : AppColors.border)
                : AppColors.accent,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _importState == _ImportState.importing
                  ? Icons.hourglass_empty
                  : Icons.upload_file_outlined,
              size: 40,
              color: _importState == _ImportState.idle
                  ? (isDark ? AppColors.darkTextHint : AppColors.textHint)
                  : AppColors.accent,
            ),
            const SizedBox(height: 8),
            if (_importState == _ImportState.idle)
              Text(
                'Click to select an Excel file (.xlsx)',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary),
              )
            else if (_importState == _ImportState.importing)
              const Text('Processing…')
            else ...[
              Text(
                _fileName ?? '',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                '${_parsed.length} rows parsed, ${_parseErrors.length} errors',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Choose different file'),
                onPressed: _pickFile,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    final validRows = _parsed.where((p) => p.isValid).toList();
    final invalidRows = _parsed.where((p) => !p.isValid).toList();

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary + import button
          Row(
            children: [
              Chip(
                avatar: Icon(Icons.check_circle,
                    size: 14, color: AppColors.success),
                label: Text('${validRows.length} valid',
                    style: const TextStyle(fontSize: 12)),
                backgroundColor:
                    AppColors.success.withValues(alpha: 0.1),
              ),
              const SizedBox(width: 8),
              if (invalidRows.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.warning_amber,
                      size: 14, color: AppColors.warning),
                  label: Text('${invalidRows.length} issues',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor:
                      AppColors.warning.withValues(alpha: 0.1),
                ),
              const Spacer(),
              if (validRows.isNotEmpty)
                ElevatedButton.icon(
                  icon: const Icon(Icons.people_alt_outlined, size: 16),
                  label: Text(
                    _selectedRows.isEmpty
                        ? 'Import All (${validRows.length})'
                        : 'Import Selected (${_selectedRows.length})',
                  ),
                  onPressed: _importState == _ImportState.importing
                      ? null
                      : _doImport,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Table header
          _buildTableHeader(isDark),

          // Rows
          Expanded(
            child: ListView.separated(
              itemCount: _parsed.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
              itemBuilder: (ctx, i) => _buildPreviewRow(_parsed[i], i, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    final bg = isDark ? AppColors.darkCardElevated : AppColors.primary;
    final fg = Colors.white;
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Checkbox(
              value: _allSelected,
              onChanged: (v) {
                setState(() {
                  _allSelected = v ?? false;
                  if (_allSelected) {
                    _selectedRows.addAll(_parsed
                        .asMap()
                        .entries
                        .where((e) => e.value.isValid)
                        .map((e) => e.key));
                  } else {
                    _selectedRows.clear();
                  }
                });
              },
              fillColor: WidgetStateProperty.all(
                  _allSelected ? AppColors.accent : Colors.transparent),
              side: const BorderSide(color: Colors.white54),
            ),
          ),
          Expanded(
              flex: 3,
              child: Text('Full Name',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: fg))),
          Expanded(
              flex: 2,
              child: Text('NIS Number',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: fg))),
          Expanded(
              flex: 2,
              child: Text('Position',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: fg))),
          Expanded(
              flex: 2,
              child: Text('Corporation',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: fg))),
          SizedBox(
            width: 60,
            child: Text('Status',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: fg),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(_ParsedEmployee emp, int index, bool isDark) {
    final isSelected = _selectedRows.contains(index);
    final rowBg = emp.isValid
        ? (isSelected
            ? AppColors.accent.withValues(alpha: 0.07)
            : (isDark ? AppColors.darkCard : Colors.white))
        : (isDark
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.04));

    return InkWell(
      onTap: emp.isValid
          ? () => setState(() {
                if (isSelected) {
                  _selectedRows.remove(index);
                } else {
                  _selectedRows.add(index);
                }
              })
          : null,
      child: Container(
        color: rowBg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: emp.isValid
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedRows.add(index);
                        } else {
                          _selectedRows.remove(index);
                        }
                      }),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  : const Icon(Icons.warning_amber,
                      size: 16, color: AppColors.warning),
            ),
            Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emp.fullName ?? '(missing)',
                      style: TextStyle(
                        fontSize: 12,
                        color: emp.fullName != null
                            ? (isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary)
                            : AppColors.error,
                      ),
                    ),
                    if (emp.errors.isNotEmpty)
                      Text(
                        emp.errors.first,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.error),
                      ),
                  ],
                )),
            Expanded(
                flex: 2,
                child: Text(
                  emp.nisNumber ?? '—',
                  style: const TextStyle(fontSize: 12),
                )),
            Expanded(
                flex: 2,
                child: Text(
                  emp.position ?? '—',
                  style: const TextStyle(fontSize: 12),
                )),
            Expanded(
                flex: 2,
                child: Text(
                  emp.corporationName ?? '—',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
            SizedBox(
              width: 60,
              child: Icon(
                emp.isValid ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: emp.isValid ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneCard(bool isDark) {
    return Card(
      color: AppColors.success.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.success, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.check_circle,
                size: 32, color: AppColors.success),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Import Successful',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.success)),
                  Text(
                    '${_selectedRows.isEmpty ? _parsed.where((p) => p.isValid).length : _selectedRows.length} employees have been added to the registry.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _importState = _ImportState.idle;
                _parsed = [];
                _parseErrors = [];
                _selectedRows.clear();
                _fileName = null;
              }),
              child: const Text('Import Another'),
            ),
          ],
        ),
      ),
    );
  }

  // ── File picking & parsing ────────────────────────────────────────────────

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() {
        _importState = _ImportState.importing;
        _fileName = file.name;
        _parsed = [];
        _parseErrors = [];
        _selectedRows.clear();
      });

      final parsed = await _parseExcel(file.bytes!);

      setState(() {
        _parsed = parsed;
        _importState = _ImportState.parsed;
        _allSelected = false;
        // Auto-select all valid rows
        _selectedRows.addAll(_parsed
            .asMap()
            .entries
            .where((e) => e.value.isValid)
            .map((e) => e.key));
        _allSelected = _selectedRows.length == _parsed.where((p) => p.isValid).length &&
            _selectedRows.isNotEmpty;
      });
    } catch (e) {
      setState(() => _importState = _ImportState.idle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
    }
  }

  Future<List<_ParsedEmployee>> _parseExcel(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    Sheet? sheet = excel.tables.values.firstOrNull;
    if (sheet == null) return [];

    final rows = sheet.rows;
    if (rows.length < 2) return [];

    // Build column index map from header row
    final headers = <String, int>{};
    final headerRow = rows[0];
    for (int i = 0; i < headerRow.length; i++) {
      final h = _cellStr(headerRow, i).trim().toLowerCase();
      if (h.isNotEmpty) headers[h] = i;
    }

    final existingNis =
        _workerStore.workers.map((w) => w.nisNumber).toSet();
    final result = <_ParsedEmployee>[];

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      // Skip fully empty rows
      if (row.every((c) => c == null || c.value == null)) continue;

      final emp = _ParsedEmployee.fromRow(row, headers, existingNis);
      result.add(emp);
    }

    return result;
  }

  static String _cellStr(List<Data?> row, int col) {
    if (col >= row.length) return '';
    return row[col]?.value?.toString() ?? '';
  }

  // ── Import execution ──────────────────────────────────────────────────────

  Future<void> _doImport() async {
    setState(() => _importState = _ImportState.importing);

    final toImport = _selectedRows.isEmpty
        ? _parsed
            .asMap()
            .entries
            .where((e) => e.value.isValid)
            .map((e) => e.value)
            .toList()
        : _selectedRows
            .where((i) => i < _parsed.length && _parsed[i].isValid)
            .map((i) => _parsed[i])
            .toList();

    int imported = 0;
    for (final emp in toImport) {
      final worker = emp.toWorker(_workerStore.generateWorkerId());
      _workerStore.addWorker(worker);
      _auditService.log(
        actor: widget.currentUser,
        action: AuditAction.create,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        note: 'Imported via Excel upload',
        fieldChanges: [
          AuditFieldChange(fieldName: 'Full Name', newValue: worker.fullName),
          AuditFieldChange(fieldName: 'NIS Number', newValue: worker.nisNumber),
          AuditFieldChange(fieldName: 'Position', newValue: worker.position),
          AuditFieldChange(
              fieldName: 'Corporation', newValue: worker.corporationName),
        ],
      );
      imported++;
    }

    if (mounted) {
      setState(() => _importState = _ImportState.done);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$imported employee(s) imported successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

enum _ImportState { idle, importing, parsed, done }

// ── Parsed Employee ────────────────────────────────────────────────────────────

class _ParsedEmployee {
  final String? fullName;
  final String? nisNumber;
  final DateTime? dateOfBirth;
  final String? position;
  final String? idNumber;
  final String? corporationId;
  final String? corporationName;
  final String? electoralDistrict;
  final double? wageRate;
  final double? colaRate;
  final double? allowanceRate;
  final String? bankName;
  final String? accountNumber;
  final String? branchName;
  final String? contact;
  final String? address;
  final String? birNumber;
  final DateTime? startDate;
  final String? referenceNumber;
  final List<String> errors;

  _ParsedEmployee({
    this.fullName,
    this.nisNumber,
    this.dateOfBirth,
    this.position,
    this.idNumber,
    this.corporationId,
    this.corporationName,
    this.electoralDistrict,
    this.wageRate,
    this.colaRate,
    this.allowanceRate,
    this.bankName,
    this.accountNumber,
    this.branchName,
    this.contact,
    this.address,
    this.birNumber,
    this.startDate,
    this.referenceNumber,
    this.errors = const [],
  });

  bool get isValid => errors.isEmpty && fullName != null && nisNumber != null;

  factory _ParsedEmployee.fromRow(
    List<Data?> row,
    Map<String, int> headers,
    Set<String> existingNis,
  ) {
    final errors = <String>[];

    String? cell(String key) {
      final idx = headers[key.toLowerCase()];
      if (idx == null) return null;
      if (idx >= row.length) return null;
      final v = row[idx]?.value?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    double? cellDouble(String key) {
      final v = cell(key);
      if (v == null) return null;
      return double.tryParse(v.replaceAll(',', ''));
    }

    DateTime? cellDate(String key) {
      final v = cell(key);
      if (v == null) return null;
      // Try dd/mm/yyyy
      final m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$').firstMatch(v);
      if (m != null) {
        final day = int.tryParse(m.group(1)!);
        final month = int.tryParse(m.group(2)!);
        final year = int.tryParse(m.group(3)!);
        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
      // Try Excel numeric date
      final numeric = double.tryParse(v);
      if (numeric != null) {
        return DateTime(1899, 12, 30)
            .add(Duration(days: numeric.toInt()));
      }
      return null;
    }

    final fullName = cell('full name') ?? cell('name');
    final nisNumber = cell('nis number') ?? cell('nis');
    final dateOfBirth = cellDate('date of birth') ?? cellDate('dob');
    final position = cell('position') ?? cell('job title');
    final idNumber = cell('id number') ?? cell('id#') ?? cell('national id');
    final corporationName = cell('corporation name') ?? cell('corporation');
    final corporationId = cell('corporation id') ?? cell('corp id');
    final electoralDistrict =
        cell('electoral district') ?? cell('district');

    if (fullName == null || fullName.isEmpty) {
      errors.add('Missing: Full Name');
    }
    if (nisNumber == null || nisNumber.isEmpty) {
      errors.add('Missing: NIS Number');
    } else if (existingNis.contains(nisNumber)) {
      errors.add('Duplicate NIS: $nisNumber already in system');
    }
    if (dateOfBirth == null) {
      errors.add('Missing or invalid: Date of Birth');
    }
    if (position == null || position.isEmpty) {
      errors.add('Missing: Position');
    }
    if (corporationName == null || corporationName.isEmpty) {
      errors.add('Missing: Corporation Name');
    }

    return _ParsedEmployee(
      fullName: fullName,
      nisNumber: nisNumber,
      dateOfBirth: dateOfBirth,
      position: position,
      idNumber: idNumber ?? 'PENDING',
      corporationId: corporationId ?? '0',
      corporationName: corporationName,
      electoralDistrict: electoralDistrict ?? '',
      wageRate: cellDouble('wage rate') ?? cellDouble('wage'),
      colaRate: cellDouble('cola rate') ?? cellDouble('cola'),
      allowanceRate:
          cellDouble('allowance rate') ?? cellDouble('allowance'),
      bankName: cell('bank name') ?? cell('bank'),
      accountNumber: cell('account number') ?? cell('account'),
      branchName: cell('branch name') ?? cell('branch'),
      contact: cell('phone') ?? cell('contact'),
      address: cell('address'),
      birNumber: cell('bir number') ?? cell('bir'),
      startDate: cellDate('start date'),
      referenceNumber: cell('reference number') ?? cell('reference'),
      errors: errors,
    );
  }

  Worker toWorker(String id) {
    return Worker(
      id: id,
      fullName: fullName!,
      nisNumber: nisNumber!,
      dateOfBirth: dateOfBirth ?? DateTime(1990),
      position: position!,
      idNumber: idNumber ?? 'PENDING',
      corporationId: corporationId ?? '0',
      corporationName: corporationName ?? 'Unknown',
      electoralDistrict: electoralDistrict ?? '',
      wageRate: wageRate ?? 150.0,
      colaRate: colaRate ?? 25.0,
      allowanceRate: allowanceRate ?? 40.0,
      bankInfo: BankInfo(
        bankName: bankName ?? 'Unknown',
        accountNumber: accountNumber ?? 'PENDING',
        branchName: branchName ?? '',
      ),
      documents: {
        for (final name in Worker.requiredDocumentNames)
          name: WorkerDocument(name: name),
      },
      dateRegistered: DateTime.now(),
      contact: contact,
      address: address,
      birNumber: birNumber,
      startDate: startDate,
      referenceNumber: referenceNumber,
    );
  }
}
