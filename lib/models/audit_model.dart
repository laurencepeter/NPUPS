// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Audit Trail Model
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
  stageRejected('Stage Rejected');

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
  system('System');

  const AuditEntityType(this.displayName);
  final String displayName;
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
  final String? note;
  // SHA-256(prevHash + id + timestamp + userId + action + entityType + entityId + changes)
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
    this.note,
    required this.hash,
    required this.previousHash,
  });

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
}
