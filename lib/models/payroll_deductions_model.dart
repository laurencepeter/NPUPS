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
  /// Backend row id (null for the built-in [defaults], which never persists).
  final String? id;

  /// Human label shown in the admin editor, e.g. "2026 statutory rates".
  final String? label;

  /// Date this rate set takes effect. The engine resolves the applicable set
  /// for a fortnight by picking the latest [effectiveFrom] on or before the
  /// fortnight start (see RateTableService.resolve), so a mid-year rate change
  /// never rewrites already-processed fortnights.
  final DateTime? effectiveFrom;

  /// Year these rates apply to (matched against fortnightStart.year).
  final int year;

  /// Pay periods per year the annual PAYE thresholds are prorated over.
  /// 26 = fortnightly (WorkForce default), 12 = monthly, 52 = weekly.
  final int payPeriodsPerYear;

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
    this.id,
    this.label,
    this.effectiveFrom,
    this.payPeriodsPerYear = kFortnightsPerYear,
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

  /// Built-in Trinidad & Tobago fallback used when the backend has no rate
  /// tables loaded yet, so the engine always has a sane, documented default.
  static const DeductionRateTable defaults = DeductionRateTable(year: 2026);

  static double _num(dynamic v, double fallback) =>
      v == null ? fallback : (v as num).toDouble();

  factory DeductionRateTable.fromJson(Map<String, dynamic> j) {
    final eff =
        j['effective_from'] == null ? null : DateTime.parse(j['effective_from'] as String);
    return DeductionRateTable(
      id: j['id'] as String?,
      label: j['label'] as String?,
      effectiveFrom: eff,
      year: (j['year'] as num?)?.toInt() ?? eff?.year ?? DateTime.now().year,
      payPeriodsPerYear:
          (j['pay_periods_per_year'] as num?)?.toInt() ?? kFortnightsPerYear,
      nisEmployeeRate: _num(j['nis_employee_rate'], 0.034),
      nisEmployerRate: _num(j['nis_employer_rate'], 0.065),
      healthSurchargeWeeklyHigh: _num(j['health_surcharge_weekly_high'], 8.25),
      healthSurchargeWeeklyLow: _num(j['health_surcharge_weekly_low'], 4.80),
      healthSurchargeHighThreshold:
          _num(j['health_surcharge_high_threshold'], 469.99),
      personalAllowanceAnnual: _num(j['personal_allowance_annual'], 90000.0),
      payeBandThresholdAnnual: _num(j['paye_band_threshold_annual'], 1000000.0),
      payeRateLow: _num(j['paye_rate_low'], 0.25),
      payeRateHigh: _num(j['paye_rate_high'], 0.30),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'label': label,
        'effective_from': effectiveFrom?.toIso8601String(),
        'year': year,
        'pay_periods_per_year': payPeriodsPerYear,
        'nis_employee_rate': nisEmployeeRate,
        'nis_employer_rate': nisEmployerRate,
        'health_surcharge_weekly_high': healthSurchargeWeeklyHigh,
        'health_surcharge_weekly_low': healthSurchargeWeeklyLow,
        'health_surcharge_high_threshold': healthSurchargeHighThreshold,
        'personal_allowance_annual': personalAllowanceAnnual,
        'paye_band_threshold_annual': payeBandThresholdAnnual,
        'paye_rate_low': payeRateLow,
        'paye_rate_high': payeRateHigh,
      };

  DeductionRateTable copyWith({
    String? id,
    String? label,
    DateTime? effectiveFrom,
    int? payPeriodsPerYear,
    double? nisEmployeeRate,
    double? nisEmployerRate,
    double? healthSurchargeWeeklyHigh,
    double? healthSurchargeWeeklyLow,
    double? healthSurchargeHighThreshold,
    double? personalAllowanceAnnual,
    double? payeBandThresholdAnnual,
    double? payeRateLow,
    double? payeRateHigh,
  }) {
    final eff = effectiveFrom ?? this.effectiveFrom;
    return DeductionRateTable(
      id: id ?? this.id,
      label: label ?? this.label,
      effectiveFrom: eff,
      year: eff?.year ?? year,
      payPeriodsPerYear: payPeriodsPerYear ?? this.payPeriodsPerYear,
      nisEmployeeRate: nisEmployeeRate ?? this.nisEmployeeRate,
      nisEmployerRate: nisEmployerRate ?? this.nisEmployerRate,
      healthSurchargeWeeklyHigh:
          healthSurchargeWeeklyHigh ?? this.healthSurchargeWeeklyHigh,
      healthSurchargeWeeklyLow:
          healthSurchargeWeeklyLow ?? this.healthSurchargeWeeklyLow,
      healthSurchargeHighThreshold:
          healthSurchargeHighThreshold ?? this.healthSurchargeHighThreshold,
      personalAllowanceAnnual:
          personalAllowanceAnnual ?? this.personalAllowanceAnnual,
      payeBandThresholdAnnual:
          payeBandThresholdAnnual ?? this.payeBandThresholdAnnual,
      payeRateLow: payeRateLow ?? this.payeRateLow,
      payeRateHigh: payeRateHigh ?? this.payeRateHigh,
    );
  }
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
    int? payPeriodsPerYear,
  }) {
    final periods = payPeriodsPerYear ?? rates.payPeriodsPerYear;
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
    final periodAllowance = rates.personalAllowanceAnnual / periods;
    final periodBandCeiling = rates.payeBandThresholdAnnual / periods;
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
