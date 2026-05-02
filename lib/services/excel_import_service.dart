// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Parses .xlsx files (generated from the template) back into timesheet data.
// Reads worker details, time-in/time-out entries, allowance days, and remarks
// from known cell positions in the standard WorkForce template layout.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../models/timesheet_model.dart';

/// Result of parsing a single worker section from an uploaded Excel file.
class ParsedTimesheetEntry {
  final String? workerId;
  final String? workerName;
  final String? nisNumber;
  final String? idNumber;
  final String? position;
  final String? corporationName;
  final String? groupNumber;
  final DateTime? fortnightStart;
  final DateTime? fortnightEnd;
  final List<TimesheetDailyEntry> dailyEntries;
  final int allowanceDays;
  final String remarks;
  final double? wageRate;
  final double? colaRate;
  final double? allowanceRate;
  final List<String> warnings;

  ParsedTimesheetEntry({
    this.workerId,
    this.workerName,
    this.nisNumber,
    this.idNumber,
    this.position,
    this.corporationName,
    this.groupNumber,
    this.fortnightStart,
    this.fortnightEnd,
    required this.dailyEntries,
    this.allowanceDays = 0,
    this.remarks = '',
    this.wageRate,
    this.colaRate,
    this.allowanceRate,
    this.warnings = const [],
  });

  int get daysWorked => dailyEntries.where((d) => d.isPresent).length;
  double get wageTotal => daysWorked * (wageRate ?? 0);
  double get colaTotal => daysWorked * (colaRate ?? 0);
  double get allowanceTotal => allowanceDays * (allowanceRate ?? 0);
  double get grandTotal => wageTotal + colaTotal + allowanceTotal;
}

/// Overall result from importing an Excel file.
class ExcelImportResult {
  final bool success;
  final List<ParsedTimesheetEntry> entries;
  final List<String> errors;

  const ExcelImportResult({
    required this.success,
    this.entries = const [],
    this.errors = const [],
  });
}

class ExcelImportService {
  /// Parse an uploaded Excel file and extract timesheet entries.
  /// Supports both single-worker and batch (multi-worker) templates.
  static ExcelImportResult parseTimesheetFile(Uint8List fileBytes) {
    try {
      final excel = Excel.decodeBytes(fileBytes);
      final errors = <String>[];
      final entries = <ParsedTimesheetEntry>[];

      // Find the Timesheet sheet (or use the first sheet)
      Sheet? sheet;
      if (excel.tables.containsKey('Timesheet')) {
        sheet = excel.tables['Timesheet'];
      } else if (excel.tables.isNotEmpty) {
        sheet = excel.tables.values.first;
      }

      if (sheet == null) {
        return const ExcelImportResult(
          success: false,
          errors: ['No worksheet found in the uploaded file.'],
        );
      }

      final rows = sheet.rows;
      if (rows.isEmpty) {
        return const ExcelImportResult(
          success: false,
          errors: ['The uploaded file contains no data.'],
        );
      }

      // Scan through rows looking for worker sections.
      // Each section starts with "TIMESHEET" in a merged cell.
      int i = 0;
      while (i < rows.length) {
        final cellVal = _getCellString(rows, i, 0).trim().toUpperCase();

        if (cellVal == 'TIMESHEET') {
          final result = _parseWorkerSection(rows, i);
          if (result != null) {
            entries.add(result.entry);
            errors.addAll(result.entry.warnings);
            i = result.nextRow;
            continue;
          }
        }
        i++;
      }

      if (entries.isEmpty) {
        return ExcelImportResult(
          success: false,
          errors: [
            'No timesheet data found. Ensure the file uses the WorkForce template format.',
            ...errors,
          ],
        );
      }

      return ExcelImportResult(
        success: true,
        entries: entries,
        errors: errors,
      );
    } catch (e) {
      return ExcelImportResult(
        success: false,
        errors: ['Failed to read Excel file: $e'],
      );
    }
  }

