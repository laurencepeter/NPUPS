// ─────────────────────────────────────────────────────────────────────────────
// Audit log seed — computes hashes using the identical algorithm to
// lib/services/audit_service.dart _computeHash() so chain verification passes.
//
// Called automatically from index.js on startup when app_audit_logs is empty.
// Can also be run standalone to reseed an existing database:
//   DATABASE_URL=<url> node server/seed_audit.js
// ─────────────────────────────────────────────────────────────────────────────

'use strict';

const { createHash } = require('crypto');

// Mirror of AuditService._computeHash() in Dart.
// payload = previousHash || id || microsecondsSinceEpoch || userId ||
//           action || entityType || entityId || changesStr || attachStr
function computeHash({ previousHash, id, timestamp, userId, action, entityType, entityId, fieldChanges = [], attachments = [] }) {
  const changesStr = fieldChanges
    .map(f => `${f.fieldName}|${f.oldValue ?? ''}|${f.newValue ?? ''}`)
    .join(';');
  const attachStr = attachments
    .map(a => `${a.id}|${a.contentHash}|${a.sizeBytes}`)
    .join(';');

  // Dart DateTime.microsecondsSinceEpoch == JS Date.getTime() * 1000
  // (clean-second timestamps have 0 sub-millisecond component)
  const microseconds = BigInt(timestamp.getTime()) * 1000n;

  const payload = [
    previousHash,
    id,
    microseconds.toString(),
    userId,
    action,
    entityType,
    entityId,
    changesStr,
    attachStr,
  ].join('||');

  return createHash('sha256').update(payload, 'utf8').digest('hex');
}

// Timestamps: 2026-04-27 12:00:00 UTC minus N days
const BASE_MS = new Date('2026-04-27T12:00:00Z').getTime();
const DAY_MS  = 86_400_000;
const ts = daysAgo => new Date(BASE_MS - daysAgo * DAY_MS);

// ── Seed data ─────────────────────────────────────────────────────────────────

const ENTRIES = [
  { id: 'AUDIT-000001', daysAgo: 30, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'login',             entityType: 'userAccount', entityId: 'admin',             entityDisplayName: 'System Administrator',                               note: 'Initial system login' },
  { id: 'AUDIT-000002', daysAgo: 28, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'create',            entityType: 'worker',      entityId: 'WRK-001',           entityDisplayName: 'Kevin Rampersad',                                    note: null },
  { id: 'AUDIT-000003', daysAgo: 25, userId: 'hr-001',    userName: 'HR Officer',           userRole: 'HR Department',        sessionId: 'demo-session-hr-001',    action: 'documentUpload',    entityType: 'document',    entityId: 'WRK-001-NIS',       entityDisplayName: 'Kevin Rampersad – NIS Registration',            note: null },
  { id: 'AUDIT-000004', daysAgo: 24, userId: 'hr-001',    userName: 'HR Officer',           userRole: 'HR Department',        sessionId: 'demo-session-hr-001',    action: 'documentApprove',   entityType: 'document',    entityId: 'WRK-001-NIS',       entityDisplayName: 'Kevin Rampersad – NIS Registration',            note: 'Document verified and approved' },
  { id: 'AUDIT-000005', daysAgo: 20, userId: 'coord-001', userName: 'Regional Coordinator', userRole: 'Regional Coordinator', sessionId: 'demo-session-coord-001', action: 'create',            entityType: 'timesheet',   entityId: 'TS-001',            entityDisplayName: 'Kevin Rampersad – Fortnight 17/03/2026',       note: null },
  { id: 'AUDIT-000006', daysAgo: 18, userId: 'coord-001', userName: 'Regional Coordinator', userRole: 'Regional Coordinator', sessionId: 'demo-session-coord-001', action: 'stageAdvanced',     entityType: 'timesheet',   entityId: 'TS-001',            entityDisplayName: 'Kevin Rampersad – Fortnight 17/03/2026',       note: 'Time entries verified in field' },
  { id: 'AUDIT-000007', daysAgo: 14, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'wageRateChanged',   entityType: 'worker',      entityId: 'WRK-001',           entityDisplayName: 'Kevin Rampersad',                                    note: 'Annual collective-agreement increase' },
  { id: 'AUDIT-000008', daysAgo: 10, userId: 'hr-001',    userName: 'HR Officer',           userRole: 'HR Department',        sessionId: 'demo-session-hr-001',    action: 'update',            entityType: 'worker',      entityId: 'WRK-003',           entityDisplayName: 'Andre Williams',                                     note: null },
  { id: 'AUDIT-000009', daysAgo:  7, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'replacementAdded',  entityType: 'worker',      entityId: 'WRK-006',           entityDisplayName: 'Marcia Boodoo (replaced by Patricia Hernandez)',     note: 'Repeated absenteeism and conduct issues' },
  { id: 'AUDIT-000010', daysAgo:  5, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'backpayCalculated', entityType: 'backpay',      entityId: 'BP-2026-001',       entityDisplayName: 'Q1 2026 Backpay – Kevin Rampersad',            note: 'Retroactive to 01/01/2026' },
  { id: 'AUDIT-000011', daysAgo:  3, userId: 'hr-001',    userName: 'HR Officer',           userRole: 'HR Department',        sessionId: 'demo-session-hr-001',    action: 'rosterUpdate',      entityType: 'rosterEntry', entityId: 'ROSTER-2026-04-11', entityDisplayName: 'Chaguanas Borough Corporation – Fortnight 11/04/2026', note: 'Updated absences for fortnight' },
  { id: 'AUDIT-000012', daysAgo:  1, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'export',            entityType: 'timesheet',   entityId: 'BATCH-2026-04',     entityDisplayName: 'Payroll Export – April 2026 (Port of Spain)',  note: '12 timesheets exported to XLSX' },
  { id: 'AUDIT-000013', daysAgo:  1, userId: 'admin',     userName: 'System Administrator', userRole: 'System Admin',         sessionId: 'demo-session-admin',     action: 'paymentRecorded',   entityType: 'payment',     entityId: 'PAY-2026-04-A',     entityDisplayName: 'Direct Deposit Run – Port of Spain (April 2026)', note: '12 workers paid via direct deposit' },
];

