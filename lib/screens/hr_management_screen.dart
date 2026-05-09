// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Comprehensive HR dashboard for:
//  - Document vetting (approve / reject / request re-upload per document)
//  - Worker status management (active / inactive / on-leave / terminated)
//  - HR notes attached to worker records
//  - Employment action log (full history)
// Accessible by HR, System Admin, PS (read-only for PS and Executive Dept)
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/audit_service.dart';
import '../models/audit_model.dart';
import '../theme/app_theme.dart';

class HrManagementScreen extends StatefulWidget {
  final AppUser currentUser;

  const HrManagementScreen({super.key, required this.currentUser});

  @override
  State<HrManagementScreen> createState() => _HrManagementScreenState();
}

class _HrManagementScreenState extends State<HrManagementScreen>
    with SingleTickerProviderStateMixin {
  final WorkerDataStore _workerStore = WorkerDataStore();
  final AuditService _auditService = AuditService();

  late TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _statusFilter = 'All';
  Worker? _selectedWorker;

  bool get _canEdit =>
      widget.currentUser.role == UserRole.hr ||
      widget.currentUser.role == UserRole.systemAdmin ||
      widget.currentUser.role == UserRole.dmcr;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Worker> get _filteredWorkers {
    var workers = _canEdit
        ? _workerStore.workers.toList()
        : _workerStore
            .getByCorpId(widget.currentUser.corporationId ?? '')
            .toList();

    if (_statusFilter == 'Active') workers = workers.where((w) => w.isActive).toList();
    if (_statusFilter == 'Inactive') workers = workers.where((w) => !w.isActive).toList();
    if (_statusFilter == 'Pending Docs') {
      workers = workers.where((w) => !w.isFullyVerified).toList();
    }

    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      workers = workers
          .where((w) =>
              w.fullName.toLowerCase().contains(q) ||
              w.nisNumber.toLowerCase().contains(q) ||
              w.idNumber.toLowerCase().contains(q) ||
              w.position.toLowerCase().contains(q))
          .toList();
    }

    workers.sort((a, b) => a.fullName.compareTo(b.fullName));
    return workers;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _workerStore,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('HR Management'),
            bottom: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: AppColors.accentLight,
              tabs: const [
                Tab(text: 'Workers & Documents'),
                Tab(text: 'Document Queue'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildWorkersTab(isDark),
              _buildDocumentQueueTab(isDark),
            ],
          ),
        );
      },
    );
  }

  // ── Workers tab ─────────────────────────────────────────────────────────────

  Widget _buildWorkersTab(bool isDark) {
    final workers = _filteredWorkers;

    return Row(
      children: [
        // Worker list panel
        SizedBox(
          width: 300,
          child: Column(
            children: [
              _buildSearchBar(isDark),
              _buildStatusFilters(isDark),
              Expanded(
                child: ListView.separated(
                  itemCount: workers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.border,
                  ),
                  itemBuilder: (_, i) =>
                      _buildWorkerListTile(workers[i], isDark),
                ),
              ),
            ],
          ),
        ),

        // Vertical divider
        VerticalDivider(
          width: 1,
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),

        // Detail panel
        Expanded(
          child: _selectedWorker == null
              ? _buildEmptyDetail(isDark)
              : _buildWorkerDetail(_selectedWorker!, isDark),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      color: isDark ? AppColors.darkCard : AppColors.card,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search workers…',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                  },
                )
              : null,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildStatusFilters(bool isDark) {
    final filters = ['All', 'Active', 'Inactive', 'Pending Docs'];
    return Container(
      height: 40,
      color: isDark ? AppColors.darkBackground : AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final f = filters[i];
          final active = _statusFilter == f;
          return Center(
            child: FilterChip(
              label: Text(f, style: const TextStyle(fontSize: 11)),
              selected: active,
              onSelected: (_) => setState(() => _statusFilter = f),
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkerListTile(Worker worker, bool isDark) {
    final isSelected = _selectedWorker?.id == worker.id;
    final docPct = worker.verificationPercent;

    return InkWell(
      onTap: () => setState(() => _selectedWorker = worker),
      child: Container(
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: worker.isActive
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              child: Text(
                worker.initials,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: worker.isActive
                      ? AppColors.accent
                      : AppColors.error,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.fullName,
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
                    worker.position,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextHint
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _docBadge(worker),
                const SizedBox(height: 2),
                SizedBox(
                  width: 50,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: docPct,
                      backgroundColor: isDark
                          ? AppColors.darkBorder
                          : AppColors.border,
                      color: docPct == 1.0
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _docBadge(Worker worker) {
    if (worker.isFullyVerified) {
      return const Icon(Icons.verified, size: 14, color: AppColors.success);
    }
    return Text(
      '${worker.documentsUploaded}/${worker.totalDocuments}',
      style: const TextStyle(fontSize: 10, color: AppColors.warning),
    );
  }

  Widget _buildEmptyDetail(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search_outlined,
              size: 48,
              color: isDark
                  ? AppColors.darkTextHint
                  : AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'Select a worker to view their HR record',
            style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerDetail(Worker worker, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Worker header card
          _buildWorkerHeader(worker, isDark),
          const SizedBox(height: 16),

          // Employment info
          _buildSection(
            'Employment Details',
            Icons.work_outline,
            isDark,
            [
              _infoRow2('Position', worker.position, isDark),
              _infoRow2('Corporation', worker.corporationName, isDark),
              _infoRow2('Electoral District', worker.electoralDistrict, isDark),
              _infoRow2('Start Date', _fmtDate(worker.startDate), isDark),
              if (worker.endDate != null)
                _infoRow2('End Date', _fmtDate(worker.endDate), isDark),
              _infoRow2('Reference No.', worker.referenceNumber ?? '—', isDark),
            ],
          ),
          const SizedBox(height: 12),

          // Documents section
          _buildDocumentsSection(worker, isDark),
          const SizedBox(height: 12),

          // Status actions
          if (_canEdit) _buildStatusActions(worker, isDark),
          const SizedBox(height: 12),

          // HR Notes
          if (_canEdit) _buildNotesSection(worker, isDark),

          // Audit trail for this worker
          const SizedBox(height: 12),
          _buildWorkerAuditTrail(worker, isDark),
        ],
      ),
    );
  }

  Widget _buildWorkerHeader(Worker worker, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: worker.isActive
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              child: Text(
                worker.initials,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: worker.isActive
                      ? AppColors.accent
                      : AppColors.error,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.fullName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(worker.id,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextHint
                              : AppColors.textHint)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusPill(worker.isActive ? 'Active' : 'Inactive',
                          worker.isActive ? AppColors.success : AppColors.error),
                      const SizedBox(width: 6),
                      _statusPill(
                          worker.verificationLabel,
                          worker.isFullyVerified
                              ? AppColors.success
                              : AppColors.warning),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildSection(String title, IconData icon, bool isDark,
      List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)),
            ]),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow2(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextHint
                        : AppColors.textHint)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection(Worker worker, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  'Documents',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary),
                ),
                const Spacer(),
                Text(
                  worker.verificationLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: worker.isFullyVerified
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...worker.documents.entries
                .map((e) => _buildDocumentRow(worker, e.key, e.value, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentRow(
      Worker worker, String docName, WorkerDocument doc, bool isDark) {
    final statusColor = switch (doc.status) {
      DocumentStatus.uploaded => AppColors.success,
      DocumentStatus.missing => AppColors.error,
      DocumentStatus.pending => AppColors.warning,
    };
    final statusIcon = switch (doc.status) {
      DocumentStatus.uploaded => Icons.check_circle,
      DocumentStatus.missing => Icons.cancel_outlined,
      DocumentStatus.pending => Icons.hourglass_empty,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(docName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    )),
                if (doc.fileName != null)
                  Text(doc.fileName!,
                      style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkTextHint
                              : AppColors.textHint)),
              ],
            ),
          ),
          if (_canEdit) ...[
            if (doc.status == DocumentStatus.uploaded)
              _docAction(
                icon: Icons.check,
                color: AppColors.success,
                tooltip: 'Approve',
                onTap: () => _approveDocument(worker, docName),
              ),
            if (doc.status != DocumentStatus.missing)
              _docAction(
                icon: Icons.close,
                color: AppColors.error,
                tooltip: 'Reject / Request Re-upload',
                onTap: () => _rejectDocument(worker, docName, doc),
              ),
            if (doc.status == DocumentStatus.missing)
              _docAction(
                icon: Icons.upload,
                color: AppColors.accent,
                tooltip: 'Mark as Received',
                onTap: () => _markDocReceived(worker, docName),
              ),
          ],
        ],
      ),
    );
  }

  Widget _docAction(
      {required IconData icon,
      required Color color,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  void _approveDocument(Worker worker, String docName) {
    final doc = worker.documents[docName]!;
    final oldStatus = doc.status.name;
    _workerStore.updateDocumentStatus(
        worker.id, docName, DocumentStatus.uploaded);
    _auditService.log(
      actor: widget.currentUser,
      action: AuditAction.documentApprove,
      entityType: AuditEntityType.document,
      entityId: '${worker.id}-$docName',
      entityDisplayName: '${worker.fullName} – $docName',
      fieldChanges: [
        AuditFieldChange(
            fieldName: 'Status',
            oldValue: oldStatus,
            newValue: 'approved'),
      ],
      note: 'Document approved by ${widget.currentUser.fullName}',
    );
    setState(() => _selectedWorker = _workerStore.getById(worker.id));
  }

  Future<void> _rejectDocument(
      Worker worker, String docName, WorkerDocument doc) async {
    final reason = await _promptText(
      context,
      title: 'Reject Document',
      hint: 'Reason for rejection (optional)',
    );

    _workerStore.updateDocumentStatus(
        worker.id, docName, DocumentStatus.missing,
        fileName: null);
    _auditService.log(
      actor: widget.currentUser,
      action: AuditAction.documentReject,
      entityType: AuditEntityType.document,
      entityId: '${worker.id}-$docName',
      entityDisplayName: '${worker.fullName} – $docName',
      fieldChanges: [
        AuditFieldChange(
            fieldName: 'Status',
            oldValue: doc.status.name,
            newValue: 'rejected'),
      ],
      note: reason,
    );
    setState(() => _selectedWorker = _workerStore.getById(worker.id));
  }

  void _markDocReceived(Worker worker, String docName) {
    _workerStore.updateDocumentStatus(
        worker.id, docName, DocumentStatus.pending,
        fileName: 'received_pending_review.pdf');
    _auditService.log(
      actor: widget.currentUser,
      action: AuditAction.documentUpload,
      entityType: AuditEntityType.document,
      entityId: '${worker.id}-$docName',
      entityDisplayName: '${worker.fullName} – $docName',
      fieldChanges: [
        const AuditFieldChange(
            fieldName: 'Status', oldValue: 'missing', newValue: 'pending'),
      ],
    );
    setState(() => _selectedWorker = _workerStore.getById(worker.id));
  }

  Widget _buildStatusActions(Worker worker, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.manage_accounts_outlined,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Employment Actions',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!worker.isActive)
                  _actionButton(
                    label: 'Reinstate',
                    icon: Icons.check_circle_outline,
                    color: AppColors.success,
                    onTap: () => _changeWorkerStatus(
                        worker, true, 'Worker reinstated'),
                  ),
                if (worker.isActive)
                  _actionButton(
                    label: 'Place on Leave',
                    icon: Icons.event_busy_outlined,
                    color: AppColors.warning,
                    onTap: () =>
                        _changeWorkerStatus(worker, false, 'Placed on leave'),
                  ),
                if (worker.isActive)
                  _actionButton(
                    label: 'Deactivate',
                    icon: Icons.block_outlined,
                    color: AppColors.error,
                    onTap: () =>
                        _confirmDeactivate(worker),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
      {required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 14, color: color),
      label: Text(label,
          style: TextStyle(fontSize: 12, color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onTap,
    );
  }

  Widget _buildNotesSection(Worker worker, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.notes_outlined,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Add HR Note',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('note-${worker.id}'),
                    decoration: const InputDecoration(
                      hintText:
                          'Enter HR note (will be recorded in audit trail)…',
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 3,
                    onSubmitted: (note) =>
                        _addHrNote(worker, note),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  child: const Text('Add', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerAuditTrail(Worker worker, bool isDark) {
    final logs = _auditService.getForEntity(worker.id);
    if (logs.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Change History (${logs.length})',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)),
            ]),
            const SizedBox(height: 8),
            ...logs.take(5).map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${e.shortTimestamp} · ${e.action.displayName} by ${e.userName}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary),
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

  // ── Document Queue tab ──────────────────────────────────────────────────────

  Widget _buildDocumentQueueTab(bool isDark) {
    final pending = _workerStore.workers
        .expand((w) => w.documents.entries
            .where((e) =>
                e.value.status == DocumentStatus.missing ||
                e.value.status == DocumentStatus.pending)
            .map((e) => _DocQueueItem(worker: w, docName: e.key, doc: e.value)))
        .toList();

    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle,
                size: 48, color: AppColors.success),
            const SizedBox(height: 12),
            Text('All documents are up to date',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? AppColors.darkCard : AppColors.card,
          child: Row(children: [
            const Icon(Icons.pending_actions,
                size: 16, color: AppColors.warning),
            const SizedBox(width: 6),
            Text('${pending.length} documents require attention',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.warning)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: pending.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
            itemBuilder: (_, i) =>
                _buildQueueItem(pending[i], isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueItem(_DocQueueItem item, bool isDark) {
    final isMissing = item.doc.status == DocumentStatus.missing;
    final color = isMissing ? AppColors.error : AppColors.warning;
    final label = isMissing ? 'Missing' : 'Pending Review';

    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          isMissing ? Icons.cancel_outlined : Icons.hourglass_empty,
          size: 16,
          color: color,
        ),
      ),
      title: Text(item.docName,
          style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary)),
      subtitle: Text(item.worker.fullName,
          style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppColors.darkTextHint
                  : AppColors.textHint)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 10, color: color)),
          ),
          if (_canEdit && !isMissing) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.check,
                  size: 16, color: AppColors.success),
              onPressed: () =>
                  _approveDocument(item.worker, item.docName),
              tooltip: 'Approve',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ],
      ),
      onTap: () {
        setState(() {
          _selectedWorker = item.worker;
          _tabCtrl.animateTo(0);
        });
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Future<void> _changeWorkerStatus(
      Worker worker, bool active, String reason) async {
    final confirm = await _promptText(
      context,
      title: reason,
      hint: 'Reason (required)',
    );
    if (confirm == null || confirm.isEmpty) return;

    if (active) {
      _workerStore.updateWorker(
          Worker(
            id: worker.id,
            fullName: worker.fullName,
            nisNumber: worker.nisNumber,
            dateOfBirth: worker.dateOfBirth,
            position: worker.position,
            idNumber: worker.idNumber,
            corporationId: worker.corporationId,
            corporationName: worker.corporationName,
            electoralDistrict: worker.electoralDistrict,
            wageRate: worker.wageRate,
            colaRate: worker.colaRate,
            allowanceRate: worker.allowanceRate,
            bankInfo: worker.bankInfo,
            documents: worker.documents,
            dateRegistered: worker.dateRegistered,
            isActive: true,
            customAllowances: worker.customAllowances,
            contact: worker.contact,
            address: worker.address,
            birNumber: worker.birNumber,
            startDate: worker.startDate,
            endDate: null,
            referenceNumber: worker.referenceNumber,
          ));
      _auditService.log(
        actor: widget.currentUser,
        action: AuditAction.activate,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          const AuditFieldChange(
              fieldName: 'Status', oldValue: 'Inactive', newValue: 'Active'),
        ],
        note: confirm,
      );
    } else {
      _workerStore.deactivateWorker(worker.id);
      _auditService.log(
        actor: widget.currentUser,
        action: AuditAction.deactivate,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          const AuditFieldChange(
              fieldName: 'Status', oldValue: 'Active', newValue: 'Inactive'),
        ],
        note: confirm,
      );
    }
    setState(() => _selectedWorker = _workerStore.getById(worker.id));
  }

  Future<void> _confirmDeactivate(Worker worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.error),
            SizedBox(width: 8),
            Text('Deactivate Worker'),
          ],
        ),
        content: Text(
            'Are you sure you want to deactivate ${worker.fullName}? '
            'This action will be logged in the audit trail.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _changeWorkerStatus(
          worker, false, 'Worker deactivated by HR');
    }
  }

  void _addHrNote(Worker worker, String note) {
    if (note.isEmpty) return;
    _auditService.log(
      actor: widget.currentUser,
      action: AuditAction.update,
      entityType: AuditEntityType.worker,
      entityId: worker.id,
      entityDisplayName: worker.fullName,
      note: 'HR Note: $note',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note added to audit trail')),
    );
  }

  Future<String?> _promptText(BuildContext context,
      {required String title, required String hint}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    final p = (int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }
}

class _DocQueueItem {
  final Worker worker;
  final String docName;
  final WorkerDocument doc;
  _DocQueueItem(
      {required this.worker, required this.docName, required this.doc});
}
