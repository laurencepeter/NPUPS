// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Audit Service
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
    required NpupsUser actor,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityDisplayName,
    List<AuditFieldChange> fieldChanges = const [],
    String? note,
    String? sessionId,
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
      note: note,
      hash: hash,
      previousHash: _latestHash,
    );

    _entries.add(entry);
    _latestHash = hash;
    notifyListeners();
  }

  // Convenience: log a plain event with no field diffs.
  void logEvent({
    required NpupsUser actor,
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
  }) {
    final changesStr = fieldChanges
        .map((f) => '${f.fieldName}|${f.oldValue ?? ''}|${f.newValue ?? ''}')
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
    ].join('||');

    final bytes = utf8.encode(payload);
    final digest = sha256.convert(bytes);
    return digest.toString();
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
      UserRole.ministersDepartment => "Minister's Department",
      UserRole.worker => 'Worker',
    };
  }

  // ── Demo Seed Data ──────────────────────────────────────────────────────────

  void _seedDemoLogs() {
    const demoUser = NpupsUser(
      id: 'admin',
      email: 'admin@npups.gov.tt',
      fullName: 'System Administrator',
      role: UserRole.systemAdmin,
    );

    const hrUser = NpupsUser(
      id: 'hr-001',
      email: 'hr@npups.gov.tt',
      fullName: 'HR Officer',
      role: UserRole.hr,
      corporationId: '2',
      corporationName: 'Chaguanas Borough Corporation',
    );

    const coordUser = NpupsUser(
      id: 'coord-001',
      email: 'coordinator@npups.gov.tt',
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
  }

  void _seedEntry({
    required NpupsUser actor,
    required AuditAction action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityDisplayName,
    List<AuditFieldChange> fieldChanges = const [],
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