  /// Parse one worker section starting from the "TIMESHEET" header row.
  static _ParseResult? _parseWorkerSection(List<List<Data?>> rows, int startRow) {
    final warnings = <String>[];
    int r = startRow;

    // Row 0: "TIMESHEET"
    r++;

    // Row 1: header text
    if (r >= rows.length) return null;
    r++;

    // Row 2: Corporation name | Group #
    if (r >= rows.length) return null;
    final corpName = _getCellString(rows, r, 0).trim();
    final groupCell = _getCellString(rows, r, 11).trim();
    final groupNumber = _extractGroupNumber(groupCell);
    r++;

    // Row 3: Fortnight dates
    if (r >= rows.length) return null;
    final fortnightText = _getCellString(rows, r, 0).trim();
    final dates = _parseFortnightDates(fortnightText);
    r++;

    // Row 4: Worker name
    if (r >= rows.length) return null;
    final workerLine = _getCellString(rows, r, 0).trim();
    final workerName = workerLine.startsWith('Worker:')
        ? workerLine.substring(7).trim()
        : workerLine;
    r++;

    // Row 5: Worker ID line (optional — only in template)
    String? workerId;
    String? nisNumber;
    String? idNumber;
    if (r < rows.length) {
      final idLine = _getCellString(rows, r, 0).trim();
      if (idLine.startsWith('Worker ID:')) {
        final parsed = _parseWorkerIdLine(idLine);
        workerId = parsed['workerId'];
        nisNumber = parsed['nisNumber'];
        idNumber = parsed['idNumber'];
        r++;
      }
    }

    // Skip blank rows until column headers
    while (r < rows.length) {
      final cell = _getCellString(rows, r, 0).trim().toUpperCase();
      if (cell.contains('DATE') || cell.contains('POSITION')) break;
      r++;
    }
    if (r >= rows.length) return null;

    // Column headers row
    r++;

    // Rate sub-header row (WAGE / COLA / ALLOW)
    r++;

    // Rate values row (optional)
    double? wageRate;
    double? colaRate;
    double? allowanceRate;
    if (r < rows.length) {
      final rateCell = _getCellString(rows, r, 16).trim();
      if (rateCell.toLowerCase().contains('rate')) {
        wageRate = _extractRate(rateCell);
        colaRate = _extractRate(_getCellString(rows, r, 17).trim());
        allowanceRate = _extractRate(_getCellString(rows, r, 18).trim());
        r++;
      }
    }

    // ── Time In Row ──────────────────────────────────────────────────────
    if (r >= rows.length) return null;
    final timeInLabel = _getCellString(rows, r, 0).trim().toLowerCase();
    if (!timeInLabel.contains('time in')) {
      // Try scanning forward a bit
      for (int scan = 0; scan < 3 && r + scan < rows.length; scan++) {
        if (_getCellString(rows, r + scan, 0).trim().toLowerCase().contains('time in')) {
          r += scan;
          break;
        }
      }
    }

    final timeInRow = r;
    final timeIns = <TimeOfDay?>[];
    for (int d = 0; d < 14; d++) {
      timeIns.add(_parseTime(_getCellString(rows, r, 1 + d).trim()));
    }

    // Read allowance days and remarks from time-in row
    final allowanceDaysStr = _getCellString(rows, r, 19).trim();
    final allowanceDays = int.tryParse(allowanceDaysStr) ?? 0;
    final remarks = _getCellString(rows, r, 21).trim();

    // Also try to read NIS/ID from column 22 if not already found
    if (nisNumber == null || idNumber == null) {
      final nameCell = _getCellString(rows, r, 22).trim();
      if (nameCell.contains('NAME:') && workerName.isEmpty) {
        // Could extract name here
      }
    }

    r++;

    // ── Time Out Row ─────────────────────────────────────────────────────
    if (r >= rows.length) return null;
    final timeOuts = <TimeOfDay?>[];
    for (int d = 0; d < 14; d++) {
      timeOuts.add(_parseTime(_getCellString(rows, r, 1 + d).trim()));
    }

    // Try to read ID/NIS from column 22 of time-out row
    if (nisNumber == null || idNumber == null) {
      final idCell = _getCellString(rows, r, 22).trim();
      final parsedIds = _parseIdNisCell(idCell);
      idNumber ??= parsedIds['idNumber'];
      nisNumber ??= parsedIds['nisNumber'];
    }

    r++;

    // ── Position Row ─────────────────────────────────────────────────────
    String? position;
    if (r < rows.length) {
      final posVal = _getCellString(rows, r, 0).trim();
      if (posVal.isNotEmpty &&
          !posVal.toUpperCase().contains('CE SUPERVISOR') &&
          !posVal.toUpperCase().contains('TIMESHEET')) {
        position = posVal;
      }
      r++;
    }

    // Build daily entries
    final dailyEntries = <TimesheetDailyEntry>[];
    for (int d = 0; d < 14; d++) {
      dailyEntries.add(TimesheetDailyEntry(
        timeIn: timeIns.length > d ? timeIns[d] : null,
        timeOut: timeOuts.length > d ? timeOuts[d] : null,
      ));
    }

    // Validate
    final daysWithData = dailyEntries.where((d) => d.isPresent).length;
    if (daysWithData == 0) {
      warnings.add('No time entries found for ${workerName.isNotEmpty ? workerName : "unknown worker"}.');
    }

    // Skip past signature block to find next section
    while (r < rows.length) {
      final cell = _getCellString(rows, r, 0).trim().toUpperCase();
      if (cell == 'TIMESHEET') break;
      r++;
    }

    return _ParseResult(
      entry: ParsedTimesheetEntry(
        workerId: workerId,
        workerName: workerName.isNotEmpty ? workerName : null,
        nisNumber: nisNumber,
        idNumber: idNumber,
        position: position,
        corporationName: corpName.isNotEmpty ? corpName : null,
        groupNumber: groupNumber,
        fortnightStart: dates?.$1,
        fortnightEnd: dates?.$2,
        dailyEntries: dailyEntries,
        allowanceDays: allowanceDays,
        remarks: remarks,
        wageRate: wageRate,
        colaRate: colaRate,
        allowanceRate: allowanceRate,
        warnings: warnings,
      ),
      nextRow: r,
    );
  }

