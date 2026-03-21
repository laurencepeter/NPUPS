// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Permanent Secretary Dashboard — Full Pipeline Oversight
//
// Features:
//   - Summary counts per stage (Not Started → Cheque Printing)
//   - Visual pipeline tracker (horizontal flow)
//   - Drill down by region, department, individual worker
//   - Filter by: stage, region, department, date range, overdue/stalled
//   - Bottleneck detection — flag stalled timesheets (>48h configurable)
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../services/timesheet_data_store.dart';

class PsDashboardScreen extends StatefulWidget {
  final NpupsUser user;
  const PsDashboardScreen({super.key, required this.user});

  @override
  State<PsDashboardScreen> createState() => _PsDashboardScreenState();
}

class _PsDashboardScreenState extends State<PsDashboardScreen>
    with SingleTickerProviderStateMixin {
  final TimesheetDataStore _store = TimesheetDataStore();
  late final TabController _tabController;

  // Filters
  String? _filterCorporation;
  TimesheetStage? _filterStage;
  bool _showStalledOnly = false;
  Duration _stalledThreshold = const Duration(hours: 48);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Timesheet> get _filteredTimesheets {
    var list = _store.timesheets.toList();
    if (_filterCorporation != null) {
      list = list.where((t) => t.corporationName == _filterCorporation).toList();
    }
    if (_filterStage != null) {
      list = list.where((t) => t.stage == _filterStage).toList();
    }
    if (_showStalledOnly) {
      list = list.where((t) => t.isStalled(_stalledThreshold) &&
          t.stage != TimesheetStage.notStarted &&
          t.stage != TimesheetStage.chequePrinting).toList();
    }
    return list;
  }

  Set<String> get _allCorporations =>
      _store.timesheets.map((t) => t.corporationName).toSet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NpupsColors.surface,
      appBar: AppBar(
        backgroundColor: NpupsColors.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PS Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Welcome, ${widget.user.fullName}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Pipeline'),
            Tab(text: 'Drill Down'),
            Tab(text: 'Bottlenecks'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filters',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildPipelineTab(),
              _buildDrillDownTab(),
              _buildBottleneckTab(),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1: PIPELINE OVERVIEW
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPipelineTab() {
    final counts = <TimesheetStage, int>{};
    final filtered = _filteredTimesheets;
    for (final stage in TimesheetStage.values) {
      counts[stage] = filtered.where((t) => t.stage == stage).length;
    }
    final totalPayroll = filtered.fold<double>(0, (s, t) => s + t.grandTotal);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Active filter indicator
        if (_filterCorporation != null || _filterStage != null || _showStalledOnly)
          _buildActiveFilters(),

        // KPI Summary Row
        _buildKpiRow(filtered, totalPayroll),
        const SizedBox(height: 16),

        // Pipeline Flow (Horizontal)
        const Text('Pipeline Flow', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NpupsColors.textPrimary)),
        const SizedBox(height: 12),
        _buildPipelineFlow(counts),
        const SizedBox(height: 20),

        // Stage Breakdown Cards
        const Text('Stage Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NpupsColors.textPrimary)),
        const SizedBox(height: 12),
        ...TimesheetStage.values.map((stage) => _buildStageCard(stage, counts[stage] ?? 0, filtered)),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NpupsColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NpupsColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 16, color: NpupsColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                if (_filterCorporation != null) _filterChip(_filterCorporation!, () => setState(() => _filterCorporation = null)),
                if (_filterStage != null) _filterChip(_filterStage!.displayName, () => setState(() => _filterStage = null)),
                if (_showStalledOnly) _filterChip('Stalled Only', () => setState(() => _showStalledOnly = false)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() { _filterCorporation = null; _filterStage = null; _showStalledOnly = false; }),
            child: const Text('Clear All', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onRemove,
      backgroundColor: NpupsColors.accent.withValues(alpha: 0.1),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildKpiRow(List<Timesheet> timesheets, double totalPayroll) {
    final stalled = timesheets.where((t) =>
        t.isStalled(_stalledThreshold) &&
        t.stage != TimesheetStage.notStarted &&
        t.stage != TimesheetStage.chequePrinting).length;

    return Row(
      children: [
        _kpiCard('Total', '${timesheets.length}', Icons.assignment, NpupsColors.accent),
        const SizedBox(width: 8),
        _kpiCard('Payroll', '\$${(totalPayroll / 1000).toStringAsFixed(1)}K', Icons.payments, NpupsColors.success),
        const SizedBox(width: 8),
        _kpiCard('Stalled', '$stalled', Icons.warning_amber, stalled > 0 ? NpupsColors.error : NpupsColors.success),
        const SizedBox(width: 8),
        _kpiCard('Complete', '${timesheets.where((t) => t.stage == TimesheetStage.chequePrinting).length}', Icons.done_all, NpupsColors.success),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineFlow(Map<TimesheetStage, int> counts) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: TimesheetStage.values.asMap().entries.map((entry) {
            final stage = entry.value;
            final count = counts[stage] ?? 0;
            final isLast = entry.key == TimesheetStage.values.length - 1;

            return Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _filterStage = _filterStage == stage ? null : stage;
                  }),
                  child: Container(
                    width: 80,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    decoration: BoxDecoration(
                      color: _filterStage == stage ? stage.color : stage.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: count > 0 ? Border.all(color: stage.color, width: 1.5) : null,
                    ),
                    child: Column(
                      children: [
                        Icon(stage.icon, size: 18, color: _filterStage == stage ? Colors.white : stage.color),
                        const SizedBox(height: 4),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _filterStage == stage ? Colors.white : stage.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stage.displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: _filterStage == stage ? Colors.white70 : stage.color,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.arrow_forward_ios, size: 12, color: NpupsColors.border),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStageCard(TimesheetStage stage, int count, List<Timesheet> allTimesheets) {
    final stageTimesheets = allTimesheets.where((t) => t.stage == stage).toList();
    if (count == 0) return const SizedBox();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: stage.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: stage.color)),
          ),
        ),
        title: Text(stage.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('\$${stageTimesheets.fold<double>(0, (s, t) => s + t.grandTotal).toStringAsFixed(0)} total',
            style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
        children: stageTimesheets.map((ts) => ListTile(
          dense: true,
          title: Text(ts.workerName, style: const TextStyle(fontSize: 13)),
          subtitle: Text('${ts.corporationName} | ${ts.position}', style: const TextStyle(fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${ts.grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (ts.isStalled(_stalledThreshold) && stage != TimesheetStage.notStarted && stage != TimesheetStage.chequePrinting)
                Text('${ts.timeAtCurrentStage.inHours}h stalled', style: const TextStyle(fontSize: 10, color: NpupsColors.error)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2: DRILL DOWN
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDrillDownTab() {
    final byCorpMap = <String, List<Timesheet>>{};
    for (final ts in _filteredTimesheets) {
      byCorpMap.putIfAbsent(ts.corporationName, () => []).add(ts);
    }

    if (byCorpMap.isEmpty) {
      return const Center(child: Text('No data matching filters', style: TextStyle(color: NpupsColors.textSecondary)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_filterCorporation != null || _filterStage != null || _showStalledOnly)
          _buildActiveFilters(),
        ...byCorpMap.entries.map((entry) => _buildCorporationSection(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildCorporationSection(String corpName, List<Timesheet> timesheets) {
    // Group by stage within this corporation
    final stageCounts = <TimesheetStage, int>{};
    for (final ts in timesheets) {
      stageCounts[ts.stage] = (stageCounts[ts.stage] ?? 0) + 1;
    }
    final totalPay = timesheets.fold<double>(0, (s, t) => s + t.grandTotal);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(corpName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('${timesheets.length} workers | \$${totalPay.toStringAsFixed(0)} total',
            style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
        leading: CircleAvatar(
          backgroundColor: NpupsColors.accent.withValues(alpha: 0.1),
          child: Text('${timesheets.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: NpupsColors.accent)),
        ),
        children: [
          // Mini pipeline for this corporation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: stageCounts.entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: e.key.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${e.key.displayName}: ${e.value}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: e.key.color)),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // Individual workers
          ...timesheets.map((ts) => ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: ts.stage.color.withValues(alpha: 0.12),
              child: Icon(ts.stage.icon, size: 14, color: ts.stage.color),
            ),
            title: Text(ts.workerName, style: const TextStyle(fontSize: 13)),
            subtitle: Text('${ts.position} | ${ts.stage.displayName}', style: const TextStyle(fontSize: 11)),
            trailing: Text('\$${ts.grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _showTimesheetDetail(ts),
          )),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3: BOTTLENECK DETECTION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBottleneckTab() {
    final stalled = _store.timesheets.where((t) =>
        t.isStalled(_stalledThreshold) &&
        t.stage != TimesheetStage.notStarted &&
        t.stage != TimesheetStage.chequePrinting).toList();

    // Group by stage to identify which stages are bottlenecks
    final bottlenecksByStage = <TimesheetStage, List<Timesheet>>{};
    for (final ts in stalled) {
      bottlenecksByStage.putIfAbsent(ts.stage, () => []).add(ts);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Threshold config
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.timer, color: NpupsColors.warning),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stalled Threshold', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Timesheets stuck longer than this are flagged', style: TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                    ],
                  ),
                ),
                DropdownButton<int>(
                  value: _stalledThreshold.inHours,
                  items: [24, 48, 72, 96].map((h) =>
                    DropdownMenuItem(value: h, child: Text('${h}h')),
                  ).toList(),
                  onChanged: (v) => setState(() => _stalledThreshold = Duration(hours: v ?? 48)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Summary
        if (stalled.isEmpty)
          _buildNoBottlenecks()
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NpupsColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NpupsColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: NpupsColors.error, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${stalled.length} Stalled Timesheet${stalled.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NpupsColors.error)),
                      Text('Exceeding ${_stalledThreshold.inHours}h threshold',
                          style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bottleneck by stage
          ...bottlenecksByStage.entries.map((entry) {
            final stage = entry.key;
            final items = entry.value;
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: NpupsColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: stage.color.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(stage.icon, size: 20, color: stage.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(stage.displayName, style: TextStyle(fontWeight: FontWeight.bold, color: stage.color)),
                              Text('${items.length} stalled | Responsible: ${items.first.stageOwner}',
                                  style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: NpupsColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('BOTTLENECK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: NpupsColors.error)),
                        ),
                      ],
                    ),
                  ),
                  ...items.map((ts) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule, size: 18, color: NpupsColors.error),
                    title: Text(ts.workerName, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${ts.corporationName} | Waiting ${ts.timeAtCurrentStage.inHours}h',
                        style: const TextStyle(fontSize: 11, color: NpupsColors.error)),
                    trailing: Text('\$${ts.grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => _showTimesheetDetail(ts),
                  )),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildNoBottlenecks() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: NpupsColors.success),
          const SizedBox(height: 16),
          const Text('No Bottlenecks Detected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NpupsColors.success)),
          const SizedBox(height: 8),
          Text('All timesheets are flowing within the ${_stalledThreshold.inHours}h threshold.',
              style: const TextStyle(color: NpupsColors.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter Timesheets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // Corporation filter
              const Text('Corporation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filterCorporation == null,
                    onSelected: (_) {
                      setSheetState(() => _filterCorporation = null);
                      setState(() {});
                    },
                  ),
                  ..._allCorporations.map((corp) => ChoiceChip(
                    label: Text(corp.split(' ').first, style: const TextStyle(fontSize: 12)),
                    selected: _filterCorporation == corp,
                    onSelected: (_) {
                      setSheetState(() => _filterCorporation = _filterCorporation == corp ? null : corp);
                      setState(() {});
                    },
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // Stage filter
              const Text('Stage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filterStage == null,
                    onSelected: (_) {
                      setSheetState(() => _filterStage = null);
                      setState(() {});
                    },
                  ),
                  ...TimesheetStage.values.map((stage) => ChoiceChip(
                    label: Text(stage.displayName, style: const TextStyle(fontSize: 11)),
                    selected: _filterStage == stage,
                    onSelected: (_) {
                      setSheetState(() => _filterStage = _filterStage == stage ? null : stage);
                      setState(() {});
                    },
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // Stalled only toggle
              SwitchListTile(
                title: const Text('Show stalled only', style: TextStyle(fontSize: 14)),
                subtitle: Text('Timesheets waiting > ${_stalledThreshold.inHours}h', style: const TextStyle(fontSize: 12)),
                value: _showStalledOnly,
                onChanged: (v) {
                  setSheetState(() => _showStalledOnly = v);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Apply Filters'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimesheetDetail(Timesheet ts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: NpupsColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            // Worker info
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: ts.stage.color.withValues(alpha: 0.12),
                  child: Icon(ts.stage.icon, color: ts.stage.color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ts.workerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${ts.position} | ${ts.corporationName}', style: const TextStyle(color: NpupsColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Current stage
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ts.stage.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(ts.stage.icon, color: ts.stage.color, size: 18),
                  const SizedBox(width: 8),
                  Text(ts.stage.displayName, style: TextStyle(fontWeight: FontWeight.bold, color: ts.stage.color)),
                  const Spacer(),
                  Text('${ts.timeAtCurrentStage.inHours}h at this stage',
                      style: TextStyle(fontSize: 12, color: ts.isStalled(_stalledThreshold) ? NpupsColors.error : NpupsColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details
            _detailRow('ID', ts.id),
            _detailRow('NIS', ts.nisNumber),
            _detailRow('ID Number', ts.idNumber),
            _detailRow('District', ts.electoralDistrict),
            _detailRow('Group', ts.groupNumber),
            _detailRow('Fortnight', '${DateFormat('dd/MM/yyyy').format(ts.fortnightStart)} - ${DateFormat('dd/MM/yyyy').format(ts.fortnightEnd)}'),
            _detailRow('Days Worked', '${ts.daysWorked}'),
            _detailRow('Wage', '\$${ts.wageTotal.toStringAsFixed(2)}'),
            _detailRow('COLA', '\$${ts.colaTotal.toStringAsFixed(2)}'),
            _detailRow('Allowance', '\$${ts.allowanceTotal.toStringAsFixed(2)}'),
            _detailRow('Grand Total', '\$${ts.grandTotal.toStringAsFixed(2)}'),
            _detailRow('Bank', '${ts.bankName} - ${ts.accountNumber}'),
            _detailRow('Branch', ts.branchName),
            _detailRow('Current Owner', ts.stageOwner),
            const SizedBox(height: 16),

            // Approval history
            const Text('Approval History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (ts.approvalHistory.isEmpty)
              const Text('No approvals yet', style: TextStyle(color: NpupsColors.textSecondary))
            else
              ...ts.approvalHistory.map((record) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      record.state == ApprovalState.approved ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: record.state == ApprovalState.approved ? NpupsColors.success : NpupsColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${record.reviewerName} (${record.reviewerRole})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          if (record.note != null) Text(record.note!, style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
                          Text(DateFormat('dd/MM/yyyy HH:mm').format(record.timestamp), style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
