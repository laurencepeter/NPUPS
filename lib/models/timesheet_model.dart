// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Timesheet Model — Pipeline Stages & Approval Tracking
// Supports multi-stage approval: Not Started → Draft → Submitted →
//   Coordinator Review → HR Processing → Accounts Processing →
//   Approved for Payment → Exported → Cheque/Direct Deposit
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum TimesheetStage {
  notStarted('Not Started', Icons.hourglass_empty, Color(0xFF9CA3AF)),
  draft('Draft', Icons.edit_note, Color(0xFF6B7280)),
  submitted('Submitted', Icons.send, Color(0xFF2980B9)),
  coordinatorReview('Coordinator Review', Icons.supervisor_account, Color(0xFF8E44AD)),
  hrProcessing('HR Processing', Icons.badge, Color(0xFFD68910)),
  accountsProcessing('Accounts Processing', Icons.account_balance, Color(0xFFE67E22)),
  approvedForPayment('Approved for Payment', Icons.check_circle, Color(0xFF27AE60)),
  exported('Exported', Icons.download_done, Color(0xFF16A085)),
  chequePrinting('Cheque / Direct Deposit', Icons.payments, Color(0xFF1A2C4E));

  const TimesheetStage(this.displayName, this.icon, this.color);
  final String displayName;
  final IconData icon;
  final Color color;

  TimesheetStage? get nextStage {
    final idx = TimesheetStage.values.indexOf(this);
    if (idx < TimesheetStage.values.length - 1) {
      return TimesheetStage.values[idx + 1];
    }
    return null;
  }

  TimesheetStage? get previousStage {
    final idx = TimesheetStage.values.indexOf(this);
    if (idx > 0) {
      return TimesheetStage.values[idx - 1];
    }
    return null;
  }
}

enum ApprovalState { pending, approved, rejected }

class ApprovalRecord {
  final String reviewerName;
  final String reviewerRole;
  final ApprovalState state;
  final String? note;
  final DateTime timestamp;

  const ApprovalRecord({
    required this.reviewerName,
    required this.reviewerRole,
    required this.state,
    this.note,
    required this.timestamp,
  });
}

class TimesheetDailyEntry {
  TimeOfDay? timeIn;
  TimeOfDay? timeOut;
  TimesheetDailyEntry({this.timeIn, this.timeOut});
  bool get isPresent => timeIn != null && timeOut != null;
}

class Timesheet {
  final String id;
  final String workerId;
  final String workerName;
  final String position;
  final String idNumber;
  final String nisNumber;
  final double wageRate;
  final double colaRate;
  final double allowanceRate;
  final String corporationId;
  final String corporationName;
  final String electoralDistrict;
  final String groupNumber;
  final DateTime fortnightStart;
  final DateTime fortnightEnd;
  final String bankName;
  final String accountNumber;
  final String branchName;

  // Dynamic fields (worker-editable)
  List<TimesheetDailyEntry> dailyEntries;
  int allowanceDays;
  String remarks;

  // Pipeline state
  TimesheetStage stage;
  final List<ApprovalRecord> approvalHistory;
  DateTime createdAt;
  DateTime updatedAt;

  Timesheet({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.idNumber,
    required this.nisNumber,
    required this.wageRate,
    required this.colaRate,
    required this.allowanceRate,
    required this.corporationId,
    required this.corporationName,
    required this.electoralDistrict,
    required this.groupNumber,
    required this.fortnightStart,
    required this.fortnightEnd,
    required this.bankName,
    required this.accountNumber,
    required this.branchName,
    List<TimesheetDailyEntry>? dailyEntries,
    this.allowanceDays = 0,
    this.remarks = '',
    this.stage = TimesheetStage.notStarted,
    List<ApprovalRecord>? approvalHistory,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : dailyEntries = dailyEntries ?? List.generate(14, (_) => TimesheetDailyEntry()),
        approvalHistory = approvalHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Calculated fields
  int get daysWorked => dailyEntries.where((d) => d.isPresent).length;
  double get wageTotal => daysWorked * wageRate;
  double get colaTotal => daysWorked * colaRate;
  double get allowanceTotal => allowanceDays * allowanceRate;
  double get grandTotal => wageTotal + colaTotal + allowanceTotal;

  // Pipeline helpers
  bool get isEditable => stage == TimesheetStage.notStarted || stage == TimesheetStage.draft;

  Duration get timeAtCurrentStage => DateTime.now().difference(updatedAt);
  bool isStalled(Duration threshold) => timeAtCurrentStage > threshold;

  String get stageOwner {
    return switch (stage) {
      TimesheetStage.notStarted => workerName,
      TimesheetStage.draft => workerName,
      TimesheetStage.submitted => 'Regional Coordinator',
      TimesheetStage.coordinatorReview => 'Regional Coordinator',
      TimesheetStage.hrProcessing => 'HR Department',
      TimesheetStage.accountsProcessing => 'Accounts Department',
      TimesheetStage.approvedForPayment => 'Accounts Department',
      TimesheetStage.exported => 'Accounts Department',
      TimesheetStage.chequePrinting => 'Accounts Department',
    };
  }

  void advanceStage(String reviewerName, String reviewerRole, {String? note}) {
    final next = stage.nextStage;
    if (next == null) return;
    approvalHistory.add(ApprovalRecord(
      reviewerName: reviewerName,
      reviewerRole: reviewerRole,
      state: ApprovalState.approved,
      note: note,
      timestamp: DateTime.now(),
    ));
    stage = next;
    updatedAt = DateTime.now();
  }

  void rejectToPreviousStage(String reviewerName, String reviewerRole, String note) {
    final prev = stage.previousStage;
    if (prev == null) return;
    approvalHistory.add(ApprovalRecord(
      reviewerName: reviewerName,
      reviewerRole: reviewerRole,
      state: ApprovalState.rejected,
      note: note,
      timestamp: DateTime.now(),
    ));
    stage = prev;
    updatedAt = DateTime.now();
  }
}