  // ── Helper Methods ──────────────────────────────────────────────────────

  static String _getCellString(List<List<Data?>> rows, int row, int col) {
    if (row >= rows.length) return '';
    final r = rows[row];
    if (col >= r.length) return '';
    final cell = r[col];
    if (cell == null || cell.value == null) return '';
    return cell.value.toString();
  }

  static String? _extractGroupNumber(String text) {
    // "GROUP #: 1" -> "1"
    final match = RegExp(r'GROUP\s*#?\s*:?\s*(\S+)', caseSensitive: false)
        .firstMatch(text);
    return match?.group(1);
  }

  static (DateTime, DateTime)? _parseFortnightDates(String text) {
    // "Fortnight: 17/03/2026 - 30/03/2026"
    final match = RegExp(r'(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})')
        .firstMatch(text);
    if (match == null) return null;

    try {
      final fmt = _dateFormat;
      final start = fmt.parse(match.group(1)!);
      final end = fmt.parse(match.group(2)!);
      return (start, end);
    } catch (_) {
      return null;
    }
  }

  static final _dateFormat = _SafeDateFormat('dd/MM/yyyy');

  static Map<String, String?> _parseWorkerIdLine(String text) {
    // "Worker ID: WRK-001 | NIS: NIS-2024-00147 | ID#: ID-TT-198803150"
    String? extract(String label) {
      final match = RegExp('$label\\s*:?\\s*([^|]+)', caseSensitive: false)
          .firstMatch(text);
      return match?.group(1)?.trim();
    }

    return {
      'workerId': extract('Worker ID'),
      'nisNumber': extract('NIS'),
      'idNumber': extract('ID#'),
    };
  }

  static Map<String, String?> _parseIdNisCell(String text) {
    // "ID#: ID-TT-198803150\nNIS#: NIS-2024-00147"
    String? extract(String label) {
      final match = RegExp('$label\\s*:?\\s*(\\S+)', caseSensitive: false)
          .firstMatch(text);
      return match?.group(1)?.trim();
    }

    return {
      'idNumber': extract('ID#'),
      'nisNumber': extract('NIS#'),
    };
  }

  static double? _extractRate(String text) {
    // "Rate: 150" -> 150.0
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    return match != null ? double.tryParse(match.group(1)!) : null;
  }

  static TimeOfDay? _parseTime(String text) {
    if (text.isEmpty) return null;

    // Handle "7:00", "15:00", "07:00", "7:30 AM" etc.
    final match24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match24 != null) {
      final h = int.tryParse(match24.group(1)!);
      final m = int.tryParse(match24.group(2)!);
      if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return TimeOfDay(hour: h, minute: m);
      }
    }

    // Handle "7:00 AM" / "3:00 PM"
    final matchAmPm = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(text);
    if (matchAmPm != null) {
      var h = int.tryParse(matchAmPm.group(1)!) ?? 0;
      final m = int.tryParse(matchAmPm.group(2)!) ?? 0;
      final period = matchAmPm.group(3)!.toUpperCase();
      if (period == 'PM' && h < 12) h += 12;
      if (period == 'AM' && h == 12) h = 0;
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return TimeOfDay(hour: h, minute: m);
      }
    }

    // Try just a number (treat as hours, e.g. "7" -> 7:00)
    final hourOnly = int.tryParse(text);
    if (hourOnly != null && hourOnly >= 0 && hourOnly <= 23) {
      return TimeOfDay(hour: hourOnly, minute: 0);
    }

    return null;
  }
}

class _ParseResult {
  final ParsedTimesheetEntry entry;
  final int nextRow;

  _ParseResult({required this.entry, required this.nextRow});
}

/// Safe wrapper around DateFormat to avoid crash if parse fails.
class _SafeDateFormat {
  final String pattern;
  _SafeDateFormat(this.pattern);

  DateTime parse(String input) {
    // Manual parse for dd/MM/yyyy
    final parts = input.split('/');
    if (parts.length != 3) throw FormatException('Invalid date: $input');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final year = int.parse(parts[2]);
    return DateTime(year, month, day);
  }
}
