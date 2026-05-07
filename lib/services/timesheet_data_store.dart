// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Timesheet cache backed by the WorkForce REST API.
//
// All timesheet data — including the 14-day daily grid and approval history —
// is sourced from the PostgreSQL database via `ApiClient`. Hardcoded demo
// timesheets used to live here; they have been moved to db/domain_schema.sql.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/timesheet_model.dart';
import 'api_client.dart';

class TimesheetDataStore extends ChangeNotifier {
  static final TimesheetDataStore _instance = TimesheetDataStore._internal();
  factory TimesheetDataStore() => _instance;
  TimesheetDataStore._internal();

  final ApiClient _api = ApiClient();
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> loadFromBackend({bool force = false}) async {
    if (_loaded && !force) return;
    final json = await _api.getList('/api/timesheets');
    _timesheets
      ..clear()
      ..addAll(json.map((j) => Timesheet.fromJson(j as Map<String, dynamic>)));
    _loaded = true;
    notifyListeners();
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


  // ── Demo data removed ────────────────────────────────────────────────────
  // 17 hardcoded timesheets (TS-001..TS-017), 14-day grids and approval
  // history have been moved to db/domain_schema.sql. The frontend now
  // fetches them from the backend via loadFromBackend() above.
}
