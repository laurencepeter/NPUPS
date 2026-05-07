// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Supports multi-stage approval: Not Started → Draft → Submitted →
//   Coordinator Review → HR Processing → Accounts Processing →
//   Approved for Payment → Exported → Cheque/Direct Deposit
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'payroll_deductions_model.dart';

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

  factory ApprovalRecord.fromJson(Map<String, dynamic> j) => ApprovalRecord(
        reviewerName: j['reviewer_name'] as String,
        reviewerRole: j['reviewer_role'] as String,
        state: ApprovalState.values.byName(j['state'] as String),
        note: j['note'] as String?,
        timestamp: DateTime.parse(j['ts'] as String),
      );

  Map<String, dynamic> toJson() => {
        'reviewer_name': reviewerName,
        'reviewer_role': reviewerRole,
        'state': state.name,
        'note': note,
        'ts': timestamp.toIso8601String(),
      };
}

class TimesheetDailyEntry {
  TimeOfDay? timeIn;
  TimeOfDay? timeOut;
  TimesheetDailyEntry({this.timeIn, this.timeOut});
  bool get isPresent => timeIn != null && timeOut != null;

  static TimeOfDay? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String? _formatTime(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  factory TimesheetDailyEntry.fromJson(Map<String, dynamic> j) =>
      TimesheetDailyEntry(
        timeIn: _parseTime(j['time_in'] as String?),
        timeOut: _parseTime(j['time_out'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'time_in': _formatTime(timeIn),
        'time_out': _formatTime(timeOut),
      };
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
    this.colaRate = 0.0,
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

  // Statutory deductions — gross is wage + cola (allowance is non-taxable).
  double get grossSalary => wageTotal + colaTotal;
  DeductionBreakdown get deductions =>
      DeductionBreakdown.compute(grossSalary: grossSalary);
  double get nisEmployee => deductions.nisEmployee;
  double get nisEmployer => deductions.nisEmployer;
  double get healthSurcharge => deductions.healthSurcharge;
  double get netPay => grandTotal - deductions.totalEmployeeDeductions;

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

  factory Timesheet.fromJson(Map<String, dynamic> j) {
    final entries = (j['daily_entries'] as List? ?? const [])
        .map((e) => TimesheetDailyEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    while (entries.length < 14) {
      entries.add(TimesheetDailyEntry());
    }
    return Timesheet(
      id: j['id'] as String,
      workerId: j['worker_id'] as String,
      workerName: j['worker_name'] as String,
      position: j['position'] as String,
      idNumber: j['id_number'] as String,
      nisNumber: j['nis_number'] as String,
      wageRate: (j['wage_rate'] as num).toDouble(),
      colaRate: (j['cola_rate'] as num?)?.toDouble() ?? 0.0,
      allowanceRate: (j['allowance_rate'] as num).toDouble(),
      corporationId: j['corporation_id'] as String,
      corporationName: j['corporation_name'] as String,
      electoralDistrict: j['electoral_district'] as String,
      groupNumber: j['group_number'] as String,
      fortnightStart: DateTime.parse(j['fortnight_start'] as String),
      fortnightEnd: DateTime.parse(j['fortnight_end'] as String),
      bankName: j['bank_name'] as String,
      accountNumber: j['account_number'] as String,
      branchName: j['branch_name'] as String,
      dailyEntries: entries,
      allowanceDays: j['allowance_days'] as int? ?? 0,
      remarks: j['remarks'] as String? ?? '',
      stage: TimesheetStage.values.byName(j['stage'] as String),
      approvalHistory: (j['approval_history'] as List? ?? const [])
          .map((e) => ApprovalRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: DateTime.parse(j['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'worker_id': workerId,
        'worker_name': workerName,
        'position': position,
        'id_number': idNumber,
        'nis_number': nisNumber,
        'wage_rate': wageRate,
        'cola_rate': colaRate,
        'allowance_rate': allowanceRate,
        'corporation_id': corporationId,
        'corporation_name': corporationName,
        'electoral_district': electoralDistrict,
        'group_number': groupNumber,
        'fortnight_start': fortnightStart.toIso8601String(),
        'fortnight_end': fortnightEnd.toIso8601String(),
        'bank_name': bankName,
        'account_number': accountNumber,
        'branch_name': branchName,
        'daily_entries': dailyEntries.map((e) => e.toJson()).toList(),
        'allowance_days': allowanceDays,
        'remarks': remarks,
        'stage': stage.name,
        'approval_history':
            approvalHistory.map((a) => a.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
