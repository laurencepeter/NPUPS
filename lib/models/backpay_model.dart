// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Backpay records — when a wage rate is increased retroactively, this captures
// the per-fortnight delta owed to a worker from the effective date forward.
// Each record carries the originating audit entry id so the trail is closed.
// ──────────────────────────────────────────────────────────────────────────────

enum BackpayStatus {
  calculated('Calculated'),
  approved('Approved'),
  disbursed('Disbursed'),
  cancelled('Cancelled');

  const BackpayStatus(this.displayName);
  final String displayName;
}

class BackpayLineItem {
  final String timesheetId;
  final DateTime fortnightStart;
  final int daysWorked;
  final double oldDailyRate;
  final double newDailyRate;
  final double oldColaRate;
  final double newColaRate;

  const BackpayLineItem({
    required this.timesheetId,
    required this.fortnightStart,
    required this.daysWorked,
    required this.oldDailyRate,
    required this.newDailyRate,
    required this.oldColaRate,
    required this.newColaRate,
  });

  double get wageDelta => (newDailyRate - oldDailyRate) * daysWorked;
  double get colaDelta => (newColaRate - oldColaRate) * daysWorked;
  double get totalDelta => wageDelta + colaDelta;

  factory BackpayLineItem.fromJson(Map<String, dynamic> j) => BackpayLineItem(
        timesheetId: j['timesheet_id'] as String,
        fortnightStart: DateTime.parse(j['fortnight_start'] as String),
        daysWorked: j['days_worked'] as int,
        oldDailyRate: (j['old_daily_rate'] as num).toDouble(),
        newDailyRate: (j['new_daily_rate'] as num).toDouble(),
        oldColaRate: (j['old_cola_rate'] as num).toDouble(),
        newColaRate: (j['new_cola_rate'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'timesheet_id': timesheetId,
        'fortnight_start': fortnightStart.toIso8601String(),
        'days_worked': daysWorked,
        'old_daily_rate': oldDailyRate,
        'new_daily_rate': newDailyRate,
        'old_cola_rate': oldColaRate,
        'new_cola_rate': newColaRate,
      };
}

class BackpayRecord {
  final String id;
  final String workerId;
  final String workerName;
  final String corporationId;
  final String corporationName;
  final DateTime effectiveFrom;
  final double oldWageRate;
  final double newWageRate;
  final double oldColaRate;
  final double newColaRate;
  final List<BackpayLineItem> lineItems;
  BackpayStatus status;
  final DateTime calculatedAt;
  final String calculatedByUserId;
  String? note;

  BackpayRecord({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.corporationId,
    required this.corporationName,
    required this.effectiveFrom,
    required this.oldWageRate,
    required this.newWageRate,
    required this.oldColaRate,
    required this.newColaRate,
    required this.lineItems,
    this.status = BackpayStatus.calculated,
    required this.calculatedAt,
    required this.calculatedByUserId,
    this.note,
  });

  double get totalAmount =>
      lineItems.fold(0.0, (sum, l) => sum + l.totalDelta);

  int get fortnightsAffected => lineItems.length;

  factory BackpayRecord.fromJson(Map<String, dynamic> j) => BackpayRecord(
        id: j['id'] as String,
        workerId: j['worker_id'] as String,
        workerName: j['worker_name'] as String,
        corporationId: j['corporation_id'] as String,
        corporationName: j['corporation_name'] as String,
        effectiveFrom: DateTime.parse(j['effective_from'] as String),
        oldWageRate: (j['old_wage_rate'] as num).toDouble(),
        newWageRate: (j['new_wage_rate'] as num).toDouble(),
        oldColaRate: (j['old_cola_rate'] as num).toDouble(),
        newColaRate: (j['new_cola_rate'] as num).toDouble(),
        lineItems: (j['line_items'] as List? ?? const [])
            .map((e) => BackpayLineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: BackpayStatus.values.byName(j['status'] as String),
        calculatedAt: DateTime.parse(j['calculated_at'] as String),
        calculatedByUserId: j['calculated_by_user_id'] as String,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'worker_id': workerId,
        'worker_name': workerName,
        'corporation_id': corporationId,
        'corporation_name': corporationName,
        'effective_from': effectiveFrom.toIso8601String(),
        'old_wage_rate': oldWageRate,
        'new_wage_rate': newWageRate,
        'old_cola_rate': oldColaRate,
        'new_cola_rate': newColaRate,
        'line_items': lineItems.map((l) => l.toJson()).toList(),
        'status': status.name,
        'calculated_at': calculatedAt.toIso8601String(),
        'calculated_by_user_id': calculatedByUserId,
        'note': note,
      };
}
