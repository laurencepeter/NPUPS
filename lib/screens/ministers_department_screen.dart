import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../models/user_model.dart';
import '../services/worker_data_store.dart';
import '../services/security_utils.dart';
import 'worker_registration_form.dart';
import 'worker_replacement_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Minister's Department Screen
// Provides the Minister's Department with full read/edit access to the worker
// registry. Workers can be filtered by corporation and exported as a summary.
// ──────────────────────────────────────────────────────────────────────────────

class MinistersDepartmentScreen extends StatefulWidget {
  final NpupsUser user;

  const MinistersDepartmentScreen({super.key, required this.user});

  @override
  State<MinistersDepartmentScreen> createState() => _MinistersDepartmentScreenState();
}

class _MinistersDepartmentScreenState extends State<MinistersDepartmentScreen>
    with SingleTickerProviderStateMixin {
  final WorkerDataStore _store = WorkerDataStore();
  late TabController _tabController;

  String _filterCorp = 'All';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Filter: Active only or all
  bool _showActiveOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _corporations {
    final corps = _store.workers.map((w) => w.corporationName).toSet().toList();
    corps.sort();
    return ['All', ...corps];
  }

  List<Worker> get _filteredWorkers {
    var list = _store.workers.toList();

    if (_showActiveOnly) list = list.where((w) => w.isActive).toList();

    if (_filterCorp != 'All') {
      list = list.where((w) => w.corporationName == _filterCorp).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((w) =>
          w.fullName.toLowerCase().contains(q) ||
          w.position.toLowerCase().contains(q) ||
          w.nisNumber.toLowerCase().contains(q) ||
          w.idNumber.toLowerCase().contains(q)).toList();
    }

    return list;
  }

  List<Worker> get _replacedWorkers {
    var list = _store.getReplacedWorkers();
    if (_filterCorp != 'All') {
      list = list.where((w) => w.corporationName == _filterCorp).toList();
    }
    return list;
  }

  void _openEdit(Worker worker) async {
    final updated = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkerRegistrationForm(existingWorker: worker),
    ));
    if (updated == true) setState(() {});
  }

  void _openReplacement(Worker worker) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerReplacementScreen(originalWorkerId: worker.id),
    ));
  }

  void _exportByCorporation() {
    final corp = _filterCorp == 'All' ? 'All Corporations' : _filterCorp;
    final workers = _filteredWorkers;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.download, color: NpupsColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('Export: $corp', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${workers.length} workers will be included in the export.', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NpupsColors.inputFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export will include:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.textSecondary)),
                  const SizedBox(height: 6),
                  ...[
                    'Full Name', 'Position', 'NIS Number', 'ID Number', 'BIR Number',
                    'Contact', 'Address', 'Corporation', 'Electoral District',
                    'Start Date', 'End Date', 'EmployTT Reference', 'Active Status',
                  ].map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(children: [
                      const Icon(Icons.check, size: 12, color: NpupsColors.success),
                      const SizedBox(width: 6),
                      Text(f, style: const TextStyle(fontSize: 12, color: NpupsColors.textPrimary)),
                    ]),
                  )),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exported ${workers.length} worker records for $corp'),
                  backgroundColor: NpupsColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export'),
            style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.accent),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: NpupsColors.surface,
          appBar: AppBar(
            backgroundColor: NpupsColors.primary,
            title: const Text("Minister's Department", style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                onPressed: _exportByCorporation,
                icon: const Icon(Icons.download),
                tooltip: 'Export by Corporation',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: NpupsColors.accent,
              tabs: [
                Tab(text: 'Workers (${_filteredWorkers.length})', icon: const Icon(Icons.people, size: 18)),
                Tab(text: 'Replacements (${_replacedWorkers.length})', icon: const Icon(Icons.swap_horiz, size: 18)),
              ],
            ),
          ),
          body: Column(
            children: [
              // Filter bar
              _buildFilterBar(),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildWorkerList(),
                    _buildReplacementList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by name, NIS, ID, or position...',
              prefixIcon: const Icon(Icons.search, size: 20, color: NpupsColors.textHint),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: NpupsColors.inputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          // Corporation filter + active toggle
          Row(
            children: [
              // Corporation dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: NpupsColors.inputFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterCorp,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: NpupsColors.textPrimary),
                      items: _corporations.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) => setState(() => _filterCorp = v ?? 'All'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Active only toggle
              FilterChip(
                label: const Text('Active only', style: TextStyle(fontSize: 12)),
                selected: _showActiveOnly,
                onSelected: (v) => setState(() => _showActiveOnly = v),
                selectedColor: NpupsColors.accent.withValues(alpha: 0.15),
                checkmarkColor: NpupsColors.accent,
                labelStyle: TextStyle(color: _showActiveOnly ? NpupsColors.accent : NpupsColors.textSecondary),
              ),
              const SizedBox(width: 8),
              // Export button
              IconButton(
                onPressed: _exportByCorporation,
                icon: const Icon(Icons.download, color: NpupsColors.accent, size: 22),
                tooltip: 'Export',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerList() {
    final workers = _filteredWorkers;

    if (workers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: NpupsColors.textHint),
            const SizedBox(height: 12),
            const Text('No workers match your filters.', style: TextStyle(color: NpupsColors.textSecondary)),
          ],
        ),
      );
    }

    // Group by corporation
    final grouped = <String, List<Worker>>{};
    for (final w in workers) {
      grouped.putIfAbsent(w.corporationName, () => []).add(w);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Summary stats
        _buildSummaryBar(workers),
        const SizedBox(height: 12),

        for (final corpEntry in grouped.entries) ...[
          _corpHeader(corpEntry.key, corpEntry.value.length),
          const SizedBox(height: 6),
          ...corpEntry.value.map((w) => _buildWorkerTile(w)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildReplacementList() {
    final replaced = _replacedWorkers;

    if (replaced.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: NpupsColors.textHint),
            const SizedBox(height: 12),
            const Text('No replacement records found.', style: TextStyle(color: NpupsColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: replaced.length,
      itemBuilder: (context, index) {
        final original = replaced[index];
        final repRecord = _store.getReplacementFor(original.id);
        final replacement = repRecord != null ? _store.getById(repRecord.replacementWorkerId) : null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 1,
          child: InkWell(
            onTap: () => _openReplacement(original),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz, color: NpupsColors.warning, size: 20),
                      const SizedBox(width: 8),
                      const Text('Replacement', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.warning)),
                      const Spacer(),
                      if (repRecord != null)
                        Text(
                          DateFormat('d MMM yyyy').format(repRecord.replacedAt),
                          style: const TextStyle(fontSize: 11, color: NpupsColors.textHint),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _miniWorkerChip(original, isOriginal: true, daysMissed: repRecord?.daysMissed)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 18, color: NpupsColors.textHint),
                      ),
                      Expanded(child: replacement != null
                          ? _miniWorkerChip(replacement, isOriginal: false)
                          : _noReplacementChip()),
                    ],
                  ),
                  if (repRecord != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Reason: ${repRecord.reason}',
                      style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openReplacement(original),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('View Full Record', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: NpupsColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniWorkerChip(Worker worker, {required bool isOriginal, int? daysMissed}) {
    final color = isOriginal ? NpupsColors.error : NpupsColors.success;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOriginal ? 'Original' : 'Replacement',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 3),
          Text(worker.fullName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.textPrimary)),
          Text(worker.position, style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
          if (isOriginal && daysMissed != null) ...[
            const SizedBox(height: 3),
            Text('$daysMissed days missed', style: const TextStyle(fontSize: 10, color: NpupsColors.error, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }

  Widget _noReplacementChip() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NpupsColors.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NpupsColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Replacement', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: NpupsColors.textHint)),
          SizedBox(height: 3),
          Text('Not assigned', style: TextStyle(fontSize: 12, color: NpupsColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(List<Worker> workers) {
    final active = workers.where((w) => w.isActive).length;
    final inactive = workers.length - active;
    final verified = workers.where((w) => w.isFullyVerified).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NpupsColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Total', '${workers.length}', NpupsColors.accent),
          _stat('Active', '$active', NpupsColors.success),
          _stat('Inactive', '$inactive', NpupsColors.error),
          _stat('Verified', '$verified', NpupsColors.warning),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: NpupsColors.textSecondary)),
      ],
    );
  }

  Widget _corpHeader(String name, int count) {
    return Row(
      children: [
        const Icon(Icons.location_city, size: 14, color: NpupsColors.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$name  ($count)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NpupsColors.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkerTile(Worker worker) {
    final isReplaced = _store.getReplacementFor(worker.id) != null;
    final statusColor = !worker.isActive
        ? NpupsColors.error
        : worker.isFullyVerified
            ? NpupsColors.success
            : NpupsColors.warning;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Text(worker.initials, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(worker.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (isReplaced)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: NpupsColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Replaced', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: NpupsColors.warning)),
              ),
            if (!worker.isActive)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: NpupsColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Inactive', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: NpupsColors.error)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${worker.position}  •  ${SecurityUtils.maskNisNumber(worker.nisNumber)}',
              style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary),
            ),
            if (worker.contact != null)
              Text(worker.contact!, style: const TextStyle(fontSize: 11, color: NpupsColors.textHint)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20, color: NpupsColors.textSecondary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (action) {
            if (action == 'edit') _openEdit(worker);
            if (action == 'replacement') _openReplacement(worker);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Row(children: [
              Icon(Icons.edit, size: 16, color: NpupsColors.accent),
              SizedBox(width: 10),
              Text('Edit Worker'),
            ])),
            if (isReplaced)
              const PopupMenuItem(value: 'replacement', child: Row(children: [
                Icon(Icons.swap_horiz, size: 16, color: NpupsColors.warning),
                SizedBox(width: 10),
                Text('View Replacement'),
              ])),
          ],
        ),
      ),
    );
  }
}
