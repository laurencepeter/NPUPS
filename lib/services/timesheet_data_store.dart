// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Timesheet Data Store
// In-memory singleton with demo timesheets at various pipeline stages.
// Provides querying by stage, corporation, worker, and region.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/timesheet_model.dart';

class TimesheetDataStore extends ChangeNotifier {
  static final TimesheetDataStore _instance = TimesheetDataStore._internal();
  factory TimesheetDataStore() => _instance;
  TimesheetDataStore._internal() {
    _initializeDemoData();
  }

  final List<Timesheet> _timesheets = [];
  List<Timesheet> get timesheets => List.unmodifiable(_timesheets);

  // ── Queries ──────────────────────────────────────────────────────────────

  List<Timesheet> getByStage(TimesheetStage stage) =>
      _timesheets.where((t) => t.stage == stage).toList();

  List<Timesheet> getByWorker(String workerId) =>
      _timesheets.where((t) => t.workerId == workerId).toList();

  List<Timesheet> getByCorporation(String corpId) =>
      _timesheets.where((t) => t.corporationId == corpId).toList();

  List<Timesheet> getByStageAndCorporation(TimesheetStage stage, String corpId) =>
      _timesheets.where((t) => t.stage == stage && t.corporationId == corpId).toList();

  Timesheet? getById(String id) {
    try {
      return _timesheets.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Map<TimesheetStage, int> getStageCounts() {
    final counts = <TimesheetStage, int>{};
    for (final stage in TimesheetStage.values) {
      counts[stage] = _timesheets.where((t) => t.stage == stage).length;
    }
    return counts;
  }

  Map<String, Map<TimesheetStage, int>> getStageCountsByCorporation() {
    final result = <String, Map<TimesheetStage, int>>{};
    for (final t in _timesheets) {
      result.putIfAbsent(t.corporationName, () => {});
      result[t.corporationName]!.putIfAbsent(t.stage, () => 0);
      result[t.corporationName]![t.stage] = result[t.corporationName]![t.stage]! + 1;
    }
    return result;
  }

  List<Timesheet> getStalledTimesheets(Duration threshold) =>
      _timesheets.where((t) =>
          t.stage != TimesheetStage.notStarted &&
          t.stage != TimesheetStage.chequePrinting &&
          t.isStalled(threshold)).toList();

  double getTotalPayroll() =>
      _timesheets.fold(0.0, (sum, t) => sum + t.grandTotal);

  // ── Mutations ────────────────────────────────────────────────────────────

  void addTimesheet(Timesheet timesheet) {
    _timesheets.add(timesheet);
    notifyListeners();
  }

  void updateTimesheet(Timesheet timesheet) {
    timesheet.updatedAt = DateTime.now();
    notifyListeners();
  }

  void advanceStage(String timesheetId, String reviewerName, String reviewerRole, {String? note}) {
    final ts = getById(timesheetId);
    if (ts == null) return;
    ts.advanceStage(reviewerName, reviewerRole, note: note);
    notifyListeners();
  }

  void rejectTimesheet(String timesheetId, String reviewerName, String reviewerRole, String note) {
    final ts = getById(timesheetId);
    if (ts == null) return;
    ts.rejectToPreviousStage(reviewerName, reviewerRole, note);
    notifyListeners();
  }

  void batchAdvance(List<String> ids, String reviewerName, String reviewerRole, {String? note}) {
    for (final id in ids) {
      advanceStage(id, reviewerName, reviewerRole, note: note);
    }
  }

  // ── Demo Data ────────────────────────────────────────────────────────────

  static List<TimesheetDailyEntry> _weekdayEntries() {
    return List.generate(14, (i) {
      final isWeekday = (i % 7) < 5;
      return TimesheetDailyEntry(
        timeIn: isWeekday ? const TimeOfDay(hour: 7, minute: 0) : null,
        timeOut: isWeekday ? const TimeOfDay(hour: 15, minute: 0) : null,
      );
    });
  }

  static List<TimesheetDailyEntry> _partialEntries() {
    return List.generate(14, (i) {
      final isWeekday = (i % 7) < 5;
      final worked = isWeekday && i < 8; // Only first 8 days partially filled
      return TimesheetDailyEntry(
        timeIn: worked ? const TimeOfDay(hour: 7, minute: 0) : null,
        timeOut: worked ? const TimeOfDay(hour: 15, minute: 0) : null,
      );
    });
  }

  void _initializeDemoData() {
    final now = DateTime.now();
    final fortnightStart = now.subtract(Duration(days: now.weekday - 1 + 7)); // Last Monday
    final fortnightEnd = fortnightStart.add(const Duration(days: 13));

    _timesheets.addAll([
      // ── Not Started ────────────────────────────────────────────────────────
      Timesheet(
        id: 'TS-001', workerId: 'WRK-008', workerName: 'Terrence Charles',
        position: 'Drain Cleaner', idNumber: 'ID-TT-199812301', nisNumber: 'NIS-2024-01055',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '8', corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain North', groupNumber: '1',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Scotiabank', accountNumber: '3303-5544-6677', branchName: 'Frederick Street',
        stage: TimesheetStage.notStarted,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      Timesheet(
        id: 'TS-002', workerId: 'WRK-009', workerName: 'Camille Hospedales',
        position: 'Road Maintenance', idNumber: 'ID-TT-199108191', nisNumber: 'NIS-2024-01198',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '2', corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas East', groupNumber: '2',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'JMMB Bank', accountNumber: '5502-7788-9900', branchName: 'Endeavour Road',
        stage: TimesheetStage.notStarted,
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now.subtract(const Duration(days: 4)),
      ),

      // ── Draft ──────────────────────────────────────────────────────────────
      Timesheet(
        id: 'TS-003', workerId: 'WRK-005', workerName: 'Ravi Doobay',
        position: 'Landscaper', idNumber: 'ID-TT-199509071', nisNumber: 'NIS-2024-00621',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '8', corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain West', groupNumber: '1',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'JMMB Bank', accountNumber: '5501-3322-1144', branchName: 'Ariapita Avenue',
        dailyEntries: _partialEntries(), allowanceDays: 2, remarks: 'Partial entry',
        stage: TimesheetStage.draft,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      Timesheet(
        id: 'TS-004', workerId: 'WRK-010', workerName: 'Denise La Fortune',
        position: 'Landscaper', idNumber: 'ID-TT-198906111', nisNumber: 'NIS-2024-01342',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '3', corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando East', groupNumber: '3',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Republic Bank', accountNumber: '1108-2233-4455', branchName: 'Coffee Street',
        dailyEntries: _partialEntries(), remarks: 'Saving for later',
        stage: TimesheetStage.draft,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),

      // ── Submitted ──────────────────────────────────────────────────────────
      Timesheet(
        id: 'TS-005', workerId: 'WRK-001', workerName: 'Kevin Rampersad',
        position: 'General Worker', idNumber: 'ID-TT-198803150', nisNumber: 'NIS-2024-00147',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '8', corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain South', groupNumber: '1',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Republic Bank', accountNumber: '1102-4587-6321', branchName: 'Independence Square',
        dailyEntries: _weekdayEntries(), allowanceDays: 10,
        stage: TimesheetStage.submitted,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 18)),
      ),
      Timesheet(
        id: 'TS-006', workerId: 'WRK-002', workerName: 'Sasha Mohammed',
        position: 'Drain Cleaner', idNumber: 'ID-TT-199207221', nisNumber: 'NIS-2024-00203',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '8', corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain East', groupNumber: '1',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'First Citizens Bank', accountNumber: '2203-8765-1234', branchName: 'Park Street',
        dailyEntries: _weekdayEntries(), allowanceDays: 10,
        stage: TimesheetStage.submitted,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),

      // ── Coordinator Review ─────────────────────────────────────────────────
      Timesheet(
        id: 'TS-007', workerId: 'WRK-003', workerName: 'Andre Williams',
        position: 'Road Maintenance', idNumber: 'ID-TT-198511030', nisNumber: 'NIS-2023-01982',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '2', corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas North', groupNumber: '2',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Scotiabank', accountNumber: '3301-2244-5566', branchName: 'Chaguanas Main',
        dailyEntries: _weekdayEntries(), allowanceDays: 10,
        stage: TimesheetStage.coordinatorReview,
        approvalHistory: [
          ApprovalRecord(
            reviewerName: 'Andre Williams', reviewerRole: 'Worker',
            state: ApprovalState.approved, note: 'Submitted for review',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 36)),
      ),
      Timesheet(
        id: 'TS-008', workerId: 'WRK-004', workerName: 'Lisa Doodnath',
        position: 'General Worker', idNumber: 'ID-TT-199005181', nisNumber: 'NIS-2024-00489',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '2', corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas South', groupNumber: '2',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Republic Bank', accountNumber: '1104-9876-5432', branchName: 'Chaguanas',
        dailyEntries: _weekdayEntries(), allowanceDays: 10,
        stage: TimesheetStage.coordinatorReview,
        approvalHistory: [
          ApprovalRecord(
            reviewerName: 'Lisa Doodnath', reviewerRole: 'Worker',
            state: ApprovalState.approved, note: 'Submitted',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 28)),
      ),

      // ── HR Processing ──────────────────────────────────────────────────────
      Timesheet(
        id: 'TS-009', workerId: 'WRK-006', workerName: 'Marcia Boodoo',
        position: 'Street Cleaner', idNumber: 'ID-TT-198701251', nisNumber: 'NIS-2024-00788',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '3', corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando East', groupNumber: '3',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'First Citizens Bank', accountNumber: '2205-6677-8899', branchName: 'High Street',
        dailyEntries: _weekdayEntries(), allowanceDays: 10,
        stage: TimesheetStage.hrProcessing,
        approvalHistory: [
          ApprovalRecord(
            reviewerName: 'Marcia Boodoo', reviewerRole: 'Worker',
            state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 3)),
          ),
          ApprovalRecord(
            reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator',
            state: ApprovalState.approved, note: 'Verified attendance',
            timestamp: now.subtract(const Duration(days: 2)),
          ),
        ],
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 52)),
      ),
      Timesheet(
        id: 'TS-010', workerId: 'WRK-007', workerName: 'Jason Baptiste',
        position: 'General Worker', idNumber: 'ID-TT-199304141', nisNumber: 'NIS-2024-00912',
        wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
        corporationId: '3', corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando West', groupNumber: '3',
        fortnightStart: fortnightStart, fortnightEnd: fortnightEnd,
        bankName: 'Republic Bank', accountNumber: '1106-1122-3344', branchName: 'San Fernando',
        dailyEntries: _weekdayEntries(), allowanceDays: 8,
        stage: TimesheetStage.hrProcessing,
        approvalHistory: [
          ApprovalRecord(
            reviewerName: 'Jason Baptiste', reviewerRole: 'Worker',
            state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 3)),
          ),
          ApprovalRecord(
            reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator',
            state: ApprovalState.approved, note: 'All good',
            timestamp: now.subtract(const Duration(days: 2)),
          ),
        ],
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 60)),
      ),

      // ── Accounts Processing ────────────────────────────────────────────────
      _buildAccountsTimesheet(
        id: 'TS-011', workerId: 'WRK-101', name: 'Ronald Persad',
        position: 'General Worker', idNum: 'ID-TT-199001011', nis: 'NIS-2024-01501',
        corpId: '8', corpName: 'Port of Spain City Corporation', district: 'Port of Spain South',
        group: '1', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'Republic Bank', acct: '1109-1234-5678', branch: 'Independence Square',
      ),
      _buildAccountsTimesheet(
        id: 'TS-012', workerId: 'WRK-102', name: 'Sandra Ramsaran',
        position: 'Landscaper', idNum: 'ID-TT-198802022', nis: 'NIS-2024-01502',
        corpId: '2', corpName: 'Chaguanas Borough Corporation', district: 'Chaguanas North',
        group: '2', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'First Citizens Bank', acct: '2206-8765-4321', branch: 'Chaguanas',
      ),

      // ── Approved for Payment ───────────────────────────────────────────────
      _buildApprovedTimesheet(
        id: 'TS-013', workerId: 'WRK-103', name: 'Derek Singh',
        position: 'Road Maintenance', idNum: 'ID-TT-199203033', nis: 'NIS-2024-01503',
        corpId: '8', corpName: 'Port of Spain City Corporation', district: 'Laventille',
        group: '1', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'Scotiabank', acct: '3304-5566-7788', branch: 'Frederick Street',
      ),

      // ── Exported ───────────────────────────────────────────────────────────
      _buildExportedTimesheet(
        id: 'TS-014', workerId: 'WRK-104', name: 'Angela Pierre',
        position: 'Street Cleaner', idNum: 'ID-TT-198504044', nis: 'NIS-2024-01504',
        corpId: '3', corpName: 'San Fernando City Corporation', district: 'San Fernando East',
        group: '3', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'Republic Bank', acct: '1110-4455-6677', branch: 'Coffee Street',
      ),
      _buildExportedTimesheet(
        id: 'TS-015', workerId: 'WRK-105', name: 'Michael James',
        position: 'General Worker', idNum: 'ID-TT-199106055', nis: 'NIS-2024-01505',
        corpId: '8', corpName: 'Port of Spain City Corporation', district: 'Morvant',
        group: '1', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'JMMB Bank', acct: '5503-2233-4455', branch: 'Ariapita Avenue',
      ),

      // ── Cheque Printing / Direct Deposit ───────────────────────────────────
      _buildFinalTimesheet(
        id: 'TS-016', workerId: 'WRK-106', name: 'Patricia Garcia',
        position: 'General Worker', idNum: 'ID-TT-198707066', nis: 'NIS-2024-01506',
        corpId: '2', corpName: 'Chaguanas Borough Corporation', district: 'Chaguanas South',
        group: '2', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'Republic Bank', acct: '1111-6677-8899', branch: 'Chaguanas',
      ),
      _buildFinalTimesheet(
        id: 'TS-017', workerId: 'WRK-107', name: 'Vernon Alexander',
        position: 'Drain Cleaner', idNum: 'ID-TT-199308077', nis: 'NIS-2024-01507',
        corpId: '3', corpName: 'San Fernando City Corporation', district: 'San Fernando West',
        group: '3', start: fortnightStart, end: fortnightEnd, now: now,
        bankName: 'First Citizens Bank', acct: '2207-9988-7766', branch: 'High Street',
      ),
    ]);
  }

  static Timesheet _buildAccountsTimesheet({
    required String id, required String workerId, required String name,
    required String position, required String idNum, required String nis,
    required String corpId, required String corpName, required String district,
    required String group, required DateTime start, required DateTime end,
    required DateTime now, required String bankName, required String acct, required String branch,
  }) {
    return Timesheet(
      id: id, workerId: workerId, workerName: name, position: position,
      idNumber: idNum, nisNumber: nis, wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
      corporationId: corpId, corporationName: corpName, electoralDistrict: district,
      groupNumber: group, fortnightStart: start, fortnightEnd: end,
      bankName: bankName, accountNumber: acct, branchName: branch,
      dailyEntries: _weekdayEntries(), allowanceDays: 10,
      stage: TimesheetStage.accountsProcessing,
      approvalHistory: [
        ApprovalRecord(reviewerName: name, reviewerRole: 'Worker', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 5))),
        ApprovalRecord(reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 4))),
        ApprovalRecord(reviewerName: 'Priya Maharaj', reviewerRole: 'HR Department', state: ApprovalState.approved, note: 'Compliance verified', timestamp: now.subtract(const Duration(days: 3))),
      ],
      createdAt: now.subtract(const Duration(days: 7)),
      updatedAt: now.subtract(const Duration(hours: 40)),
    );
  }

  static Timesheet _buildApprovedTimesheet({
    required String id, required String workerId, required String name,
    required String position, required String idNum, required String nis,
    required String corpId, required String corpName, required String district,
    required String group, required DateTime start, required DateTime end,
    required DateTime now, required String bankName, required String acct, required String branch,
  }) {
    return Timesheet(
      id: id, workerId: workerId, workerName: name, position: position,
      idNumber: idNum, nisNumber: nis, wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
      corporationId: corpId, corporationName: corpName, electoralDistrict: district,
      groupNumber: group, fortnightStart: start, fortnightEnd: end,
      bankName: bankName, accountNumber: acct, branchName: branch,
      dailyEntries: _weekdayEntries(), allowanceDays: 10,
      stage: TimesheetStage.approvedForPayment,
      approvalHistory: [
        ApprovalRecord(reviewerName: name, reviewerRole: 'Worker', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 6))),
        ApprovalRecord(reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 5))),
        ApprovalRecord(reviewerName: 'Priya Maharaj', reviewerRole: 'HR Department', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 4))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, note: 'Pay calculations verified', timestamp: now.subtract(const Duration(days: 2))),
      ],
      createdAt: now.subtract(const Duration(days: 8)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
  }

  static Timesheet _buildExportedTimesheet({
    required String id, required String workerId, required String name,
    required String position, required String idNum, required String nis,
    required String corpId, required String corpName, required String district,
    required String group, required DateTime start, required DateTime end,
    required DateTime now, required String bankName, required String acct, required String branch,
  }) {
    return Timesheet(
      id: id, workerId: workerId, workerName: name, position: position,
      idNumber: idNum, nisNumber: nis, wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
      corporationId: corpId, corporationName: corpName, electoralDistrict: district,
      groupNumber: group, fortnightStart: start, fortnightEnd: end,
      bankName: bankName, accountNumber: acct, branchName: branch,
      dailyEntries: _weekdayEntries(), allowanceDays: 10,
      stage: TimesheetStage.exported,
      approvalHistory: [
        ApprovalRecord(reviewerName: name, reviewerRole: 'Worker', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 8))),
        ApprovalRecord(reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 7))),
        ApprovalRecord(reviewerName: 'Priya Maharaj', reviewerRole: 'HR Department', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 6))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 4))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, note: 'Exported to paysheet', timestamp: now.subtract(const Duration(days: 1))),
      ],
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
  }

  static Timesheet _buildFinalTimesheet({
    required String id, required String workerId, required String name,
    required String position, required String idNum, required String nis,
    required String corpId, required String corpName, required String district,
    required String group, required DateTime start, required DateTime end,
    required DateTime now, required String bankName, required String acct, required String branch,
  }) {
    return Timesheet(
      id: id, workerId: workerId, workerName: name, position: position,
      idNumber: idNum, nisNumber: nis, wageRate: 150.0, colaRate: 25.0, allowanceRate: 40.0,
      corporationId: corpId, corporationName: corpName, electoralDistrict: district,
      groupNumber: group, fortnightStart: start, fortnightEnd: end,
      bankName: bankName, accountNumber: acct, branchName: branch,
      dailyEntries: _weekdayEntries(), allowanceDays: 10,
      stage: TimesheetStage.chequePrinting,
      approvalHistory: [
        ApprovalRecord(reviewerName: name, reviewerRole: 'Worker', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 10))),
        ApprovalRecord(reviewerName: 'Marcus Thompson', reviewerRole: 'Regional Coordinator', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 9))),
        ApprovalRecord(reviewerName: 'Priya Maharaj', reviewerRole: 'HR Department', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 7))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, timestamp: now.subtract(const Duration(days: 5))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, note: 'Exported', timestamp: now.subtract(const Duration(days: 3))),
        ApprovalRecord(reviewerName: 'James Roberts', reviewerRole: 'Accounts', state: ApprovalState.approved, note: 'Direct deposit initiated', timestamp: now.subtract(const Duration(days: 1))),
      ],
      createdAt: now.subtract(const Duration(days: 12)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
  }
}
