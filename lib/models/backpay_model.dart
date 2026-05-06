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
}
