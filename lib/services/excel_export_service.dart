// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Excel Timesheet Export Service
// Generates .xlsx files matching the exact NPUPS timesheet template layout.
// Supports:
//   - Single worker export: one complete timesheet per worker
//   - Batch export by corporation: all workers stacked down the document,
//     each with their own full timesheet section for easy printing
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/worker_model.dart';

class ExcelExportService {
  /// Generate a timesheet for a single worker.
  static Uint8List generateSingleWorkerTimesheet({
    required Worker worker,
    required String groupNumber,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    return _generateTimesheetDocument(
      workers: [worker],
      groupNumber: groupNumber,
      corporationName: corporationName,
      fortnightStart: fortnightStart,
    );
  }

  /// Generate a batch timesheet for all workers in a corporation.
  /// Each worker gets their own complete timesheet section going down the
  /// document so the entire document can be printed in one go.
  static Uint8List generateBatchTimesheet({
    required List<Worker> workers,
    required String groupNumber,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    return _generateTimesheetDocument(
      workers: workers,
      groupNumber: groupNumber,
      corporationName: corporationName,
      fortnightStart: fortnightStart,
    );
  }

  /// Internal: generates a document with one full timesheet section per worker.
  static Uint8List _generateTimesheetDocument({
    required List<Worker> workers,
    required String groupNumber,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    final excel = Excel.createExcel();
    final sheetName = 'Timesheet';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    final fortnightEnd = fortnightStart.add(const Duration(days: 13));
    final dayLabels = ['MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN',
                       'MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN'];
    final dateFormat = DateFormat('dd/MM/yyyy');

    // ── Styles ───────────────────────────────────────────────────────────
    final headerStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
    );
    final subHeaderStyle = CellStyle(
      bold: true,
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
    );
    final colHeaderStyle = CellStyle(
      bold: true,
      fontSize: 8,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      backgroundColorHex: ExcelColor.fromHexString('#D9E1F2'),
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );
    final cellStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );
    final labelStyle = CellStyle(
      fontSize: 9,
      bold: true,
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );
    final sigStyle = CellStyle(
      bold: true,
      fontSize: 9,
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );

    int row = 0;

    for (int wi = 0; wi < workers.length; wi++) {
      final worker = workers[wi];

      // ── Title Block ──────────────────────────────────────────────────
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
      _setCell(sheet, row, 0, 'TIMESHEET', headerStyle);
      row++;

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
      _setCell(sheet, row, 0, 'National Programme for the Upkeep of Public Spaces (NPUPS)', subHeaderStyle);
      row++;

      // Corporation and Group
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row));
      _setCell(sheet, row, 0, corporationName, subHeaderStyle);
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
      _setCell(sheet, row, 11, 'GROUP #: $groupNumber', subHeaderStyle);
      row++;

      // Fortnight dates
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
      _setCell(sheet, row, 0,
          'Fortnight: ${dateFormat.format(fortnightStart)} - ${dateFormat.format(fortnightEnd)}',
          subHeaderStyle);
      row++;

      // Worker name line
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
      _setCell(sheet, row, 0, 'Worker: ${worker.fullName}', subHeaderStyle);
      row++;
      row++; // blank row

      // ── Column Headers ───────────────────────────────────────────────
      final headerRow = row;

      _setCell(sheet, headerRow, 0, 'DATE\nPOSITION', colHeaderStyle);

      for (int i = 0; i < 14; i++) {
        _setCell(sheet, headerRow, 1 + i, dayLabels[i], colHeaderStyle);
      }

      _setCell(sheet, headerRow, 15, 'DAYS', colHeaderStyle);

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: headerRow),
                  CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: headerRow));
      _setCell(sheet, headerRow, 16, 'RATE', colHeaderStyle);

      _setCell(sheet, headerRow, 19, 'ALLOWANCE', colHeaderStyle);
      _setCell(sheet, headerRow, 20, 'TOTAL', colHeaderStyle);
      _setCell(sheet, headerRow, 21, 'REMARKS', colHeaderStyle);
      _setCell(sheet, headerRow, 22, 'NAME(S)', colHeaderStyle);

      // Rate sub-header row
      row = headerRow + 1;
      _setCell(sheet, row, 16, 'WAGE', colHeaderStyle);
      _setCell(sheet, row, 17, 'COLA', colHeaderStyle);
      _setCell(sheet, row, 18, 'Days\nRate', colHeaderStyle);

      // Sub-sub headers
      row++;
      for (int c = 16; c <= 18; c++) {
        _setCell(sheet, row, c, 'Days:\nRate:\nTotal:', colHeaderStyle);
      }

      row++;

      // ── Worker Data Rows ─────────────────────────────────────────────
      final workerStartRow = row;

      // Time In row
      _setCell(sheet, row, 0, 'Time In', labelStyle);
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        final isWeekday = date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
        _setCell(sheet, row, 1 + d, isWeekday ? '7:00' : '', cellStyle);
      }

      // Calculate days worked
      int daysWorked = 0;
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) {
          daysWorked++;
        }
      }

      _setCell(sheet, row, 15, '$daysWorked', cellStyle);

      final wageTotal = daysWorked * worker.wageRate;
      final colaTotal = daysWorked * worker.colaRate;
      _setCell(sheet, row, 16, 'Days: $daysWorked\nRate: ${worker.wageRate.toStringAsFixed(0)}\nTotal: ${wageTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 17, 'Days: $daysWorked\nRate: ${worker.colaRate.toStringAsFixed(0)}\nTotal: ${colaTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 18, 'Days: $daysWorked\nRate: ${worker.allowanceRate.toStringAsFixed(0)}', cellStyle);
      _setCell(sheet, row, 19, '', cellStyle);
      final total = wageTotal + colaTotal;
      _setCell(sheet, row, 20, total.toStringAsFixed(2), cellStyle);
      _setCell(sheet, row, 21, '', cellStyle);

      _setCell(sheet, row, 22, 'NAME: ${worker.fullName}', labelStyle);

      row++;

      // Time Out row
      _setCell(sheet, row, 0, 'Time Out', labelStyle);
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        final isWeekday = date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
        _setCell(sheet, row, 1 + d, isWeekday ? '15:00' : '', cellStyle);
      }

      _setCell(sheet, row, 16, 'Total: ${wageTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 17, 'Total: ${colaTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 18, 'Total:', cellStyle);
      _setCell(sheet, row, 20, total.toStringAsFixed(2), cellStyle);

      _setCell(sheet, row, 22, 'ID#: ${worker.idNumber}\nNIS#: ${worker.nisNumber}', labelStyle);

      row++;

      // Position row
      _setCell(sheet, row, 0, worker.position, labelStyle);
      for (int c = 1; c <= 21; c++) {
        _setCell(sheet, row, c, '', cellStyle);
      }

      row++;

      // Merge name column
      if (workerStartRow < row - 1) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: workerStartRow),
          CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row - 1),
        );
      }

      row += 2; // spacing

      // ── Footer / Signature Block ─────────────────────────────────────
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
      _setCell(sheet, row, 0, 'CE SUPERVISOR', sigStyle);

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row));
      _setCell(sheet, row, 5, 'REGIONAL COORDINATOR', sigStyle);

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: row));
      _setCell(sheet, row, 11, 'MUNICIPAL CORPORATION', sigStyle);

      row++;
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
      _setCell(sheet, row, 0, 'Checked by', CellStyle(fontSize: 8));

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row));
      _setCell(sheet, row, 5, 'Verified by', CellStyle(fontSize: 8));

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: row));
      _setCell(sheet, row, 11, 'Approved by', CellStyle(fontSize: 8));

      row++;
      for (final label in ['NAME:', 'POSITION:', 'SIGNATURE:', 'DATE:']) {
        sheet.merge(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: row),
                    CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: row));
        _setCell(sheet, row, 17, label, CellStyle(bold: true, fontSize: 8));
        sheet.merge(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: row),
                    CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
        _setCell(sheet, row, 19, '', CellStyle(
          fontSize: 8,
          bottomBorder: Border(borderStyle: BorderStyle.Thin),
        ));
        row++;
      }

      // TOTAL field
      row++;
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: row),
                  CellIndex.indexByColumnRow(columnIndex: 20, rowIndex: row));
      _setCell(sheet, row, 19, 'TOTAL', CellStyle(bold: true, fontSize: 10));

      _setCell(sheet, row, 21, total.toStringAsFixed(2), CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Right,
        bottomBorder: Border(borderStyle: BorderStyle.Double),
      ));

      // Add spacing between worker sections for batch export
      if (wi < workers.length - 1) {
        row += 4; // blank rows between worker timesheets
      }
    }

    // ── Column widths ────────────────────────────────────────────────────
    sheet.setColumnWidth(0, 14);
    for (int i = 1; i <= 14; i++) {
      sheet.setColumnWidth(i, 6);
    }
    sheet.setColumnWidth(15, 6);
    sheet.setColumnWidth(16, 14);
    sheet.setColumnWidth(17, 14);
    sheet.setColumnWidth(18, 10);
    sheet.setColumnWidth(19, 12);
    sheet.setColumnWidth(20, 10);
    sheet.setColumnWidth(21, 12);
    sheet.setColumnWidth(22, 22);

    final fileBytes = excel.save();
    return Uint8List.fromList(fileBytes!);
  }

  static void _setCell(Sheet sheet, int row, int col, String value, CellStyle style) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }
}
