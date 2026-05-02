// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Generates blank .xlsx templates pre-populated with worker details.
// Corporation personnel download these, fill in time-in/time-out data,
// then upload them back via the Timesheet Upload screen.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/worker_model.dart';

class ExcelTemplateService {
  /// Generate a blank timesheet template for a single worker.
  /// Time-in/time-out cells are left empty for manual entry.
  static Uint8List generateWorkerTemplate({
    required Worker worker,
    required String groupNumber,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    return _generateTemplate(
      workers: [worker],
      groupNumber: groupNumber,
      corporationName: corporationName,
      fortnightStart: fortnightStart,
    );
  }

  /// Generate a blank batch template for all workers in a corporation.
  /// Each worker gets their own section with pre-filled details.
  static Uint8List generateBatchTemplate({
    required List<Worker> workers,
    required String groupNumber,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    return _generateTemplate(
      workers: workers,
      groupNumber: groupNumber,
      corporationName: corporationName,
      fortnightStart: fortnightStart,
    );
  }

  static Uint8List _generateTemplate({
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
    final dayLabels = [
      'MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN',
      'MON', 'TUES', 'WED', 'THUR', 'FRI', 'SAT', 'SUN',
    ];
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
    final editableCellStyle = CellStyle(
      fontSize: 9,
      horizontalAlign: HorizontalAlign.Center,
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
      backgroundColorHex: ExcelColor.fromHexString('#FFFFCC'),
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
    final instructionStyle = CellStyle(
      fontSize: 8,
      italic: true,
      fontColorHex: ExcelColor.fromHexString('#666666'),
    );

    int row = 0;

    // ── Instructions Row ──────────────────────────────────────────────
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
    );
    _setCell(sheet, row, 0,
        'INSTRUCTIONS: Fill in the yellow-highlighted cells with time values (e.g. 7:00, 15:00). '
        'Do not modify worker details, corporation, or structure. '
        'Upload completed file via the WorkForce Timesheet Upload screen.',
        instructionStyle);
    row += 2;

    for (int wi = 0; wi < workers.length; wi++) {
      final worker = workers[wi];

      // ── Title Block ──────────────────────────────────────────────────
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 0, 'TIMESHEET', headerStyle);
      row++;

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 0,
          'WorkForce HR System',
          subHeaderStyle);
      row++;

      // Corporation and Group
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row),
      );
      _setCell(sheet, row, 0, corporationName, subHeaderStyle);
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 11, 'GROUP #: $groupNumber', subHeaderStyle);
      row++;

