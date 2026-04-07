import 'package:flutter/material.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../models/user_model.dart';
import '../services/worker_data_store.dart';
import '../services/security_utils.dart';
import 'worker_detail_screen.dart';
import 'worker_registration_form.dart';
import 'worker_replacement_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Worker Registry Screen
// Browse all registered workers, search/filter, view document status at a glance.
// Admins can register new workers; any authorised user can view replacement records.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerListScreen extends StatefulWidget {
  final NpupsUser? currentUser;

  const WorkerListScreen({super.key, this.currentUser});

  @override
  State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  final WorkerDataStore _store = WorkerDataStore();
  final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'All';
  String _filterCorp = 'All';
  bool _showInactive = false;

  // Cached filtered list — invalidated on setState
  List<Worker>? _cachedFiltered;

  bool get _isAdmin => widget.currentUser?.role == UserRole.systemAdmin;
  bool get _isMinistersDept => widget.currentUser?.role == UserRole.ministersDepartment;
  bool get _canEdit => _isAdmin || _isMinistersDept;

  List<Worker> get _filteredWorkers {
    return _cachedFiltered ??= _computeFilteredWorkers();
  }

  List<Worker> _computeFilteredWorkers() {
    var list = _store.workers.toList();

    // Active/inactive filter
    if (!_showInactive) {
      list = list.where((w) => w.isActive).toList();
    }

    // Search
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((w) =>
          w.fullName.toLowerCase().contains(query) ||
          w.nisNumber.toLowerCase().contains(query) ||
          w.idNumber.toLowerCase().contains(query) ||
          w.position.toLowerCase().contains(query)).toList();
    }

    // Filter by doc status
    if (_filterStatus == 'Verified') {
      list = list.where((w) => w.isFullyVerified).toList();
    } else if (_filterStatus == 'Partial') {
      list = list.where((w) => w.documentsUploaded > 0 && !w.isFullyVerified).toList();
    } else if (_filterStatus == 'Missing') {
      list = list.where((w) => w.documentsUploaded == 0).toList();
    }

    // Filter by corporation
    if (_filterCorp != 'All') {
      list = list.where((w) => w.corporationName == _filterCorp).toList();
    }

    return list;
  }

  List<String> get _corporations {
    final corps = _store.workers.map((w) => w.corporationName).toSet().toList();
    corps.sort();
    return ['All', ...corps];
  }

  void _invalidateAndSetState(VoidCallback fn) {
    setState(() {
      _cachedFiltered = null;
      fn();
    });
  }

  void _openRegistrationForm({Worker? existing}) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WorkerRegistrationForm(existingWorker: existing),
    ));
    if (result == true) {
      _invalidateAndSetState(() {});
    }
  }

  void _openReplacement(Worker worker) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkerReplacementScreen(originalWorkerId: worker.id),
    ));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        _cachedFiltered = null; // Invalidate on store change
        final workers = _filteredWorkers;
        return Scaffold(
          backgroundColor: NpupsColors.surface,
          appBar: AppBar(
            backgroundColor: NpupsColors.primary,
            title: const Text('Worker Registry', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.person_add),
                  tooltip: 'Register New Worker',
                  onPressed: () => _openRegistrationForm(),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _invalidateAndSetState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by name, NIS, ID, or position...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.7)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              _invalidateAndSetState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
          floatingActionButton: _isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _openRegistrationForm(),
                  backgroundColor: NpupsColors.accent,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Register Worker'),
                )
              : null,
          body: Column(
            children: [
              // Filter chips
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', _filterStatus, (v) => _invalidateAndSetState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Verified', _filterStatus, (v) => _invalidateAndSetState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Partial', _filterStatus, (v) => _invalidateAndSetState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Missing', _filterStatus, (v) => _invalidateAndSetState(() => _filterStatus = v)),
                            const SizedBox(width: 16),
                            // Corporation dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: NpupsColors.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _filterCorp,
                                  isDense: true,
                                  style: const TextStyle(fontSize: 13, color: NpupsColors.textPrimary),
                                  items: _corporations.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                                  onChanged: (v) => _invalidateAndSetState(() => _filterCorp = v ?? 'All'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Show inactive toggle
                            FilterChip(
                              label: const Text('Show Inactive', style: TextStyle(fontSize: 12)),
                              selected: _showInactive,
                              onSelected: (v) => _invalidateAndSetState(() => _showInactive = v),
                              selectedColor: NpupsColors.error.withValues(alpha: 0.15),
                              checkmarkColor: NpupsColors.error,
                              labelStyle: TextStyle(color: _showInactive ? NpupsColors.error : NpupsColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Summary bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NpupsColors.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummary('Total', '${workers.length}', NpupsColors.accent),
                    _buildSummary('Verified', '${workers.where((w) => w.isFullyVerified).length}', NpupsColors.success),
                    _buildSummary('Partial', '${workers.where((w) => w.documentsUploaded > 0 && !w.isFullyVerified).length}', NpupsColors.warning),
                    _buildSummary('Missing', '${workers.where((w) => w.documentsUploaded == 0).length}', NpupsColors.error),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Worker list
              Expanded(
                child: workers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 48, color: NpupsColors.textHint),
                            const SizedBox(height: 12),
                            const Text('No workers match your filters', style: TextStyle(color: NpupsColors.textSecondary)),
                            if (_isAdmin) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _openRegistrationForm(),
                                icon: const Icon(Icons.person_add, size: 16),
                                label: const Text('Register First Worker'),
                                style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.accent),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: workers.length,
                        itemBuilder: (context, index) => _buildWorkerCard(workers[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String current, ValueChanged<String> onSelect) {
    final isSelected = label == current;
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? NpupsColors.accent : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? NpupsColors.accent : NpupsColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : NpupsColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
      ],
    );
  }

  Widget _buildWorkerCard(Worker worker) {
    final isReplaced = _store.getReplacementFor(worker.id) != null;
    final statusColor = !worker.isActive
        ? NpupsColors.error
        : worker.isFullyVerified
            ? NpupsColors.success
            : worker.documentsUploaded > 0
                ? NpupsColors.warning
                : NpupsColors.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkerDetailScreen(workerId: worker.id),
          ));
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Text(
                  worker.initials,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(worker.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: NpupsColors.textPrimary)),
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
                    const SizedBox(height: 3),
                    Text('${worker.position}  •  ${SecurityUtils.maskNisNumber(worker.nisNumber)}', style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                    const SizedBox(height: 3),
                    Text(worker.corporationName, style: const TextStyle(fontSize: 11, color: NpupsColors.accent)),
                    if (worker.contact != null) ...[
                      const SizedBox(height: 2),
                      Text(worker.contact!, style: const TextStyle(fontSize: 11, color: NpupsColors.textHint)),
                    ],
                  ],
                ),
              ),

              // Right side actions + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      worker.isActive ? worker.verificationLabel : 'Inactive',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Mini progress bar
                  SizedBox(
                    width: 60,
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: worker.verificationPercent,
                        backgroundColor: NpupsColors.border,
                        valueColor: AlwaysStoppedAnimation(statusColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Action menu
                  if (_canEdit || isReplaced)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: NpupsColors.textHint),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
                      onSelected: (action) {
                        if (action == 'edit') _openRegistrationForm(existing: worker);
                        if (action == 'replacement') _openReplacement(worker);
                      },
                      itemBuilder: (_) => [
                        if (_canEdit)
                          const PopupMenuItem(value: 'edit', child: Row(children: [
                            Icon(Icons.edit, size: 15, color: NpupsColors.accent),
                            SizedBox(width: 8),
                            Text('Edit Worker', style: TextStyle(fontSize: 13)),
                          ])),
                        if (isReplaced)
                          const PopupMenuItem(value: 'replacement', child: Row(children: [
                            Icon(Icons.swap_horiz, size: 15, color: NpupsColors.warning),
                            SizedBox(width: 8),
                            Text('View Replacement', style: TextStyle(fontSize: 13)),
                          ])),
                      ],
                    )
                  else
                    Icon(Icons.chevron_right, size: 18, color: NpupsColors.textHint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
