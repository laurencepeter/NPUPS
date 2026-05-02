// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Fortnightly attendance grid: workers (rows) × days (columns).
// Mon-Fri defaults to Present (checked). Data entry staff uncheck absences.
// Admin can configure max-days limit, weekend work, and per-worker overrides.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/roster_model.dart';
import '../models/user_model.dart';
import '../services/roster_service.dart';
import '../services/audit_service.dart';
import '../models/audit_model.dart';
import '../theme/app_theme.dart';

class RosterScreen extends StatefulWidget {
  final AppUser currentUser;

  const RosterScreen({super.key, required this.currentUser});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final RosterService _rosterService = RosterService();
  final AuditService _auditService = AuditService();

  String get _corpId => widget.currentUser.corporationId ?? '8';
  String get _corpName =>
      widget.currentUser.corporationName ?? 'Port of Spain City Corporation';

  bool get _isAdmin =>
      widget.currentUser.role == UserRole.systemAdmin ||
      widget.currentUser.role == UserRole.dmcr;

  bool get _canEdit =>
      _isAdmin ||
      widget.currentUser.role == UserRole.hr ||
      widget.currentUser.role == UserRole.regionalCoordinator;

  late FortnightRoster _roster;

  @override
  void initState() {
    super.initState();
    _loadCurrentRoster();
  }

  void _loadCurrentRoster() {
    _roster = _rosterService.getOrCreateRoster(
      corporationId: _corpId,
      corporationName: _corpName,
      fortnightStart: RosterService.currentFortnightStart(),
    );
  }