      // Fortnight dates
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 0,
          'Fortnight: ${dateFormat.format(fortnightStart)} - ${dateFormat.format(fortnightEnd)}',
          subHeaderStyle);
      row++;

      // Worker name line
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 0, 'Worker: ${worker.fullName}', subHeaderStyle);
      row++;

      // Worker ID line (for import matching)
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
      );
      _setCell(sheet, row, 0,
          'Worker ID: ${worker.id} | NIS: ${worker.nisNumber} | ID#: ${worker.idNumber}',
          CellStyle(fontSize: 8, horizontalAlign: HorizontalAlign.Center,
              fontColorHex: ExcelColor.fromHexString('#888888')));
      row++;
      row++; // blank row

      // ── Column Headers ───────────────────────────────────────────────
      final headerRow = row;

      _setCell(sheet, headerRow, 0, 'DATE\nPOSITION', colHeaderStyle);

      for (int i = 0; i < 14; i++) {
        final date = fortnightStart.add(Duration(days: i));
        _setCell(sheet, headerRow, 1 + i,
            '${dayLabels[i]}\n${DateFormat('dd/MM').format(date)}',
            colHeaderStyle);
      }

      _setCell(sheet, headerRow, 15, 'DAYS', colHeaderStyle);

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: headerRow),
        CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: headerRow),
      );
      _setCell(sheet, headerRow, 16, 'RATE', colHeaderStyle);

      _setCell(sheet, headerRow, 19, 'ALLOWANCE\nDAYS', colHeaderStyle);
      _setCell(sheet, headerRow, 20, 'TOTAL', colHeaderStyle);
      _setCell(sheet, headerRow, 21, 'REMARKS', colHeaderStyle);
      _setCell(sheet, headerRow, 22, 'NAME(S)', colHeaderStyle);

      // Rate sub-header row
      row = headerRow + 1;
      _setCell(sheet, row, 16, 'WAGE', colHeaderStyle);
      _setCell(sheet, row, 17, 'COLA', colHeaderStyle);
      _setCell(sheet, row, 18, 'ALLOW\nRate', colHeaderStyle);

      row++;

      // Rate values (pre-filled, read-only info)
      _setCell(sheet, row, 16,
          'Rate: ${worker.wageRate.toStringAsFixed(0)}', cellStyle);
      _setCell(sheet, row, 17,
          'Rate: ${worker.colaRate.toStringAsFixed(0)}', cellStyle);
      _setCell(sheet, row, 18,
          'Rate: ${worker.allowanceRate.toStringAsFixed(0)}', cellStyle);

      row++;

      // ── Worker Data Rows — Time In (EDITABLE) ────────────────────────
      final workerStartRow = row;

      _setCell(sheet, row, 0, 'Time In', labelStyle);
      for (int d = 0; d < 14; d++) {
        // Yellow editable cells — leave blank for user to fill
        _setCell(sheet, row, 1 + d, '', editableCellStyle);
      }

      _setCell(sheet, row, 15, '', cellStyle); // Days (calculated on import)
      _setCell(sheet, row, 16, '', cellStyle); // Wage total
      _setCell(sheet, row, 17, '', cellStyle); // COLA total
      _setCell(sheet, row, 18, '', cellStyle); // Allowance
      _setCell(sheet, row, 19, '', editableCellStyle); // Allowance days (editable)
      _setCell(sheet, row, 20, '', cellStyle); // Total
      _setCell(sheet, row, 21, '', editableCellStyle); // Remarks (editable)

      _setCell(sheet, row, 22, 'NAME: ${worker.fullName}', labelStyle);

      row++;

      // ── Time Out (EDITABLE) ──────────────────────────────────────────
      _setCell(sheet, row, 0, 'Time Out', labelStyle);
      for (int d = 0; d < 14; d++) {
        _setCell(sheet, row, 1 + d, '', editableCellStyle);
      }

      _setCell(sheet, row, 22,
          'ID#: ${worker.idNumber}\nNIS#: ${worker.nisNumber}', labelStyle);

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
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      _setCell(sheet, row, 0, 'CE SUPERVISOR', sigStyle);

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row),
      );
      _setCell(sheet, row, 5, 'REGIONAL COORDINATOR', sigStyle);

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: row),
      );
      _setCell(sheet, row, 11, 'MUNICIPAL CORPORATION', sigStyle);

      row++;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      _setCell(sheet, row, 0, 'Checked by', CellStyle(fontSize: 8));

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row),
      );
      _setCell(sheet, row, 5, 'Verified by', CellStyle(fontSize: 8));

      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: row),
      );
      _setCell(sheet, row, 11, 'Approved by', CellStyle(fontSize: 8));

      row++;
      for (final label in ['NAME:', 'POSITION:', 'SIGNATURE:', 'DATE:']) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: row),
        );
        _setCell(sheet, row, 17, label, CellStyle(bold: true, fontSize: 8));
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: row),
        );
        _setCell(sheet, row, 19, '', CellStyle(
          fontSize: 8,
          bottomBorder: Border(borderStyle: BorderStyle.Thin),
        ));
        row++;
      }

      // Spacing between worker sections
      if (wi < workers.length - 1) {
        row += 4;
      }
    }

    // ── Column widths ────────────────────────────────────────────────────
    sheet.setColumnWidth(0, 14);
    for (int i = 1; i <= 14; i++) {
      sheet.setColumnWidth(i, 7);
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

  static void _setCell(
      Sheet sheet, int row, int col, String value, CellStyle style) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    cell.cellStyle = style;
  }
}
