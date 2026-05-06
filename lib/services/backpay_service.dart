// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Backpay calculation service.
// Given a wage-rate increase that takes effect from a specific date onward,
// generates a per-worker BackpayRecord covering every timesheet fortnight on
// or after the effective date, computing the delta owed.
//
// The act of calculating, approving and disbursing each backpay record is
// audited via AuditService — providing an irrefutable paper trail for the
// employer should HR ever be questioned about retroactive pay.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/audit_model.dart';
import '../models/backpay_model.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import 'audit_service.dart';
import 'timesheet_data_store.dart';

class BackpayService extends ChangeNotifier {
  static final BackpayService _instance = BackpayService._internal();
  factory BackpayService() => _instance;
  BackpayService._internal();

  final List<BackpayRecord> _records = [];
  int _seq = 0;

  final AuditService _audit = AuditService();
  final TimesheetDataStore _timesheets = TimesheetDataStore();

  List<BackpayRecord> get records => List.unmodifiable(_records);

  List<BackpayRecord> getForWorker(String workerId) =>
      _records.where((r) => r.workerId == workerId).toList();

  /// Calculate backpay for one worker: walk every timesheet they have on or
  /// after [effectiveFrom] and compute the delta owed.
  ///
  /// Returns null if no eligible timesheets exist.
  BackpayRecord? calculateForWorker({
    required AppUser actor,
    required String workerId,
    required String workerName,
    required String corporationId,
    required String corporationName,
    required DateTime effectiveFrom,
    required double oldWageRate,
    required double newWageRate,
    required double oldColaRate,
    required double newColaRate,
    String? note,
  }) {
    if (newWageRate <= oldWageRate && newColaRate <= oldColaRate) {
      return null;
    }

    final timesheets = _timesheets
        .getByWorker(workerId)
        .where((t) =>
            !t.fortnightStart.isBefore(effectiveFrom) &&
            t.daysWorked > 0 &&
            t.stage.index >= TimesheetStage.approvedForPayment.index)
        .toList();

    if (timesheets.isEmpty) return null;

    final lineItems = timesheets
        .map((t) => BackpayLineItem(
              timesheetId: t.id,
              fortnightStart: t.fortnightStart,
              daysWorked: t.daysWorked,
              oldDailyRate: oldWageRate,
              newDailyRate: newWageRate,
              oldColaRate: oldColaRate,
              newColaRate: newColaRate,
            ))
        .toList();

    _seq++;
    final id = 'BP-${DateTime.now().year}-${_seq.toString().padLeft(4, '0')}';

    final record = BackpayRecord(
      id: id,
      workerId: workerId,
      workerName: workerName,
      corporationId: corporationId,
      corporationName: corporationName,
      effectiveFrom: effectiveFrom,
      oldWageRate: oldWageRate,
      newWageRate: newWageRate,
      oldColaRate: oldColaRate,
      newColaRate: newColaRate,
      lineItems: lineItems,
      calculatedAt: DateTime.now(),
      calculatedByUserId: actor.id,
      note: note,
    );

    _records.add(record);

    _audit.log(
      actor: actor,
      action: AuditAction.backpayCalculated,
      entityType: AuditEntityType.backpay,
      entityId: id,
      entityDisplayName: 'Backpay – $workerName',
      fieldChanges: [
        AuditFieldChange(
            fieldName: 'Old Wage Rate', newValue: oldWageRate.toStringAsFixed(2)),
        AuditFieldChange(
            fieldName: 'New Wage Rate', newValue: newWageRate.toStringAsFixed(2)),
        AuditFieldChange(
            fieldName: 'Old COLA Rate', newValue: oldColaRate.toStringAsFixed(2)),
        AuditFieldChange(
            fieldName: 'New COLA Rate', newValue: newColaRate.toStringAsFixed(2)),
        AuditFieldChange(
            fieldName: 'Effective From',
            newValue:
                '${effectiveFrom.year}-${effectiveFrom.month.toString().padLeft(2, '0')}-${effectiveFrom.day.toString().padLeft(2, '0')}'),
        AuditFieldChange(
            fieldName: 'Fortnights Affected',
            newValue: record.fortnightsAffected.toString()),
        AuditFieldChange(
            fieldName: 'Total Backpay',
            newValue: record.totalAmount.toStringAsFixed(2)),
      ],
      note: note,
    );

    notifyListeners();
    return record;
  }

  void approve(String recordId, AppUser actor, {String? note}) {
    final r = _records.firstWhere((x) => x.id == recordId);
    if (r.status != BackpayStatus.calculated) return;
    r.status = BackpayStatus.approved;
    _audit.log(
      actor: actor,
      action: AuditAction.backpayApproved,
      entityType: AuditEntityType.backpay,
      entityId: r.id,
      entityDisplayName: 'Backpay – ${r.workerName}',
      note: note,
    );
    notifyListeners();
  }

  void disburse(String recordId, AppUser actor, {String? note}) {
    final r = _records.firstWhere((x) => x.id == recordId);
    if (r.status != BackpayStatus.approved) return;
    r.status = BackpayStatus.disbursed;
    _audit.log(
      actor: actor,
      action: AuditAction.backpayDisbursed,
      entityType: AuditEntityType.backpay,
      entityId: r.id,
      entityDisplayName: 'Backpay – ${r.workerName}',
      fieldChanges: [
        AuditFieldChange(
            fieldName: 'Amount Paid',
            newValue: r.totalAmount.toStringAsFixed(2)),
      ],
      note: note,
    );
    notifyListeners();
  }
}
