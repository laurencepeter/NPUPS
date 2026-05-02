// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Fortnightly attendance roster: workers are present Mon-Fri by default.
// Data entry staff uncheck absent days. Admins can enable weekend work
// and set max-days-per-fortnight (default 10, overridable per worker).
// ──────────────────────────────────────────────────────────────────────────────

// Per-worker attendance for a single day in the roster.
class RosterDayEntry {
  final DateTime date;
  bool isPresent;
  // Why the worker was absent (optional, filled by data entry staff)
  String? absenceReason;

  RosterDayEntry({
    required this.date,
    required this.isPresent,
    this.absenceReason,
  });

  bool get isWeekend {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  String get dayLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}

// One worker's full fortnight attendance record.
class WorkerRosterRecord {
  final String workerId;
  final String workerName;
  final String position;
  final String corporationId;
  // 14 entries, one per day in the fortnight
  final List<RosterDayEntry> days;
  // Admin can override the global max for this specific worker
  int? maxDaysOverride;
  final String? notes;

  WorkerRosterRecord({
    required this.workerId,
    required this.workerName,
    required this.position,
    required this.corporationId,
    required this.days,
    this.maxDaysOverride,
    this.notes,
  });

  int get daysPresent => days.where((d) => d.isPresent).length;

  int get weekdaysPresent =>
      days.where((d) => d.isPresent && !d.isWeekend).length;

  int get weekendDaysPresent =>
      days.where((d) => d.isPresent && d.isWeekend).length;

  bool isOverMax(int globalMax) {
    final effectiveMax = maxDaysOverride ?? globalMax;
    return daysPresent > effectiveMax;
  }
}

// Settings for a fortnight roster — applies corporation-wide.
class RosterSettings {
  final String corporationId;
  // Default max days any worker may be present per fortnight
  int maxDaysPerFortnight;
  // Whether weekend days are shown/enabled in the roster at all
  bool allowWeekendWork;
  // Admin can allow entry beyond maxDaysPerFortnight for exceptional cases
  bool allowMaxDaysOverride;
  // If true data entry staff can set per-worker override; otherwise only admin
  bool dataEntryCanOverride;

  RosterSettings({
    required this.corporationId,
    this.maxDaysPerFortnight = 10,
    this.allowWeekendWork = false,
    this.allowMaxDaysOverride = true,
    this.dataEntryCanOverride = false,
  });
}

// The full roster for one fortnight at one corporation.
class FortnightRoster {
  final String id;
  final String corporationId;
  final String corporationName;
  final DateTime fortnightStart;
  final DateTime fortnightEnd;
  final List<WorkerRosterRecord> workerRecords;
  DateTime lastModified;
  String? lastModifiedBy;

  FortnightRoster({
    required this.id,
    required this.corporationId,
    required this.corporationName,
    required this.fortnightStart,
    required this.fortnightEnd,
    required this.workerRecords,
    DateTime? lastModified,
    this.lastModifiedBy,
  }) : lastModified = lastModified ?? DateTime.now();

  String get fortnightLabel {
    final pad2 = (int n) => n.toString().padLeft(2, '0');
    final s = fortnightStart;
    final e = fortnightEnd;
    return '${pad2(s.day)}/${pad2(s.month)}/${s.year} – '
        '${pad2(e.day)}/${pad2(e.month)}/${e.year}';
  }

  // List the 14 dates in this fortnight
  List<DateTime> get allDates {
    return List.generate(
      14,
      (i) => fortnightStart.add(Duration(days: i)),
    );
  }
}