const FIELD_CHANGES = {
  'AUDIT-000002': [
    { fieldName: 'Full Name',    oldValue: null,                        newValue: 'Kevin Rampersad' },
    { fieldName: 'NIS Number',   oldValue: null,                        newValue: 'NIS-2024-00147' },
    { fieldName: 'Position',     oldValue: null,                        newValue: 'General Worker' },
    { fieldName: 'Corporation',  oldValue: null,                        newValue: 'Port of Spain City Corporation' },
  ],
  'AUDIT-000003': [
    { fieldName: 'Status', oldValue: 'Missing', newValue: 'Uploaded' },
    { fieldName: 'File',   oldValue: null,      newValue: 'nis_registration.pdf' },
  ],
  'AUDIT-000005': [
    { fieldName: 'Stage',       oldValue: null, newValue: 'Draft' },
    { fieldName: 'Days Worked', oldValue: null, newValue: '10' },
  ],
  'AUDIT-000006': [
    { fieldName: 'Stage', oldValue: 'Submitted', newValue: 'Coordinator Review' },
  ],
  'AUDIT-000007': [
    { fieldName: 'Wage Rate',      oldValue: '140.00', newValue: '150.00' },
    { fieldName: 'Effective From', oldValue: null,     newValue: '2026-01-01' },
  ],
  'AUDIT-000008': [
    { fieldName: 'Phone Number', oldValue: '868-555-0303',             newValue: '868-777-0303' },
    { fieldName: 'Address',      oldValue: '22 Montrose Road, Chaguanas', newValue: '45 Montrose Road, Chaguanas' },
  ],
  'AUDIT-000009': [
    { fieldName: 'Status',             oldValue: 'Active', newValue: 'Inactive' },
    { fieldName: 'Replacement Worker', oldValue: null,     newValue: 'Patricia Hernandez (WRK-011)' },
  ],
  'AUDIT-000010': [
    { fieldName: 'Old Rate',            oldValue: null, newValue: '140.00' },
    { fieldName: 'New Rate',            oldValue: null, newValue: '150.00' },
    { fieldName: 'Fortnights Affected', oldValue: null, newValue: '6' },
    { fieldName: 'Backpay Amount',      oldValue: null, newValue: '600.00' },
  ],
  'AUDIT-000011': [
    { fieldName: 'Andre Williams – Mon 13/04', oldValue: 'Present', newValue: 'Absent' },
    { fieldName: 'Lisa Doodnath – Fri 17/04',  oldValue: 'Present', newValue: 'Absent' },
  ],
};

