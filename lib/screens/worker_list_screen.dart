import 'package:flutter/material.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import 'worker_detail_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Admin Worker List View
// Browse all registered workers, search/filter, view document status at a glance.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerListScreen extends StatefulWidget {
  const WorkerListScreen({super.key});

  @override
  State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  final WorkerDataStore _store = WorkerDataStore();
  final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'All';
  String _filterCorp = 'All';

  List<Worker> get _filteredWorkers {
    var list = _store.workers;

    // Search
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((w) =>
          w.fullName.toLowerCase().contains(query) ||
          w.nisNumber.toLowerCase().contains(query) ||
          w.idNumber.toLowerCase().contains(query)).toList();
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
        final workers = _filteredWorkers;
        return Scaffold(
          backgroundColor: NpupsColors.surface,
          appBar: AppBar(
            backgroundColor: NpupsColors.primary,
            title: const Text('Worker Registry', style: TextStyle(fontWeight: FontWeight.w700)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by name, NIS, or ID...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.7)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
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
                            _buildFilterChip('All', _filterStatus, (v) => setState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Verified', _filterStatus, (v) => setState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Partial', _filterStatus, (v) => setState(() => _filterStatus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Missing', _filterStatus, (v) => setState(() => _filterStatus = v)),
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
                                  items: _corporations.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                                  onChanged: (v) => setState(() => _filterCorp = v ?? 'All'),
                                ),
                              ),
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
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
    final statusColor = worker.isFullyVerified
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
                    Text(worker.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: NpupsColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text('${worker.position}  •  ${worker.nisNumber}', style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                    const SizedBox(height: 3),
                    Text(worker.corporationName, style: const TextStyle(fontSize: 11, color: NpupsColors.accent)),
                  ],
                ),
              ),

              // Status badge
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
                      worker.verificationLabel,
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
                  const SizedBox(height: 4),
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
