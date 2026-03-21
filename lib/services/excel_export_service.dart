// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Excel Timesheet Export Service
// Generates .xlsx files matching the exact NPUPS timesheet template layout:
//   - Header: TIMESHEET title, GROUP #
//   - Columns: DATE/POSITION, MON-SUN x2 weeks, DAYS, RATE (Wage/COLA),
//     ALLOWANCE, TOTAL, REMARKS
//   - Worker rows with Time In / Time Out per day
//   - Footer: CE Supervisor, Regional Coordinator, Municipal Corporation sigs
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/worker_model.dart';

class ExcelExportService {
  static Uint8List generateTimesheet({
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

    // Day labels for 14-day period
    final dayLabels = ['MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN',
                       'MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN'];

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

    int row = 0;

    // ── Title Block ──────────────────────────────────────────────────────
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
    final dateFormat = DateFormat('dd/MM/yyyy');
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
                CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row));
    _setCell(sheet, row, 0,
        'Fortnight: ${dateFormat.format(fortnightStart)} - ${dateFormat.format(fortnightEnd)}',
        subHeaderStyle);
    row++;
    row++; // blank row

    // ── Column Headers ───────────────────────────────────────────────────
    // Row for main headers
    final headerRow = row;

    // Column layout matching template image:
    // Col 0: DATE/POSITION
    // Col 1-14: MON TUES WED THUR FRI SAT SUN (x2 weeks)
    // Col 15: DAYS
    // Col 16: RATE - Wage (Days/Rate/Total)
    // Col 17: RATE - COLA (Days/Rate/Total)
    // Col 18: RATE - (third sub)
    // Col 19: ALLOWANCE
    // Col 20: TOTAL
    // Col 21: REMARKS
    // Col 22: NAME(S) / ID / NIS

    _setCell(sheet, headerRow, 0, 'DATE\nPOSITION', colHeaderStyle);

    // Day columns
    for (int i = 0; i < 14; i++) {
      _setCell(sheet, headerRow, 1 + i, dayLabels[i], colHeaderStyle);
    }

    _setCell(sheet, headerRow, 15, 'DAYS', colHeaderStyle);

    // Rate sub-headers
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

    // Sub-sub headers for rate breakdowns
    row++;
    for (int c = 16; c <= 18; c++) {
      _setCell(sheet, row, c, 'Days:\nRate:\nTotal:', colHeaderStyle);
    }

    row++;

    // ── Worker Data Rows ─────────────────────────────────────────────────
    for (final worker in workers) {
      final workerStartRow = row;

      // Time In row
      _setCell(sheet, row, 0, 'Time In', labelStyle);
      // Simulate standard work hours (7:00 AM) for weekdays
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        final isWeekday = date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
        _setCell(sheet, row, 1 + d, isWeekday ? '7:00' : '', cellStyle);
      }

      // Calculate days worked (weekdays)
      int daysWorked = 0;
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) {
          daysWorked++;
        }
      }

      _setCell(sheet, row, 15, '$daysWorked', cellStyle);

      // Wage calculation
      final wageTotal = daysWorked * worker.wageRate;
      final colaTotal = daysWorked * worker.colaRate;
      _setCell(sheet, row, 16, 'Days: $daysWorked\nRate: ${worker.wageRate.toStringAsFixed(0)}\nTotal: ${wageTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 17, 'Days: $daysWorked\nRate: ${worker.colaRate.toStringAsFixed(0)}\nTotal: ${colaTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 18, 'Days: $daysWorked\nRate: ${worker.allowanceRate.toStringAsFixed(0)}', cellStyle);
      _setCell(sheet, row, 19, '', cellStyle);
      final total = wageTotal + colaTotal;
      _setCell(sheet, row, 20, total.toStringAsFixed(2), cellStyle);
      _setCell(sheet, row, 21, '', cellStyle);

      // Worker name, ID, NIS on right side
      _setCell(sheet, row, 22, 'NAME: ${worker.fullName}', labelStyle);

      row++;

      // Time Out row
      _setCell(sheet, row, 0, 'Time Out', labelStyle);
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        final isWeekday = date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
        _setCell(sheet, row, 1 + d, isWeekday ? '15:00' : '', cellStyle);
      }

      // Totals row
      _setCell(sheet, row, 16, 'Total: ${wageTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 17, 'Total: ${colaTotal.toStringAsFixed(2)}', cellStyle);
      _setCell(sheet, row, 18, 'Total:', cellStyle);
      _setCell(sheet, row, 20, total.toStringAsFixed(2), cellStyle);

      _setCell(sheet, row, 22, 'ID#: ${worker.idNumber}\nNIS#: ${worker.nisNumber}', labelStyle);

      row++;

      // Position row
      _setCell(sheet, row, 0, worker.position, labelStyle);

      // Empty padding
      for (int c = 1; c <= 21; c++) {
        _setCell(sheet, row, c, '', cellStyle);
      }

      row++;

      // Merge name column for this worker block
      if (workerStartRow < row - 1) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: workerStartRow),
          CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row - 1),
        );
      }
    }

    row += 2; // spacing

    // ── Footer / Signature Block ─────────────────────────────────────────
    final sigStyle = CellStyle(
      bold: true,
      fontSize: 9,
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );

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

    // Name, Position, Signature, Date fields
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

    // TOTAL field at bottom right
    row++;
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: row),
                CellIndex.indexByColumnRow(columnIndex: 20, rowIndex: row));
    _setCell(sheet, row, 19, 'TOTAL', CellStyle(bold: true, fontSize: 10));

    final grandTotal = workers.fold<double>(0, (sum, w) {
      int days = 0;
      for (int d = 0; d < 14; d++) {
        final date = fortnightStart.add(Duration(days: d));
        if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) days++;
      }
      return sum + (days * w.wageRate) + (days * w.colaRate);
    });

    _setCell(sheet, row, 21, grandTotal.toStringAsFixed(2), CellStyle(
      bold: true,
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Right,
      bottomBorder: Border(borderStyle: BorderStyle.Double),
    ));

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

    // Encode and return
    final fileBytes = excel.save();
    return Uint8List.fromList(fileBytes!);
  }

  static void _setCell(Sheet sheet, int row, int col, String value, CellStyle style) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }
}
