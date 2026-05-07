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

  factory RosterDayEntry.fromJson(Map<String, dynamic> j) => RosterDayEntry(
        date: DateTime.parse(j['entry_date'] as String),
        isPresent: j['is_present'] as bool,
        absenceReason: j['absence_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'entry_date': date.toIso8601String(),
        'is_present': isPresent,
        'absence_reason': absenceReason,
      };
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

  factory WorkerRosterRecord.fromJson(Map<String, dynamic> j) =>
      WorkerRosterRecord(
        workerId: j['worker_id'] as String,
        workerName: j['worker_name'] as String,
        position: j['position'] as String,
        corporationId: j['corporation_id'] as String,
        days: (j['days'] as List? ?? const [])
            .map((e) => RosterDayEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        maxDaysOverride: j['max_days_override'] as int?,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'worker_id': workerId,
        'worker_name': workerName,
        'position': position,
        'corporation_id': corporationId,
        'days': days.map((d) => d.toJson()).toList(),
        'max_days_override': maxDaysOverride,
        'notes': notes,
      };
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

  factory RosterSettings.fromJson(Map<String, dynamic> j) => RosterSettings(
        corporationId: j['corporation_id'] as String,
        maxDaysPerFortnight: j['max_days_per_fortnight'] as int? ?? 10,
        allowWeekendWork: j['allow_weekend_work'] as bool? ?? false,
        allowMaxDaysOverride: j['allow_max_days_override'] as bool? ?? true,
        dataEntryCanOverride: j['data_entry_can_override'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'corporation_id': corporationId,
        'max_days_per_fortnight': maxDaysPerFortnight,
        'allow_weekend_work': allowWeekendWork,
        'allow_max_days_override': allowMaxDaysOverride,
        'data_entry_can_override': dataEntryCanOverride,
      };
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

  factory FortnightRoster.fromJson(Map<String, dynamic> j) => FortnightRoster(
        id: j['id'] as String,
        corporationId: j['corporation_id'] as String,
        corporationName: j['corporation_name'] as String,
        fortnightStart: DateTime.parse(j['fortnight_start'] as String),
        fortnightEnd: DateTime.parse(j['fortnight_end'] as String),
        workerRecords: (j['worker_records'] as List? ?? const [])
            .map((e) => WorkerRosterRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        lastModified: j['last_modified'] != null
            ? DateTime.parse(j['last_modified'] as String)
            : null,
        lastModifiedBy: j['last_modified_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'corporation_id': corporationId,
        'corporation_name': corporationName,
        'fortnight_start': fortnightStart.toIso8601String(),
        'fortnight_end': fortnightEnd.toIso8601String(),
        'worker_records': workerRecords.map((r) => r.toJson()).toList(),
        'last_modified': lastModified.toIso8601String(),
        'last_modified_by': lastModifiedBy,
      };
}
