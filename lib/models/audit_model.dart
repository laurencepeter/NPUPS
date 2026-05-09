// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Tamper-evident audit log with SHA-256 hash chaining.
// Every mutation in the system is recorded here with full before/after diffs.
// The hash chain means any alteration to a past record invalidates all
// subsequent hashes — detectable in court or external review.
// ──────────────────────────────────────────────────────────────────────────────

enum AuditAction {
  create('Created'),
  update('Updated'),
  delete('Deleted'),
  activate('Activated'),
  deactivate('Deactivated'),
  documentUpload('Document Uploaded'),
  documentReject('Document Rejected'),
  documentApprove('Document Approved'),
  approve('Approved'),
  reject('Rejected'),
  login('Logged In'),
  logout('Logged Out'),
  export('Exported'),
  import('Imported'),
  rosterUpdate('Roster Updated'),
  settingsChange('Settings Changed'),
  replacementAdded('Replacement Added'),
  stageAdvanced('Stage Advanced'),
  stageRejected('Stage Rejected'),
  attachmentAdded('Attachment Added'),
  attachmentRemoved('Attachment Removed'),
  wageRateChanged('Wage Rate Changed'),
  backpayCalculated('Backpay Calculated'),
  backpayApproved('Backpay Approved'),
  backpayDisbursed('Backpay Disbursed'),
  paymentRecorded('Payment Recorded'),
  paymentReversed('Payment Reversed'),
  allowanceAdded('Allowance Added'),
  allowanceUpdated('Allowance Updated'),
  allowanceRemoved('Allowance Removed'),
  duplicateIdAttempt('Duplicate ID Attempt');

  const AuditAction(this.displayName);
  final String displayName;
}

enum AuditEntityType {
  worker('Worker'),
  timesheet('Timesheet'),
  document('Document'),
  userAccount('User Account'),
  rosterEntry('Roster Entry'),
  rosterSettings('Roster Settings'),
  payroll('Payroll Batch'),
  payment('Payment'),
  backpay('Backpay'),
  attachment('Supporting Attachment'),
  system('System');

  const AuditEntityType(this.displayName);
  final String displayName;
}

/// A supporting document referenced by an audit entry — e.g. the signed
/// timesheet PDF that was the basis for an approval, or the cheque image
/// attached to a payment record.
class AuditAttachment {
  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  /// SHA-256 of the file content; the audit chain hash incorporates this so
  /// any swap of the underlying file invalidates the chain.
  final String contentHash;
  final DateTime uploadedAt;

  const AuditAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.contentHash,
    required this.uploadedAt,
  });

  String get readableSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  factory AuditAttachment.fromJson(Map<String, dynamic> j) => AuditAttachment(
        id: j['id'] as String,
        fileName: j['file_name'] as String,
        mimeType: j['mime_type'] as String,
        sizeBytes: (j['size_bytes'] as num).toInt(),
        contentHash: j['content_hash'] as String,
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'content_hash': contentHash,
        'uploaded_at': uploadedAt.toIso8601String(),
      };
}

// A single field-level change recorded within an audit entry.
class AuditFieldChange {
  final String fieldName;
  final String? oldValue;
  final String? newValue;

  const AuditFieldChange({
    required this.fieldName,
    this.oldValue,
    this.newValue,
  });

  @override
  String toString() => '$fieldName: "$oldValue" → "$newValue"';

  factory AuditFieldChange.fromJson(Map<String, dynamic> j) => AuditFieldChange(
        fieldName: j['field_name'] as String,
        oldValue: j['old_value'] as String?,
        newValue: j['new_value'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'field_name': fieldName,
        'old_value': oldValue,
        'new_value': newValue,
      };
}

class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String userId;
  final String userName;
  final String userRole;
  final String sessionId;
  final AuditAction action;
  final AuditEntityType entityType;
  final String entityId;
  final String entityDisplayName;
  final List<AuditFieldChange> fieldChanges;
  final List<AuditAttachment> attachments;
  final String? note;
  /// IP address or device fingerprint of the actor (best-effort).
  final String? actorContext;
  // SHA-256(prevHash + id + timestamp + userId + action + entityType + entityId + changes + attachmentHashes)
  final String hash;
  // The hash of the immediately preceding entry (empty string for genesis)
  final String previousHash;

  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.sessionId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.entityDisplayName,
    this.fieldChanges = const [],
    this.attachments = const [],
    this.note,
    this.actorContext,
    required this.hash,
    required this.previousHash,
  });

  bool get hasAttachments => attachments.isNotEmpty;

  String get formattedTimestamp {
    final d = timestamp;
    final pad2 = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${pad2(d.month)}-${pad2(d.day)} '
        '${pad2(d.hour)}:${pad2(d.minute)}:${pad2(d.second)}'
        '.${d.millisecond.toString().padLeft(3, '0')}';
  }

  String get shortTimestamp {
    final d = timestamp;
    final pad2 = (int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year} '
        '${pad2(d.hour)}:${pad2(d.minute)}';
  }

  bool get hasFieldChanges => fieldChanges.isNotEmpty;

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) => AuditLogEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        userId: j['user_id'] as String,
        userName: j['user_name'] as String,
        userRole: j['user_role'] as String,
        sessionId: j['session_id'] as String,
        action: AuditAction.values.byName(j['action'] as String),
        entityType:
            AuditEntityType.values.byName(j['entity_type'] as String),
        entityId: j['entity_id'] as String,
        entityDisplayName: j['entity_display_name'] as String,
        fieldChanges: (j['field_changes'] as List? ?? const [])
            .map((e) => AuditFieldChange.fromJson(e as Map<String, dynamic>))
            .toList(),
        attachments: (j['attachments'] as List? ?? const [])
            .map((e) => AuditAttachment.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: j['note'] as String?,
        actorContext: j['actor_context'] as String?,
        hash: j['hash'] as String,
        previousHash: j['previous_hash'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'user_id': userId,
        'user_name': userName,
        'user_role': userRole,
        'session_id': sessionId,
        'action': action.name,
        'entity_type': entityType.name,
        'entity_id': entityId,
        'entity_display_name': entityDisplayName,
        'field_changes': fieldChanges.map((f) => f.toJson()).toList(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'note': note,
        'actor_context': actorContext,
        'hash': hash,
        'previous_hash': previousHash,
      };
}
