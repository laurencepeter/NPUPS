// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Full tamper-evident audit trail viewer with:
//  - Filters: date range, user, action type, entity type, text search
//  - Per-entry field-level diff (before → after)
//  - Chain integrity verification badge
//  - Role restricted: systemAdmin, ps, hr, dmcr
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/audit_model.dart';
import '../models/user_model.dart';
import '../services/audit_service.dart';
import '../theme/app_theme.dart';

class AuditLogScreen extends StatefulWidget {
  final AppUser currentUser;

  const AuditLogScreen({super.key, required this.currentUser});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuditService _auditService = AuditService();
  final TextEditingController _searchCtrl = TextEditingController();

  AuditAction? _filterAction;
  AuditEntityType? _filterEntityType;
  DateTimeRange? _filterDateRange;
  ChainVerificationResult? _verificationResult;
  bool _showFilters = false;
  AuditLogEntry? _expandedEntry;

  @override
  void initState() {
    super.initState();
    _verificationResult = _auditService.verifyChainIntegrity();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AuditLogEntry> get _filteredEntries => _auditService.filter(
        from: _filterDateRange?.start,
        to: _filterDateRange?.end?.add(const Duration(days: 1)),
        action: _filterAction,
        entityType: _filterEntityType,
        searchText: _searchCtrl.text,
      );

  bool get _hasActiveFilters =>
      _filterAction != null ||
      _filterEntityType != null ||
      _filterDateRange != null ||
      _searchCtrl.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _auditService,
      builder: (context, _) {
        final entries = _filteredEntries;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Audit Trail'),
            actions: [
              // Chain integrity badge
              _ChainBadge(result: _verificationResult),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                  color: _hasActiveFilters ? AppColors.accent : null,
                ),
                tooltip: 'Filters',
                onPressed: () => setState(() => _showFilters = !_showFilters),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-verify chain',
                onPressed: () => setState(() {
                  _verificationResult = _auditService.verifyChainIntegrity();
                }),
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Search bar ────────────────────────────────────────────────
              Container(
                color: isDark ? AppColors.darkCard : AppColors.card,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by user, entity, field, value…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                  ),
                ),
              ),

              // ── Filter panel ──────────────────────────────────────────────
              if (_showFilters) _buildFilterPanel(context),

