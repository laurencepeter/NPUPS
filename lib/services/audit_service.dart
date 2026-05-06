// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Tamper-evident audit trail using SHA-256 hash chaining.
// Every entry contains a hash of (previousHash + core entry data).
// Any modification to a past entry breaks the chain — detectable via
// verifyChainIntegrity(). Suitable for legal/compliance use.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/audit_model.dart';
import '../models/user_model.dart';

class AuditService extends ChangeNotifier {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal() {
    _seedDemoLogs();
  }

  final List<AuditLogEntry> _entries = [];
  int _sequenceCounter = 0;

  // The hash of the most recently added entry (genesis = empty string).
  String _latestHash = '';

  List<AuditLogEntry> get entries => List.unmodifiable(_entries);

  // ── Public API ─────────────────────────────────────────────────────────────

  void log({
    required AppUser actor,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityDisplayName,
    List<AuditFieldChange> fieldChanges = const [],
    List<AuditAttachment> attachments = const [],
    String? note,
    String? sessionId,
    String? actorContext,
  }) {
    _sequenceCounter++;
    final id = 'AUDIT-${_sequenceCounter.toString().padLeft(6, '0')}';
    final now = DateTime.now();
    final sid = sessionId ?? 'session-${actor.id}';

    final hash = _computeHash(
      previousHash: _latestHash,
      id: id,
      timestamp: now,
      userId: actor.id,
      action: action,
      entityType: entityType,
      entityId: entityId,
      fieldChanges: fieldChanges,
      attachments: attachments,
    );

    final entry = AuditLogEntry(
      id: id,
      timestamp: now,
      userId: actor.id,
      userName: actor.fullName,
      userRole: _roleLabel(actor.role),
      sessionId: sid,
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityDisplayName: entityDisplayName,
      fieldChanges: fieldChanges,
      attachments: attachments,
      note: note,
      actorContext: actorContext,
      hash: hash,
      previousHash: _latestHash,
    );

    _entries.add(entry);
    _latestHash = hash;
    notifyListeners();
  }

  /// Convenience for recording wage rate changes (basis for backpay calc).
  void logWageRateChange({
    required AppUser actor,
    required String workerId,
    required String workerName,
    required double oldRate,
    required double newRate,
    required DateTime effectiveFrom,
    String? note,
  }) {
    log(
      actor: actor,
      action: AuditAction.wageRateChanged,
      entityType: AuditEntityType.worker,
      entityId: workerId,
      entityDisplayName: workerName,
      fieldChanges: [
        AuditFieldChange(
          fieldName: 'Wage Rate',
          oldValue: oldRate.toStringAsFixed(2),
          newValue: newRate.toStringAsFixed(2),
        ),
        AuditFieldChange(
          fieldName: 'Effective From',
          newValue:
              '${effectiveFrom.year}-${effectiveFrom.month.toString().padLeft(2, '0')}-${effectiveFrom.day.toString().padLeft(2, '0')}',
        ),
      ],
      note: note,
    );
  }

  // Convenience: log a plain event with no field diffs.
  void logEvent({
    required AppUser actor,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityDisplayName,
    String? note,
    String? sessionId,
  }) {
    log(
      actor: actor,
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityDisplayName: entityDisplayName,
      note: note,
      sessionId: sessionId,
    );
  }

  // ── Queries ─────────────────────────────────────────────────────────────────

  List<AuditLogEntry> getAll() => List.unmodifiable(_entries.reversed.toList());

  List<AuditLogEntry> getForEntity(String entityId) =>
      _entries.where((e) => e.entityId == entityId).toList().reversed.toList();

  List<AuditLogEntry> getForUser(String userId) =>
      _entries.where((e) => e.userId == userId).toList().reversed.toList();

  List<AuditLogEntry> filter({
    DateTime? from,
    DateTime? to,
    AuditAction? action,
    AuditEntityType? entityType,
    String? userId,
    String? searchText,
  }) {
    var result = _entries.toList();

    if (from != null) result = result.where((e) => !e.timestamp.isBefore(from)).toList();
    if (to != null) result = result.where((e) => !e.timestamp.isAfter(to)).toList();
    if (action != null) result = result.where((e) => e.action == action).toList();
    if (entityType != null) result = result.where((e) => e.entityType == entityType).toList();
    if (userId != null && userId.isNotEmpty) result = result.where((e) => e.userId == userId).toList();
    if (searchText != null && searchText.isNotEmpty) {
      final q = searchText.toLowerCase();
      result = result.where((e) =>
        e.userName.toLowerCase().contains(q) ||
        e.entityDisplayName.toLowerCase().contains(q) ||
        e.entityId.toLowerCase().contains(q) ||
        (e.note?.toLowerCase().contains(q) ?? false) ||
        e.fieldChanges.any((f) =>
          f.fieldName.toLowerCase().contains(q) ||
          (f.oldValue?.toLowerCase().contains(q) ?? false) ||
          (f.newValue?.toLowerCase().contains(q) ?? false)),
      ).toList();
    }

    return result.reversed.toList();
  }

