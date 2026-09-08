import 'package:flutter_test/flutter_test.dart';
import 'package:workforce/models/payroll_deductions_model.dart';
import 'package:workforce/services/rate_table_service.dart';

void main() {
  final base2020 = DeductionRateTable(
    id: 'a',
    label: 'base',
    year: 2020,
    effectiveFrom: DateTime(2020, 1, 1),
    personalAllowanceAnnual: 84000,
  );
  final budget2023 = DeductionRateTable(
    id: 'b',
    label: '2023 budget',
    year: 2023,
    effectiveFrom: DateTime(2023, 1, 1),
    personalAllowanceAnnual: 90000,
  );

  group('RateTableService.resolve — effective-date selection', () {
    test('empty list falls back to built-in defaults', () {
      final r = RateTableService.resolve([], DateTime(2026, 5, 1));
      expect(r.id, isNull);
      expect(r.personalAllowanceAnnual, 90000.0);
    });

    test('a date before every set falls back to defaults', () {
      final r = RateTableService.resolve([base2020, budget2023], DateTime(2019, 1, 1));
      expect(r.id, isNull);
    });

    test('picks the latest set effective on or before the date', () {
      expect(
        RateTableService.resolve([base2020, budget2023], DateTime(2022, 6, 1)).id,
        'a',
      );
      expect(
        RateTableService.resolve([base2020, budget2023], DateTime(2023, 6, 1)).id,
        'b',
      );
    });

    test('boundary: the effective date itself selects that set', () {
      expect(
        RateTableService.resolve([base2020, budget2023], DateTime(2023, 1, 1)).id,
        'b',
      );
    });

    test('order of the input list does not matter', () {
      expect(
        RateTableService.resolve([budget2023, base2020], DateTime(2022, 6, 1)).id,
        'a',
      );
    });
  });

  group('DeductionRateTable JSON round-trip', () {
    test('toJson → fromJson preserves every field', () {
      final t = DeductionRateTable(
        id: 'x',
        label: 'custom',
        year: 2027,
        effectiveFrom: DateTime(2027, 1, 1),
        payPeriodsPerYear: 12,
        nisEmployeeRate: 0.04,
        nisEmployerRate: 0.07,
        healthSurchargeWeeklyHigh: 9.0,
        healthSurchargeWeeklyLow: 5.0,
        healthSurchargeHighThreshold: 500,
        personalAllowanceAnnual: 100000,
        payeBandThresholdAnnual: 1200000,
        payeRateLow: 0.28,
        payeRateHigh: 0.33,
      );
      final back = DeductionRateTable.fromJson(t.toJson());
      expect(back.id, 'x');
      expect(back.label, 'custom');
      expect(back.effectiveFrom, DateTime(2027, 1, 1));
      expect(back.payPeriodsPerYear, 12);
      expect(back.nisEmployeeRate, 0.04);
      expect(back.personalAllowanceAnnual, 100000);
      expect(back.payeRateHigh, 0.33);
    });
  });

  group('compute honours the table pay period', () {
    test('a monthly (12-period) table prorates without an explicit override', () {
      final monthly = DeductionRateTable(
        year: 2026,
        payPeriodsPerYear: 12,
      );
      // 90000 / 12 = 7500 allowance; chargeable 8000-7500 = 500 @ 25% = 125
      final b = DeductionBreakdown.compute(grossSalary: 8000, rates: monthly);
      expect(b.taxable, 500);
      expect(b.paye, 125.00);
    });
  });
}