              // ── Stats bar ─────────────────────────────────────────────────
              Container(
                color: isDark
                    ? AppColors.darkBackground
                    : AppColors.surface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${entries.length} entries',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.clear_all, size: 14),
                        label: const Text('Clear filters',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _clearFilters,
                      ),
                    ],
                    const Spacer(),
                    if (_verificationResult != null)
                      Icon(
                        _verificationResult!.isValid
                            ? Icons.verified_outlined
                            : Icons.warning_amber_outlined,
                        size: 14,
                        color: _verificationResult!.isValid
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _verificationResult?.summary ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        color: _verificationResult?.isValid == true
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // ── Entry list ────────────────────────────────────────────────
              Expanded(
                child: entries.isEmpty
                    ? _buildEmpty(isDark)
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.border,
                        ),
                        itemBuilder: (context, i) =>
                            _buildEntry(context, entries[i], isDark),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkCard : AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Action filter
              _FilterChip<AuditAction>(
                label: 'Action',
                value: _filterAction,
                items: AuditAction.values,
                displayName: (a) => a.displayName,
                onSelected: (a) => setState(() => _filterAction = a),
              ),
              // Entity type filter
              _FilterChip<AuditEntityType>(
                label: 'Entity',
                value: _filterEntityType,
                items: AuditEntityType.values,
                displayName: (e) => e.displayName,
                onSelected: (e) => setState(() => _filterEntityType = e),
              ),
              // Date range
              ActionChip(
                avatar: Icon(
                  Icons.date_range,
                  size: 16,
                  color: _filterDateRange != null
                      ? AppColors.accent
                      : null,
                ),
                label: Text(
                  _filterDateRange != null
                      ? '${_fmt(_filterDateRange!.start)} – ${_fmt(_filterDateRange!.end)}'
                      : 'Date Range',
                  style: TextStyle(
                    fontSize: 12,
                    color: _filterDateRange != null ? AppColors.accent : null,
                  ),
                ),
                onPressed: _pickDateRange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(
      BuildContext context, AuditLogEntry entry, bool isDark) {
    final isExpanded = _expandedEntry?.id == entry.id;
    final actionColor = _actionColor(entry.action);

    return InkWell(
      onTap: () => setState(() {
        _expandedEntry = isExpanded ? null : entry;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action icon badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_actionIcon(entry.action),
                      size: 16, color: actionColor),
                ),
                const SizedBox(width: 10),

                // Main info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.action.displayName} · ${entry.entityType.displayName}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            entry.shortTimestamp,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.entityDisplayName,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 12,
                              color: isDark
                                  ? AppColors.darkTextHint
                                  : AppColors.textHint),
                          const SizedBox(width: 3),
                          Text(
                            '${entry.userName} (${entry.userRole})',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextHint
                                  : AppColors.textHint,
                            ),
                          ),
                          if (entry.hasFieldChanges) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${entry.fieldChanges.length} field${entry.fieldChanges.length == 1 ? '' : 's'} changed',
                                style: const TextStyle(
                                    fontSize: 10, color: AppColors.info),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: isDark
                      ? AppColors.darkTextHint
                      : AppColors.textHint,
                ),
              ],
            ),

            // ── Expanded detail ─────────────────────────────────────────
            if (isExpanded) ...[
              const SizedBox(height: 10),
              _buildEntryDetail(entry, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntryDetail(AuditLogEntry entry, bool isDark) {
    final bg = isDark ? AppColors.darkBackground : AppColors.surface;
    final textColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meta info
          _detailRow('Entry ID', entry.id, isDark),
          _detailRow('Timestamp', entry.formattedTimestamp, isDark),
          _detailRow('User ID', entry.userId, isDark),
          _detailRow('Session ID', entry.sessionId, isDark),
          _detailRow('Entity ID', entry.entityId, isDark),
          if (entry.note != null) _detailRow('Note', entry.note!, isDark),

          // Hash info
          const SizedBox(height: 8),
          Text('Chain Hash',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor)),
          const SizedBox(height: 3),
          SelectableText(
            entry.hash,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: isDark ? AppColors.darkAccentLight : AppColors.accent,
            ),
          ),

          // Field changes
          if (entry.hasFieldChanges) ...[
            const SizedBox(height: 10),
            Text('Field Changes',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 6),
            ...entry.fieldChanges.map((fc) => _buildFieldChange(fc, isDark)),
          ],

          // Supporting attachments — supplies the documentary evidence trail.
          if (entry.hasAttachments) ...[
            const SizedBox(height: 10),
            Text('Supporting Attachments',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 6),
            ...entry.attachments.map((a) => _buildAttachment(a, isDark)),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachment(AuditAttachment a, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file, size: 14, color: AppColors.info),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.fileName,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(
                    '${a.mimeType} • ${a.readableSize}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.darkTextHint
                          : AppColors.textHint,
                    ),
                  ),
                  Text('SHA-256: ${a.contentHash.substring(0, 16)}…',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: AppColors.info)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldChange(AuditFieldChange fc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              fc.fieldName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (fc.oldValue != null) ...[
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(fc.oldValue!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.error)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_forward, size: 12,
                  color: AppColors.textHint),
            ),
          ],
          if (fc.newValue != null)
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(fc.newValue!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.success)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextHint
                      : AppColors.textHint,
                )),
          ),
          Expanded(
            child: SelectableText(value,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_edu,
              size: 48,
              color: isDark
                  ? AppColors.darkTextHint
                  : AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'No audit entries match your filters',
            style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _filterAction = null;
      _filterEntityType = null;
      _filterDateRange = null;
      _searchCtrl.clear();
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _filterDateRange,
    );
    if (range != null) setState(() => _filterDateRange = range);
  }

  static Color _actionColor(AuditAction a) {
    return switch (a) {
      AuditAction.create => AppColors.success,
      AuditAction.update => AppColors.info,
      AuditAction.delete || AuditAction.deactivate => AppColors.error,
      AuditAction.activate => AppColors.success,
      AuditAction.approve ||
      AuditAction.documentApprove ||
      AuditAction.stageAdvanced =>
        AppColors.success,
      AuditAction.reject ||
      AuditAction.documentReject ||
      AuditAction.stageRejected =>
        AppColors.error,
      AuditAction.login || AuditAction.logout => AppColors.primary,
      AuditAction.export || AuditAction.import => AppColors.accentDark,
      AuditAction.rosterUpdate => AppColors.warning,
      AuditAction.documentUpload => AppColors.info,
      AuditAction.attachmentAdded => AppColors.info,
      AuditAction.attachmentRemoved => AppColors.error,
      AuditAction.wageRateChanged => AppColors.warning,
      AuditAction.backpayCalculated => AppColors.warning,
      AuditAction.backpayApproved => AppColors.success,
      AuditAction.backpayDisbursed => AppColors.primary,
      AuditAction.paymentRecorded => AppColors.success,
      AuditAction.paymentReversed => AppColors.error,
      AuditAction.allowanceAdded => AppColors.success,
      AuditAction.allowanceUpdated => AppColors.info,
      AuditAction.allowanceRemoved => AppColors.error,
      _ => AppColors.textSecondary,
    };
  }

  static IconData _actionIcon(AuditAction a) {
    return switch (a) {
      AuditAction.create => Icons.add_circle_outline,
      AuditAction.update => Icons.edit_outlined,
      AuditAction.delete => Icons.delete_outline,
      AuditAction.activate => Icons.check_circle_outline,
      AuditAction.deactivate => Icons.block_outlined,
      AuditAction.documentUpload => Icons.upload_file_outlined,
      AuditAction.documentApprove => Icons.verified_outlined,
      AuditAction.documentReject => Icons.cancel_outlined,
      AuditAction.approve => Icons.thumb_up_outlined,
      AuditAction.reject => Icons.thumb_down_outlined,
      AuditAction.login => Icons.login_outlined,
      AuditAction.logout => Icons.logout_outlined,
      AuditAction.export => Icons.download_outlined,
      AuditAction.import => Icons.upload_outlined,
      AuditAction.rosterUpdate => Icons.calendar_today_outlined,
      AuditAction.settingsChange => Icons.settings_outlined,
      AuditAction.replacementAdded => Icons.swap_horiz,
      AuditAction.stageAdvanced => Icons.arrow_forward_outlined,
      AuditAction.stageRejected => Icons.arrow_back_outlined,
      AuditAction.attachmentAdded => Icons.attach_file_outlined,
      AuditAction.attachmentRemoved => Icons.link_off_outlined,
      AuditAction.wageRateChanged => Icons.trending_up_outlined,
      AuditAction.backpayCalculated => Icons.calculate_outlined,
      AuditAction.backpayApproved => Icons.task_alt_outlined,
      AuditAction.backpayDisbursed => Icons.payments_outlined,
      AuditAction.paymentRecorded => Icons.account_balance_wallet_outlined,
      AuditAction.paymentReversed => Icons.undo_outlined,
      AuditAction.allowanceAdded => Icons.add_card_outlined,
      AuditAction.allowanceUpdated => Icons.tune_outlined,
      AuditAction.allowanceRemoved => Icons.remove_circle_outline,
    };
  }

  String _fmt(DateTime d) {
    final p = (int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _ChainBadge extends StatelessWidget {
  final ChainVerificationResult? result;
  const _ChainBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result == null) return const SizedBox.shrink();
    final ok = result!.isValid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ok
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: ok ? AppColors.success : AppColors.error, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.shield_outlined : Icons.shield_outlined,
              size: 13,
              color: ok ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              ok ? 'Chain Intact' : 'Chain Broken',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ok ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) displayName;
  final ValueChanged<T?> onSelected;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.items,
    required this.displayName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        Icons.filter_list,
        size: 14,
        color: value != null ? AppColors.accent : null,
      ),
      label: Text(
        value != null ? displayName(value as T) : label,
        style: TextStyle(
          fontSize: 12,
          color: value != null ? AppColors.accent : null,
        ),
      ),
      onPressed: () async {
        final selected = await showDialog<T?>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Filter by $label'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('All (clear filter)'),
              ),
              ...items.map((item) => SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(item),
                    child: Text(displayName(item)),
                  )),
            ],
          ),
        );
        if (selected != null || value != null) onSelected(selected);
      },
    );
  }
}
