// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Manages fortnightly attendance rosters. Workers are present Mon-Fri by
// default; data entry staff check off absences. Admins configure max days
// (default 10) and can enable weekend shifts per corporation.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/roster_model.dart';
import '../models/worker_model.dart';
import 'api_client.dart';
import 'worker_data_store.dart';

class RosterService extends ChangeNotifier {
  static final RosterService _instance = RosterService._internal();
  factory RosterService() => _instance;
  RosterService._internal();

  final WorkerDataStore _workerStore = WorkerDataStore();
  final ApiClient _api = ApiClient();
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Hydrate settings + rosters from the backend. Settings are seeded with
  /// per-corporation defaults in db/domain_schema.sql; rosters are fetched
  /// in full (worker_records and 14-day day_entries inline).
  Future<void> loadFromBackend({bool force = false}) async {
    if (_loaded && !force) return;
    _settings.clear();
    final settingsJson = await _api.getList('/api/roster-settings');
    for (final s in settingsJson) {
      final r = RosterSettings.fromJson(s as Map<String, dynamic>);
      _settings[r.corporationId] = r;
    }
    _rosters.clear();
    final rostersJson = await _api.getList('/api/rosters');
    for (final j in rostersJson) {
      final r = FortnightRoster.fromJson(j as Map<String, dynamic>);
      _rosters[r.id] = r;
    }
    _loaded = true;
    notifyListeners();
  }

  // corporationId → settings
  final Map<String, RosterSettings> _settings = {};

  // rosterId → FortnightRoster
  final Map<String, FortnightRoster> _rosters = {};

  // ── Settings ────────────────────────────────────────────────────────────────

  RosterSettings getSettings(String corporationId) {
    return _settings.putIfAbsent(
      corporationId,
      () => RosterSettings(corporationId: corporationId),
    );
  }

  void updateSettings(RosterSettings updated) {
    _settings[updated.corporationId] = updated;
    notifyListeners();
  }

  // ── Roster Access ───────────────────────────────────────────────────────────

  List<FortnightRoster> getAllRosters() => _rosters.values.toList()
    ..sort((a, b) => b.fortnightStart.compareTo(a.fortnightStart));

  List<FortnightRoster> getRostersForCorporation(String corporationId) =>
      _rosters.values
          .where((r) => r.corporationId == corporationId)
          .toList()
        ..sort((a, b) => b.fortnightStart.compareTo(a.fortnightStart));

  FortnightRoster? getRoster(String rosterId) => _rosters[rosterId];

  /// Find or create the current-fortnight roster for a corporation.
  FortnightRoster getOrCreateRoster({
    required String corporationId,
    required String corporationName,
    required DateTime fortnightStart,
  }) {
    final end = fortnightStart.add(const Duration(days: 13));
    final id = _rosterId(corporationId, fortnightStart);

    if (_rosters.containsKey(id)) return _rosters[id]!;

    final workers = _workerStore.getActiveByCorpId(corporationId);
    final roster = _buildRoster(
      id: id,
      corporationId: corporationId,
      corporationName: corporationName,
      start: fortnightStart,
      end: end,
      workers: workers,
    );
    _rosters[id] = roster;
    notifyListeners();
    return roster;
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  void toggleDayPresence({
    required String rosterId,
    required String workerId,
    required int dayIndex,
    required bool isPresent,
    String? absenceReason,
    String? modifiedBy,
  }) {
    final roster = _rosters[rosterId];
    if (roster == null) return;

    final record = roster.workerRecords.firstWhere(
      (r) => r.workerId == workerId,
      orElse: () => throw StateError('Worker $workerId not in roster $rosterId'),
    );

    if (dayIndex < 0 || dayIndex >= record.days.length) return;
    record.days[dayIndex].isPresent = isPresent;
    record.days[dayIndex].absenceReason = isPresent ? null : absenceReason;

    roster.lastModified = DateTime.now();
    roster.lastModifiedBy = modifiedBy;
    notifyListeners();
  }

  void setWorkerMaxDaysOverride({
    required String rosterId,
    required String workerId,
    required int? maxDays,
  }) {
    final roster = _rosters[rosterId];
    if (roster == null) return;

    try {
      final record = roster.workerRecords.firstWhere((r) => r.workerId == workerId);
      record.maxDaysOverride = maxDays;
      notifyListeners();
    } catch (_) {}
  }

  void refreshRosterForCorporation(String corporationId) {
    final affected = _rosters.values
        .where((r) => r.corporationId == corporationId)
        .toList();

    for (final roster in affected) {
      final existingIds = roster.workerRecords.map((r) => r.workerId).toSet();
      final currentWorkers = _workerStore.getActiveByCorpId(corporationId);

      for (final worker in currentWorkers) {
        if (!existingIds.contains(worker.id)) {
          roster.workerRecords.add(_buildWorkerRecord(worker, roster.allDates));
        }
      }
    }
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _rosterId(String corpId, DateTime start) {
    final pad = (int n) => n.toString().padLeft(2, '0');
    return 'ROSTER-$corpId-${start.year}${pad(start.month)}${pad(start.day)}';
  }

  FortnightRoster _buildRoster({
    required String id,
    required String corporationId,
    required String corporationName,
    required DateTime start,
    required DateTime end,
    required List<Worker> workers,
  }) {
    final dates = List.generate(14, (i) => start.add(Duration(days: i)));
    return FortnightRoster(
      id: id,
      corporationId: corporationId,
      corporationName: corporationName,
      fortnightStart: start,
      fortnightEnd: end,
      workerRecords: workers.map((w) => _buildWorkerRecord(w, dates)).toList(),
    );
  }

  WorkerRosterRecord _buildWorkerRecord(Worker worker, List<DateTime> dates) {
    return WorkerRosterRecord(
      workerId: worker.id,
      workerName: worker.fullName,
      position: worker.position,
      corporationId: worker.corporationId,
      days: dates.map((date) {
        final isWeekend =
            date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
        return RosterDayEntry(
          date: date,
          isPresent: !isWeekend, // Mon-Fri = present, Sat-Sun = absent
        );
      }).toList(),
    );
  }

  // Demo settings seeding and demo-absence injection have been removed —
  // both now live in db/domain_schema.sql and arrive via loadFromBackend().

  // Calculate the start of the fortnight that contains [date].
  // Fortnight 1: 1st–14th, Fortnight 2: 15th–28th/last of month.
  static DateTime _fortnightStart(DateTime date) {
    if (date.day <= 14) {
      return DateTime(date.year, date.month, 1);
    } else {
      return DateTime(date.year, date.month, 15);
    }
  }

  static DateTime currentFortnightStart() => _fortnightStart(DateTime.now());
}
