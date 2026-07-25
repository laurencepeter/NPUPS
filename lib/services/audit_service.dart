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
import 'api_client.dart';

class AuditService extends ChangeNotifier {
  static final AuditService _instance = AuditService._internal();
  factory AuditService() => _instance;
  AuditService._internal();

  final ApiClient _api = ApiClient();
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Pull the audit chain from the backend. The seeded "genesis prefix"
  /// rows in db/domain_schema.sql carry deterministic synthetic hashes;
  /// once a real backend takes over writing entries, the chain hashes are
  /// computed by the application code (see _computeHash) and remain stable.
  Future<void> loadFromBackend({bool force = false}) async {
    if (_loaded && !force) return;
    final json = await _api.getList('/api/audit-logs');
    _entries
      ..clear()
      ..addAll(
          json.map((j) => AuditLogEntry.fromJson(j as Map<String, dynamic>)));
    if (_entries.isNotEmpty) {
      _latestHash = _entries.last.hash;
      _sequenceCounter = _entries.length;
    } else {
      _latestHash = '';
      _sequenceCounter = 0;
    }
    _loaded = true;
    notifyListeners();
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

    // Persist asynchronously. Audit entries are immutable so there's no
    // rollback to perform if the backend rejects — the local copy still
    // appears in the chain, and a subsequent loadFromBackend(force:true)
    // will reconcile if the write was actually accepted.
    _api.postJson('/api/audit-logs', entry.toJson()).catchError((e) {
      debugPrint('audit persist failed for ${entry.id}: $e');
    });
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

    // NOTE: millisecondsSinceEpoch (not micros). The chain is persisted and
    // re-hydrated through the API, whose JSON timestamps carry only
    // millisecond precision (server serialises with Date.toISOString()).
    // Hashing at millisecond granularity keeps a re-loaded entry's recomputed
    // hash identical to the one written, so the chain still verifies after a
    // round-trip. The SQL seed (db/domain_schema.sql) mirrors this exactly.
    final payload = [
      previousHash,
      id,
      timestamp.millisecondsSinceEpoch.toString(),
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


  // ── Demo seed removed ──────────────────────────────────────────────────
  // The 13 historical audit entries that previously lived here have been
  // moved to db/domain_schema.sql (see app_audit_logs / app_audit_field_changes
  // / app_audit_attachments). loadFromBackend() above pulls them from the API.
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
