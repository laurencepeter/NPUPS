import 'package:flutter_test/flutter_test.dart';
import 'package:workforce/models/payroll_deductions_model.dart';

// PAYE income-tax engine. Expected figures use the Trinidad & Tobago defaults:
//   personal allowance  TT$90,000 / year   → 90000 / 26 = 3461.5385 per fortnight
//   lower band ceiling  TT$1,000,000 / year → 1000000 / 26 = 38461.5385 per fortnight
//   rates               25% (lower band), 30% (excess)
void main() {
  group('DeductionBreakdown PAYE — fortnightly (26 periods)', () {
    test('no PAYE when gross is below the prorated personal allowance', () {
      final b = DeductionBreakdown.compute(grossSalary: 3000);
      expect(b.paye, 0);
      expect(b.taxable, 0);
    });

    test('lower-band income taxed at 25%', () {
      // chargeable = 5000 - 3461.5385 = 1538.4615 → PAYE = 25% = 384.62
      final b = DeductionBreakdown.compute(grossSalary: 5000);
      expect(b.taxable, 1538.46);
      expect(b.paye, 384.62);
    });

    test('income above the band ceiling taxed at 30%', () {
      // chargeable = 45000 - 3461.5385 = 41538.4615
      //   lower band  38461.5385 @ 25% = 9615.3846
      //   excess       3076.9231 @ 30% =  923.0769
      //   PAYE                          = 10538.46
      final b = DeductionBreakdown.compute(grossSalary: 45000);
      expect(b.paye, 10538.46);
    });

    test('PAYE is included in employee deductions and net salary', () {
      final b = DeductionBreakdown.compute(grossSalary: 5000);
      // NIS worker 3.4% = 170.00 ; Health Surcharge 8.25 x 2 = 16.50 ; PAYE 384.62
      expect(b.nisEmployee, 170.00);
      expect(b.healthSurcharge, 16.50);
      expect(b.totalEmployeeDeductions, closeTo(571.12, 0.001));
      expect(b.netSalary, closeTo(4428.88, 0.001));
    });

    test('PAYE does not affect employer cost or NIS remitted', () {
      final b = DeductionBreakdown.compute(grossSalary: 5000);
      expect(b.totalEmployerCost, closeTo(5000 + 5000 * 0.065, 0.001));
      expect(b.totalNisRemitted, closeTo(b.nisEmployee + b.nisEmployer, 0.001));
    });
  });

  group('DeductionBreakdown PAYE — proration by pay period', () {
    test('monthly payroll prorates the allowance over 12 periods', () {
      // 90000 / 12 = 7500 allowance ; chargeable = 8000 - 7500 = 500 @ 25% = 125
      final b =
          DeductionBreakdown.compute(grossSalary: 8000, payPeriodsPerYear: 12);
      expect(b.taxable, 500);
      expect(b.paye, 125.00);
    });
  });

  group('DeductionBreakdown PAYE — configurable rate table', () {
    test('overriding the personal allowance changes PAYE (auditable rates)', () {
      const legacy = DeductionRateTable(
        year: 2022,
        personalAllowanceAnnual: 84000, // pre-2023 TT allowance
      );
      // 84000 / 26 = 3230.7692 ; chargeable = 5000 - 3230.7692 = 1769.2308 @ 25%
      final b = DeductionBreakdown.compute(grossSalary: 5000, rates: legacy);
      expect(b.paye, 442.31);
    });

    test('a zero personal allowance taxes the full gross', () {
      const flat = DeductionRateTable(year: 2026, personalAllowanceAnnual: 0);
      final b = DeductionBreakdown.compute(grossSalary: 1000, rates: flat);
      expect(b.taxable, 1000);
      expect(b.paye, 250.00);
    });
  });
}