  // ── Chain Integrity ─────────────────────────────────────────────────────────

  /// Returns true only if every entry's hash matches its computed value.
  /// A single tampered entry breaks the chain from that point forward.
  ChainVerificationResult verifyChainIntegrity() {
    if (_entries.isEmpty) {
      return const ChainVerificationResult(isValid: true, totalEntries: 0, firstBrokenIndex: null);
    }

    String prevHash = '';
    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];

      if (e.previousHash != prevHash) {
        return ChainVerificationResult(
          isValid: false,
          totalEntries: _entries.length,
          firstBrokenIndex: i,
          firstBrokenEntryId: e.id,
        );
      }

      final expected = _computeHash(
        previousHash: prevHash,
        id: e.id,
        timestamp: e.timestamp,
        userId: e.userId,
        action: e.action,
        entityType: e.entityType,
        entityId: e.entityId,
        fieldChanges: e.fieldChanges,
        attachments: e.attachments,
      );

      if (e.hash != expected) {
        return ChainVerificationResult(
          isValid: false,
          totalEntries: _entries.length,
          firstBrokenIndex: i,
          firstBrokenEntryId: e.id,
        );
      }

      prevHash = e.hash;
    }

    return ChainVerificationResult(
      isValid: true,
      totalEntries: _entries.length,
      firstBrokenIndex: null,
    );
  }

  // ── Hash Computation ────────────────────────────────────────────────────────

  static String _computeHash({
    required String previousHash,
    required String id,
    required DateTime timestamp,
    required String userId,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required List<AuditFieldChange> fieldChanges,
    List<AuditAttachment> attachments = const [],
  }) {
    final changesStr = fieldChanges
        .map((f) => '${f.fieldName}|${f.oldValue ?? ''}|${f.newValue ?? ''}')
        .join(';');
    final attachStr = attachments
        .map((a) => '${a.id}|${a.contentHash}|${a.sizeBytes}')
        .join(';');

    final payload = [
      previousHash,
      id,
      timestamp.microsecondsSinceEpoch.toString(),
      userId,
      action.name,
      entityType.name,
      entityId,
      changesStr,
      attachStr,
    ].join('||');

    final bytes = utf8.encode(payload);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Hashes a file's bytes for tamper-evident attachment binding.
  static String hashAttachmentBytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Export the audit chain as a portable JSON-friendly map for offline review
  /// (e.g. printing to PDF for the employer's compliance trail).
  List<Map<String, dynamic>> exportChainAsJson() {
    return _entries.map((e) => {
      'id': e.id,
      'timestamp': e.timestamp.toIso8601String(),
      'user': {'id': e.userId, 'name': e.userName, 'role': e.userRole},
      'session': e.sessionId,
      'action': e.action.name,
      'entity': {
        'type': e.entityType.name,
        'id': e.entityId,
        'display': e.entityDisplayName,
      },
      'fieldChanges': e.fieldChanges
          .map((f) => {
                'field': f.fieldName,
                'old': f.oldValue,
                'new': f.newValue,
              })
          .toList(),
      'attachments': e.attachments
          .map((a) => {
                'id': a.id,
                'fileName': a.fileName,
                'mimeType': a.mimeType,
                'sizeBytes': a.sizeBytes,
                'contentHash': a.contentHash,
              })
          .toList(),
      'note': e.note,
      'previousHash': e.previousHash,
      'hash': e.hash,
    }).toList();
  }

  static String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.systemAdmin => 'System Admin',
      UserRole.ps => 'Permanent Secretary',
      UserRole.dmcr => 'DMCR',
      UserRole.regionalCoordinator => 'Regional Coordinator',
      UserRole.hr => 'HR Department',
      UserRole.subAccounts => 'Sub-Accounts',
      UserRole.mainAccounts => 'Main Accounts',
      UserRole.ministersDepartment => "Executive Department",
      UserRole.worker => 'Worker',
    };
  }

  // ── Demo Seed Data ──────────────────────────────────────────────────────────

  void _seedDemoLogs() {
    const demoUser = AppUser(
      id: 'admin',
      email: 'admin@workforce.app',
      fullName: 'System Administrator',
      role: UserRole.systemAdmin,
    );

    const hrUser = AppUser(
      id: 'hr-001',
      email: 'hr@workforce.app',
      fullName: 'HR Officer',
      role: UserRole.hr,
      corporationId: '2',
      corporationName: 'Chaguanas Borough Corporation',
    );

    const coordUser = AppUser(
      id: 'coord-001',
      email: 'coordinator@workforce.app',
      fullName: 'Regional Coordinator',
      role: UserRole.regionalCoordinator,
      corporationId: '8',
      corporationName: 'Port of Spain City Corporation',
    );

    // Seed historic entries so the log is non-empty on first launch
    _seedEntry(
      actor: demoUser,
      action: AuditAction.login,
      entityType: AuditEntityType.userAccount,
      entityId: 'admin',
      entityDisplayName: 'System Administrator',
      note: 'Initial system login',
      daysAgo: 30,
    );

    _seedEntry(
      actor: demoUser,
      action: AuditAction.create,
      entityType: AuditEntityType.worker,
      entityId: 'WRK-001',
      entityDisplayName: 'Kevin Rampersad',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Full Name', newValue: 'Kevin Rampersad'),
        const AuditFieldChange(fieldName: 'NIS Number', newValue: 'NIS-2024-00147'),
        const AuditFieldChange(fieldName: 'Position', newValue: 'General Worker'),
        const AuditFieldChange(fieldName: 'Corporation', newValue: 'Port of Spain City Corporation'),
      ],
      daysAgo: 28,
    );

    _seedEntry(
      actor: hrUser,
      action: AuditAction.documentUpload,
      entityType: AuditEntityType.document,
      entityId: 'WRK-001-NIS',
      entityDisplayName: 'Kevin Rampersad – NIS Registration',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Status', oldValue: 'Missing', newValue: 'Uploaded'),
        const AuditFieldChange(fieldName: 'File', newValue: 'nis_registration.pdf'),
      ],
      daysAgo: 25,
    );

    _seedEntry(
      actor: hrUser,
      action: AuditAction.documentApprove,
      entityType: AuditEntityType.document,
      entityId: 'WRK-001-NIS',
      entityDisplayName: 'Kevin Rampersad – NIS Registration',
      note: 'Document verified and approved',
      daysAgo: 24,
    );

    _seedEntry(
      actor: coordUser,
      action: AuditAction.create,
      entityType: AuditEntityType.timesheet,
      entityId: 'TS-001',
      entityDisplayName: 'Kevin Rampersad – Fortnight 17/03/2026',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Stage', newValue: 'Draft'),
        const AuditFieldChange(fieldName: 'Days Worked', newValue: '10'),
      ],
      daysAgo: 20,
    );

    _seedEntry(
      actor: coordUser,
      action: AuditAction.stageAdvanced,
      entityType: AuditEntityType.timesheet,
      entityId: 'TS-001',
      entityDisplayName: 'Kevin Rampersad – Fortnight 17/03/2026',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Stage', oldValue: 'Submitted', newValue: 'Coordinator Review'),
      ],
      note: 'Time entries verified in field',
      daysAgo: 18,
    );

    _seedEntry(
      actor: hrUser,
      action: AuditAction.update,
      entityType: AuditEntityType.worker,
      entityId: 'WRK-003',
      entityDisplayName: 'Andre Williams',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Phone Number', oldValue: '868-555-0303', newValue: '868-777-0303'),
        const AuditFieldChange(fieldName: 'Address', oldValue: '22 Montrose Road, Chaguanas', newValue: '45 Montrose Road, Chaguanas'),
      ],
      daysAgo: 10,
    );

    _seedEntry(
      actor: demoUser,
      action: AuditAction.replacementAdded,
      entityType: AuditEntityType.worker,
      entityId: 'WRK-006',
      entityDisplayName: 'Marcia Boodoo (replaced by Patricia Hernandez)',
      note: 'Repeated absenteeism and conduct issues',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Status', oldValue: 'Active', newValue: 'Inactive'),
        const AuditFieldChange(fieldName: 'Replacement Worker', newValue: 'Patricia Hernandez (WRK-011)'),
      ],
      daysAgo: 7,
    );

    _seedEntry(
      actor: hrUser,
      action: AuditAction.rosterUpdate,
      entityType: AuditEntityType.rosterEntry,
      entityId: 'ROSTER-2026-04-11',
      entityDisplayName: 'Chaguanas Borough Corporation – Fortnight 11/04/2026',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Andre Williams – Mon 13/04', oldValue: 'Present', newValue: 'Absent'),
        const AuditFieldChange(fieldName: 'Lisa Doodnath – Fri 17/04', oldValue: 'Present', newValue: 'Absent'),
      ],
      note: 'Updated absences for fortnight',
      daysAgo: 3,
    );

    _seedEntry(
      actor: demoUser,
      action: AuditAction.export,
      entityType: AuditEntityType.timesheet,
      entityId: 'BATCH-2026-04',
      entityDisplayName: 'Payroll Export – April 2026 (Port of Spain)',
      note: '12 timesheets exported to XLSX',
      daysAgo: 1,
    );

    // Wage rate change — basis for backpay calculation downstream.
    _seedEntry(
      actor: demoUser,
      action: AuditAction.wageRateChanged,
      entityType: AuditEntityType.worker,
      entityId: 'WRK-001',
      entityDisplayName: 'Kevin Rampersad',
      fieldChanges: [
        const AuditFieldChange(
            fieldName: 'Wage Rate', oldValue: '140.00', newValue: '150.00'),
        const AuditFieldChange(
            fieldName: 'Effective From', newValue: '2026-01-01'),
      ],
      note: 'Annual collective-agreement increase',
      daysAgo: 14,
    );

    // Backpay calculation seeded so the system shows a backpay history.
    _seedEntry(
      actor: demoUser,
      action: AuditAction.backpayCalculated,
      entityType: AuditEntityType.backpay,
      entityId: 'BP-2026-001',
      entityDisplayName: 'Q1 2026 Backpay – Kevin Rampersad',
      fieldChanges: [
        const AuditFieldChange(fieldName: 'Old Rate', newValue: '140.00'),
        const AuditFieldChange(fieldName: 'New Rate', newValue: '150.00'),
        const AuditFieldChange(fieldName: 'Fortnights Affected', newValue: '6'),
        const AuditFieldChange(fieldName: 'Backpay Amount', newValue: '600.00'),
      ],
      note: 'Retroactive to 01/01/2026',
      daysAgo: 5,
    );

    // Payroll batch with supporting attachments.
    _seedEntry(
      actor: demoUser,
      action: AuditAction.paymentRecorded,
      entityType: AuditEntityType.payment,
      entityId: 'PAY-2026-04-A',
      entityDisplayName: 'Direct Deposit Run – Port of Spain (April 2026)',
      attachments: [
        AuditAttachment(
          id: 'ATT-001',
          fileName: 'paysheet_pos_april_2026.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          sizeBytes: 24576,
          contentHash:
              'a4f2b7c91d8e6053e2f471aa9c3d6b8852f1c0d7e6b9a4f3c1d8e6053e2f471aa', // demo placeholder hash
          uploadedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
        AuditAttachment(
          id: 'ATT-002',
          fileName: 'bank_remittance_advice.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 152432,
          contentHash:
              'b9c3d6f2e1a87045d3c5b9e8f0a172bd5e84c2f9a1b6d307f4e8c2b1d50a9f6e',
          uploadedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
      note: '12 workers paid via direct deposit',
      daysAgo: 1,
    );
  }

  void _seedEntry({
    required AppUser actor,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityDisplayName,
    List<AuditFieldChange> fieldChanges = const [],
    List<AuditAttachment> attachments = const [],
    String? note,
    required int daysAgo,
  }) {
    _sequenceCounter++;
    final id = 'AUDIT-${_sequenceCounter.toString().padLeft(6, '0')}';
    final now = DateTime.now().subtract(Duration(days: daysAgo, hours: daysAgo % 8));

    final hash = _computeHash(
      previousHash: _latestHash,
      id: id,
      timestamp: now,
      userId: actor.id,
      action: action,
      entityType: entityType,
      entityId: entityId,
      fieldChanges: fieldChanges,
      attachments: attachments,
    );

    _entries.add(AuditLogEntry(
      id: id,
      timestamp: now,
      userId: actor.id,
      userName: actor.fullName,
      userRole: _roleLabel(actor.role),
      sessionId: 'demo-session-${actor.id}',
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityDisplayName: entityDisplayName,
      fieldChanges: fieldChanges,
      attachments: attachments,
      note: note,
      hash: hash,
      previousHash: _latestHash,
    ));

    _latestHash = hash;
  }
}

class ChainVerificationResult {
  final bool isValid;
  final int totalEntries;
  final int? firstBrokenIndex;
  final String? firstBrokenEntryId;

  const ChainVerificationResult({
    required this.isValid,
    required this.totalEntries,
    this.firstBrokenIndex,
    this.firstBrokenEntryId,
  });

  String get summary {
    if (isValid) return 'Chain intact — $totalEntries entries verified';
    return 'Chain broken at entry #${(firstBrokenIndex ?? 0) + 1} ($firstBrokenEntryId)';
  }
}
