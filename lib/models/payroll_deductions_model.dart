// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Statutory deduction model — PAYE income tax, NIS contributions, Health
// Surcharge, and the derived gross/net salary breakdown for a single timesheet.
//
// Rates default to Trinidad & Tobago figures and can be overridden per year
// via [DeductionRateTable] so historical fortnights remain auditable.
// ──────────────────────────────────────────────────────────────────────────────

/// Number of fortnightly pay periods in a year. Annual PAYE thresholds are
/// prorated by this so a single fortnight is taxed at its correct share.
const int kFortnightsPerYear = 26;

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

  // ── PAYE income tax (Trinidad & Tobago) ──────────────────────────────────
  //
  // Chargeable income = gross emoluments − personal allowance. The BIR taxes
  // the first [payeBandThresholdAnnual] of chargeable income at [payeRateLow]
  // and the remainder at [payeRateHigh]. All thresholds below are ANNUAL and
  // prorated to the pay period at compute time, so mid-year rate changes stay
  // auditable per fortnight.

  /// Annual tax-free personal allowance (TTD). TT default: 90,000.
  final double personalAllowanceAnnual;

  /// Annual chargeable-income ceiling for the lower band (TTD). TT default:
  /// 1,000,000 — chargeable income above this is taxed at [payeRateHigh].
  final double payeBandThresholdAnnual;

  /// Lower-band income-tax rate, decimal (TT default 0.25 = 25%).
  final double payeRateLow;

  /// Higher-band income-tax rate, decimal (TT default 0.30 = 30%).
  final double payeRateHigh;

  const DeductionRateTable({
    required this.year,
    this.nisEmployeeRate = 0.034,
    this.nisEmployerRate = 0.065,
    this.healthSurchargeWeeklyHigh = 8.25,
    this.healthSurchargeWeeklyLow = 4.80,
    this.healthSurchargeHighThreshold = 469.99,
    this.personalAllowanceAnnual = 90000.0,
    this.payeBandThresholdAnnual = 1000000.0,
    this.payeRateLow = 0.25,
    this.payeRateHigh = 0.30,
  });

  static const DeductionRateTable defaults = DeductionRateTable(year: 2026);
}

/// Computed deduction snapshot for one timesheet / fortnight.
class DeductionBreakdown {
  final double grossSalary;

  /// Chargeable income for the period (gross − prorated personal allowance,
  /// floored at zero). This is the base PAYE is levied on.
  final double taxable;

  /// PAYE income tax withheld for the period.
  final double paye;
  final double nisEmployee;
  final double nisEmployer;
  final double healthSurcharge;
  final DeductionRateTable rates;

  const DeductionBreakdown({
    required this.grossSalary,
    required this.taxable,
    required this.paye,
    required this.nisEmployee,
    required this.nisEmployer,
    required this.healthSurcharge,
    required this.rates,
  });

  double get totalEmployeeDeductions => paye + nisEmployee + healthSurcharge;
  double get netSalary => grossSalary - totalEmployeeDeductions;
  double get totalEmployerCost => grossSalary + nisEmployer;
  double get totalNisRemitted => nisEmployee + nisEmployer;

  factory DeductionBreakdown.compute({
    required double grossSalary,
    DeductionRateTable rates = DeductionRateTable.defaults,
    int payPeriodsPerYear = kFortnightsPerYear,
  }) {
    final nisEmp = grossSalary * rates.nisEmployeeRate;
    final nisEr = grossSalary * rates.nisEmployerRate;
    final hsWeekly = grossSalary > rates.healthSurchargeHighThreshold
        ? rates.healthSurchargeWeeklyHigh
        : rates.healthSurchargeWeeklyLow;
    // A fortnight = 2 weeks
    final hsFortnight = hsWeekly * 2;

    // ── PAYE ──────────────────────────────────────────────────────────────
    // Prorate the annual personal allowance and band ceiling to this pay
    // period, then apply the two-band rate to the chargeable amount.
    final periodAllowance = rates.personalAllowanceAnnual / payPeriodsPerYear;
    final periodBandCeiling =
        rates.payeBandThresholdAnnual / payPeriodsPerYear;
    // .clamp returns num; force double so the arithmetic below stays double.
    final chargeable =
        (grossSalary - periodAllowance).clamp(0.0, double.infinity).toDouble();
    final lowBand =
        chargeable <= periodBandCeiling ? chargeable : periodBandCeiling;
    final highBand =
        chargeable > periodBandCeiling ? chargeable - periodBandCeiling : 0.0;
    final paye = lowBand * rates.payeRateLow + highBand * rates.payeRateHigh;

    return DeductionBreakdown(
      grossSalary: grossSalary,
      taxable: _r(chargeable),
      paye: _r(paye),
      nisEmployee: _r(nisEmp),
      nisEmployer: _r(nisEr),
      healthSurcharge: _r(hsFortnight),
      rates: rates,
    );
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}