const ATTACHMENTS = {
  'AUDIT-000013': [
    { id: 'ATT-001', fileName: 'paysheet_pos_april_2026.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', sizeBytes: 24576,  contentHash: 'a4f2b7c91d8e6053e2f471aa9c3d6b8852f1c0d7e6b9a4f3c1d8e6053e2f471aa', uploadedAt: new Date('2026-04-26T12:00:00Z') },
    { id: 'ATT-002', fileName: 'bank_remittance_advice.pdf',   mimeType: 'application/pdf',                                                   sizeBytes: 152432, contentHash: 'b9c3d6f2e1a87045d3c5b9e8f0a172bd5e84c2f9a1b6d307f4e8c2b1d50a9f6e', uploadedAt: new Date('2026-04-26T12:00:00Z') },
  ],
};

// ── Seeder ────────────────────────────────────────────────────────────────────

async function seedAuditLogs(pool) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query("DELETE FROM app_audit_logs WHERE session_id LIKE 'demo-session-%'");

    let prevHash = '';

    for (const entry of ENTRIES) {
      const timestamp    = ts(entry.daysAgo);
      const fieldChanges = FIELD_CHANGES[entry.id] || [];
      const attachments  = ATTACHMENTS[entry.id]   || [];

      const hash = computeHash({
        previousHash: prevHash,
        id:           entry.id,
        timestamp,
        userId:       entry.userId,
        action:       entry.action,
        entityType:   entry.entityType,
        entityId:     entry.entityId,
        fieldChanges,
        attachments,
      });

      await client.query(
        `INSERT INTO app_audit_logs
           (id, timestamp, user_id, user_name, user_role, session_id,
            action, entity_type, entity_id, entity_display_name, note,
            hash, previous_hash)
         VALUES ($1,$2,$3,$4,$5,$6,
                 $7::audit_action_enum,$8::audit_entity_type_enum,
                 $9,$10,$11,$12,$13)`,
        [entry.id, timestamp, entry.userId, entry.userName, entry.userRole,
         entry.sessionId, entry.action, entry.entityType,
         entry.entityId, entry.entityDisplayName, entry.note, hash, prevHash],
      );

      for (let i = 0; i < fieldChanges.length; i++) {
        const f = fieldChanges[i];
        await client.query(
          `INSERT INTO app_audit_field_changes
             (audit_log_id, sequence_no, field_name, old_value, new_value)
           VALUES ($1,$2,$3,$4,$5)`,
          [entry.id, i + 1, f.fieldName, f.oldValue, f.newValue],
        );
      }

      for (const a of attachments) {
        await client.query(
          `INSERT INTO app_audit_attachments
             (id, audit_log_id, file_name, mime_type, size_bytes, content_hash, uploaded_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [a.id, entry.id, a.fileName, a.mimeType, a.sizeBytes, a.contentHash, a.uploadedAt],
        );
      }

      console.log(`[seed] ${entry.id}  ${hash.slice(0, 16)}…`);
      prevHash = hash;
    }

    await client.query('COMMIT');
    console.log(`[seed] audit chain seeded — ${ENTRIES.length} entries`);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { seedAuditLogs };

// ── Standalone entry point ────────────────────────────────────────────────────

if (require.main === module) {
  const { Pool } = require('pg');
  const DATABASE_URL = process.env.DATABASE_URL;
  if (!DATABASE_URL) { console.error('DATABASE_URL must be set'); process.exit(1); }
  const pool = new Pool({ connectionString: DATABASE_URL });
  seedAuditLogs(pool)
    .then(() => pool.end())
    .catch(err => { console.error(err.message); process.exit(1); });
}
