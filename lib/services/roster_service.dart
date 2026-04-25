// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Roster Service
// Manages fortnightly attendance rosters. Workers are present Mon-Fri by
// default; data entry staff check off absences. Admins configure max days
// (default 10) and can enable weekend shifts per corporation.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/roster_model.dart';
import '../models/worker_model.dart';
import 'worker_data_store.dart';

class RosterService extends ChangeNotifier {
  static final RosterService _instance = RosterService._internal();
  factory RosterService() => _instance;
  RosterService._internal() {
    _initSettings();
    _buildCurrentRosters();
  }

  final WorkerDataStore _workerStore = WorkerDataStore();

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

  void _initSettings() {
    // Pre-seed settings for known corporations
    for (final corpId in ['2', '3', '8']) {
      _settings[corpId] = RosterSettings(corporationId: corpId);
    }
  }

  void _buildCurrentRosters() {
    // Build rosters for each known corporation for the current and previous fortnight
    final corps = [
      ('2', 'Chaguanas Borough Corporation'),
      ('3', 'San Fernando City Corporation'),
      ('8', 'Port of Spain City Corporation'),
    ];

    final now = DateTime.now();
    final currentStart = _fortnightStart(now);
    final prevStart = currentStart.subtract(const Duration(days: 14));

    for (final (corpId, corpName) in corps) {
      for (final start in [currentStart, prevStart]) {
        final id = _rosterId(corpId, start);
        final workers = _workerStore.getActiveByCorpId(corpId);
        if (workers.isEmpty) continue;
        final roster = _buildRoster(
          id: id,
          corporationId: corpId,
          corporationName: corpName,
          start: start,
          end: start.add(const Duration(days: 13)),
          workers: workers,
        );
        _rosters[id] = roster;
      }
    }

    // Inject a couple of demo absences
    _injectDemoAbsences();
  }

  void _injectDemoAbsences() {
    for (final roster in _rosters.values) {
      if (roster.workerRecords.isEmpty) continue;
      // Mark day index 1 (Tuesday) absent for first worker
      final first = roster.workerRecords.first;
      if (first.days.length > 1) {
        first.days[1].isPresent = false;
        first.days[1].absenceReason = 'Sick leave';
      }
      // Mark day index 3 (Thursday) absent for second worker if present
      if (roster.workerRecords.length > 1) {
        final second = roster.workerRecords[1];
        if (second.days.length > 3) {
          second.days[3].isPresent = false;
        }
      }
    }
  }

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