  RosterSettings get _settings => _rosterService.getSettings(_corpId);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _rosterService,
      builder: (context, _) {
        _loadCurrentRoster();
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attendance Roster',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _roster.fortnightLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Roster Settings',
                  onPressed: () => _showSettingsDialog(context),
                ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Legend',
                onPressed: () => _showLegend(context),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSummaryBar(isDark),
              Expanded(child: _buildGrid(isDark)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryBar(bool isDark) {
    final settings = _settings;
    final total = _roster.workerRecords.length;
    final overMax = _roster.workerRecords
        .where((r) => r.isOverMax(settings.maxDaysPerFortnight))
        .length;

    return Container(
      color: isDark ? AppColors.darkCard : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _summaryChip(
            icon: Icons.people_outline,
            label: '$total Workers',
            color: AppColors.info,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _summaryChip(
            icon: Icons.event_available_outlined,
            label: 'Max ${settings.maxDaysPerFortnight} days/fortnight',
            color: AppColors.accent,
            isDark: isDark,
          ),
          if (overMax > 0) ...[
            const SizedBox(width: 8),
            _summaryChip(
              icon: Icons.warning_amber_outlined,
              label: '$overMax over limit',
              color: AppColors.error,
              isDark: isDark,
            ),
          ],
          const Spacer(),
          if (!_canEdit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('View Only',
                  style: TextStyle(fontSize: 11, color: AppColors.warning)),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(
      {required IconData icon,
      required String label,
      required Color color,
      required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _buildGrid(bool isDark) {
    final allDates = _roster.allDates;
    final settings = _settings;

    // Filter dates based on weekend setting
    final visibleDates = settings.allowWeekendWork
        ? allDates
        : allDates
            .where((d) =>
                d.weekday != DateTime.saturday &&
                d.weekday != DateTime.sunday)
            .toList();

    if (_roster.workerRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48,
                color: isDark
                    ? AppColors.darkTextHint
                    : AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'No active workers for this corporation',
              style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Fixed column widths
    const nameColWidth = 160.0;
    const dayColWidth = 44.0;
    const totalColWidth = 60.0;

    final headerBg = isDark ? AppColors.darkCardElevated : AppColors.primary;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Container(
              color: headerBg,
              child: Row(
                children: [
                  _headerCell('Worker', nameColWidth, isDark, isName: true),
                  ...visibleDates.map((date) {
                    final isWeekend = date.weekday == DateTime.saturday ||
                        date.weekday == DateTime.sunday;
                    return _headerCell(
                      '${_dayAbbr(date.weekday)}\n${date.day}',
                      dayColWidth,
                      isDark,
                      isWeekend: isWeekend,
                    );
                  }),
                  _headerCell('Days', totalColWidth, isDark),
                ],
              ),
            ),

            // ── Worker rows ─────────────────────────────────────────────
            ...List.generate(_roster.workerRecords.length, (wi) {
              final record = _roster.workerRecords[wi];
              final effectiveMax = record.maxDaysOverride ??
                  settings.maxDaysPerFortnight;
              final isOver = record.daysPresent > effectiveMax;
              final rowBg = isDark
                  ? (wi.isOdd
                      ? AppColors.darkCard
                      : AppColors.darkSurface)
                  : (wi.isOdd ? Colors.white : AppColors.surface);

              return Container(
                color: rowBg,
                child: Row(
                  children: [
                    // Worker name cell
                    GestureDetector(
                      onTap: _canEdit && _isAdmin
                          ? () => _showWorkerOverrideDialog(
                              context, record, settings)
                          : null,
                      child: SizedBox(
                        width: nameColWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.workerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                record.position,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? AppColors.darkTextHint
                                      : AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (record.maxDaysOverride != null)
                                Text(
                                  'Max: ${record.maxDaysOverride}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AppColors.warning,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Day checkboxes
                    ...visibleDates.map((date) {
                      final dayIdx =
                          allDates.indexWhere((d) => d.day == date.day);
                      if (dayIdx == -1) return SizedBox(width: dayColWidth);
                      final dayEntry = record.days[dayIdx];
                      final isWeekend = date.weekday == DateTime.saturday ||
                          date.weekday == DateTime.sunday;

                      return SizedBox(
                        width: dayColWidth,
                        height: 48,
                        child: Center(
                          child: _DayCheckbox(
                            isPresent: dayEntry.isPresent,
                            isWeekend: isWeekend,
                            canEdit: _canEdit,
                            isDark: isDark,
                            onChanged: (val) => _toggleDay(
                              record.workerId,
                              dayIdx,
                              val,
                              record.workerName,
                              date,
                            ),
                          ),
                        ),
                      );
                    }),

                    // Days total
                    SizedBox(
                      width: totalColWidth,
                      height: 48,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOver
                                ? AppColors.error.withValues(alpha: 0.12)
                                : AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${record.daysPresent}/${effectiveMax}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOver
                                  ? AppColors.error
                                  : AppColors.success,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width, bool isDark,
      {bool isName = false, bool isWeekend = false}) {
    final headerFg = isDark ? AppColors.darkTextPrimary : Colors.white;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          text,
          textAlign: isName ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isWeekend
                ? headerFg.withValues(alpha: 0.5)
                : headerFg,
          ),
        ),
      ),
    );
  }

  void _toggleDay(
    String workerId,
    int dayIdx,
    bool isPresent,
    String workerName,
    DateTime date,
  ) {
    final oldVal = _roster.workerRecords
        .firstWhere((r) => r.workerId == workerId)
        .days[dayIdx]
        .isPresent;

    _rosterService.toggleDayPresence(
      rosterId: _roster.id,
      workerId: workerId,
      dayIndex: dayIdx,
      isPresent: isPresent,
      modifiedBy: widget.currentUser.fullName,
    );

    final pad = (int n) => n.toString().padLeft(2, '0');
    final dateStr =
        '${_dayAbbr(date.weekday)} ${pad(date.day)}/${pad(date.month)}';

    _auditService.log(
      actor: widget.currentUser,
      action: AuditAction.rosterUpdate,
      entityType: AuditEntityType.rosterEntry,
      entityId: _roster.id,
      entityDisplayName:
          '$_corpName – ${_roster.fortnightLabel}',
      fieldChanges: [
        AuditFieldChange(
          fieldName: '$workerName – $dateStr',
          oldValue: oldVal ? 'Present' : 'Absent',
          newValue: isPresent ? 'Present' : 'Absent',
        ),
      ],
    );
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    final settings = _settings;
    int maxDays = settings.maxDaysPerFortnight;
    bool allowWeekends = settings.allowWeekendWork;
    bool allowOverride = settings.allowMaxDaysOverride;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.settings_outlined, size: 20),
              SizedBox(width: 8),
              Text('Roster Settings'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Max days
              Row(
                children: [
                  const Expanded(
                    child: Text('Max days per fortnight',
                        style: TextStyle(fontSize: 14)),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: maxDays > 1
                            ? () => setDlgState(() => maxDays--)
                            : null,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('$maxDays',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () => setDlgState(() => maxDays++),
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow weekend work',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('Shows Sat/Sun columns in roster',
                    style: TextStyle(fontSize: 12)),
                value: allowWeekends,
                onChanged: (v) => setDlgState(() => allowWeekends = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow max-days override',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('Permit individual workers to exceed limit',
                    style: TextStyle(fontSize: 12)),
                value: allowOverride,
                onChanged: (v) => setDlgState(() => allowOverride = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _rosterService.updateSettings(RosterSettings(
                  corporationId: _corpId,
                  maxDaysPerFortnight: maxDays,
                  allowWeekendWork: allowWeekends,
                  allowMaxDaysOverride: allowOverride,
                ));
                _auditService.log(
                  actor: widget.currentUser,
                  action: AuditAction.settingsChange,
                  entityType: AuditEntityType.rosterSettings,
                  entityId: 'SETTINGS-$_corpId',
                  entityDisplayName: '$_corpName Roster Settings',
                  fieldChanges: [
                    AuditFieldChange(
                      fieldName: 'Max Days Per Fortnight',
                      oldValue: '${settings.maxDaysPerFortnight}',
                      newValue: '$maxDays',
                    ),
                    if (allowWeekends != settings.allowWeekendWork)
                      AuditFieldChange(
                        fieldName: 'Allow Weekend Work',
                        oldValue: '${settings.allowWeekendWork}',
                        newValue: '$allowWeekends',
                      ),
                  ],
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWorkerOverrideDialog(BuildContext context,
      WorkerRosterRecord record, RosterSettings settings) async {
    if (!settings.allowMaxDaysOverride) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Per-worker override is disabled in settings')),
      );
      return;
    }

    int? override = record.maxDaysOverride;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Override: ${record.workerName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Global max is ${settings.maxDaysPerFortnight} days. '
                'Set a custom limit for this worker.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Custom max: ',
                      style: TextStyle(fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: (override ?? settings.maxDaysPerFortnight) > 1
                        ? () => setDlgState(() =>
                            override = (override ?? settings.maxDaysPerFortnight) - 1)
                        : null,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Text(
                    '${override ?? settings.maxDaysPerFortnight}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => setDlgState(() =>
                        override = (override ?? settings.maxDaysPerFortnight) + 1),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _rosterService.setWorkerMaxDaysOverride(
                    rosterId: _roster.id,
                    workerId: record.workerId,
                    maxDays: null);
                Navigator.of(ctx).pop();
              },
              child: const Text('Clear Override'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _rosterService.setWorkerMaxDaysOverride(
                    rosterId: _roster.id,
                    workerId: record.workerId,
                    maxDays: override);
                Navigator.of(ctx).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLegend(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _legendRow(color: AppColors.success, label: 'Present (checked)'),
            _legendRow(color: AppColors.error, label: 'Absent (unchecked)'),
            _legendRow(
                color: AppColors.textHint,
                label: 'Weekend (greyed out when disabled)'),
            _legendRow(
                color: AppColors.warning,
                label: 'Worker has custom max-days override'),
            const SizedBox(height: 8),
            const Text('Days count shows "present/max" per worker.',
                style: TextStyle(fontSize: 12)),
            const Text('Red count means worker exceeds the limit.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _legendRow({required Color color, required String label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
              width: 14, height: 14, color: color.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  static String _dayAbbr(int weekday) {
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d[weekday - 1];
  }
}

// ── Day Checkbox Widget ────────────────────────────────────────────────────────

class _DayCheckbox extends StatelessWidget {
  final bool isPresent;
  final bool isWeekend;
  final bool canEdit;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _DayCheckbox({
    required this.isPresent,
    required this.isWeekend,
    required this.canEdit,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = isWeekend ? AppColors.accentLight : AppColors.success;
    final Color inactiveColor = isDark ? AppColors.darkTextHint : AppColors.textHint;

    return Checkbox(
      value: isPresent,
      onChanged: canEdit ? (v) => onChanged(v ?? false) : null,
      activeColor: activeColor,
      checkColor: Colors.white,
      side: BorderSide(color: inactiveColor, width: 1.5),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
