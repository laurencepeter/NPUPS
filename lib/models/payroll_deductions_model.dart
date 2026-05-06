// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Statutory deduction model — NIS contributions, Health Surcharge, and the
// derived gross/net salary breakdown for a single timesheet.
//
// Rates default to Trinidad & Tobago figures and can be overridden per year
// via [DeductionRateTable] so historical fortnights remain auditable.
// ──────────────────────────────────────────────────────────────────────────────

class DeductionRateTable {
  /// Year these rates apply to (matched against fortnightStart.year).
  final int year;

  /// Worker share of National Insurance, expressed as decimal (e.g. 0.034 = 3.4%).
  final double nisEmployeeRate;

  /// Employer share of NIS, decimal.
  final double nisEmployerRate;

  /// Weekly Health Surcharge for workers earning over [healthSurchargeHighThreshold]
  /// per fortnight (TTD). Doubled for fortnight payrolls.
  final double healthSurchargeWeeklyHigh;

  /// Weekly Health Surcharge for workers below the threshold (TTD).
  final double healthSurchargeWeeklyLow;

  /// Fortnightly gross threshold (TTD) above which the high HS rate applies.
  final double healthSurchargeHighThreshold;

  const DeductionRateTable({
    required this.year,
    this.nisEmployeeRate = 0.034,
    this.nisEmployerRate = 0.065,
    this.healthSurchargeWeeklyHigh = 8.25,
    this.healthSurchargeWeeklyLow = 4.80,
    this.healthSurchargeHighThreshold = 469.99,
  });

  static const DeductionRateTable defaults = DeductionRateTable(year: 2026);
}

/// Computed deduction snapshot for one timesheet / fortnight.
class DeductionBreakdown {
  final double grossSalary;
  final double nisEmployee;
  final double nisEmployer;
  final double healthSurcharge;
  final DeductionRateTable rates;

  const DeductionBreakdown({
    required this.grossSalary,
    required this.nisEmployee,
    required this.nisEmployer,
    required this.healthSurcharge,
    required this.rates,
  });

  double get totalEmployeeDeductions => nisEmployee + healthSurcharge;
  double get netSalary => grossSalary - totalEmployeeDeductions;
  double get totalEmployerCost => grossSalary + nisEmployer;
  double get totalNisRemitted => nisEmployee + nisEmployer;

  factory DeductionBreakdown.compute({
    required double grossSalary,
    DeductionRateTable rates = DeductionRateTable.defaults,
  }) {
    final nisEmp = grossSalary * rates.nisEmployeeRate;
    final nisEr = grossSalary * rates.nisEmployerRate;
    final hsWeekly = grossSalary > rates.healthSurchargeHighThreshold
        ? rates.healthSurchargeWeeklyHigh
        : rates.healthSurchargeWeeklyLow;
    // A fortnight = 2 weeks
    final hsFortnight = hsWeekly * 2;
    return DeductionBreakdown(
      grossSalary: grossSalary,
      nisEmployee: _r(nisEmp),
      nisEmployer: _r(nisEr),
      healthSurcharge: _r(hsFortnight),
      rates: rates,
    );
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}
