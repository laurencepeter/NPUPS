// ─────────────────────────────────────────────────────────────────────────────
// WorkForce REST API
//
// Bridges the Flutter frontend (lib/services/api_client.dart) with the
// PostgreSQL schemas in db/. JSON shapes match each model's `fromJson` /
// `toJson` exactly — see the corresponding Dart model for the contract.
//
// Run:
//   DATABASE_URL=postgres://workforce:workforce@localhost:5432/workforce \
//   PORT=8080 node index.js
//
// docker-compose.yml in the repo root brings up Postgres + this server with
// the schema and seed data already loaded.
// ─────────────────────────────────────────────────────────────────────────────

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const PORT = parseInt(process.env.PORT || '8080', 10);
const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('FATAL: DATABASE_URL must be set');
  process.exit(1);
}

const pool = new Pool({ connectionString: DATABASE_URL });

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

// ─── Helpers ─────────────────────────────────────────────────────────────────

function asyncRoute(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function isoOrNull(v) {
  return v == null ? null : new Date(v).toISOString();
}

// ─── Health / readiness ──────────────────────────────────────────────────────

app.get('/api/health', asyncRoute(async (req, res) => {
  const { rows } = await pool.query('SELECT 1 AS ok');
  res.json({ ok: rows[0].ok === 1, version: '1.0.0' });
}));

// ─── Workers ─────────────────────────────────────────────────────────────────
// JSON shape mirrors lib/models/worker_model.dart Worker.fromJson.

async function fetchWorkerRow(id) {
  const w = await pool.query(`SELECT * FROM workers WHERE id = $1`, [id]);
  if (w.rowCount === 0) return null;
  const docs = await pool.query(
    `SELECT doc_name AS name, status, file_name, uploaded_at
       FROM worker_documents WHERE worker_id = $1 ORDER BY doc_name`,
    [id]
  );
  const allows = await pool.query(
    `SELECT id, name, rate, per_day_worked, is_active, created_at, note
       FROM worker_allowances WHERE worker_id = $1 ORDER BY created_at`,
    [id]
  );
  return shapeWorker(w.rows[0], docs.rows, allows.rows);
}

function shapeWorker(row, docs, allowances) {
  return {
    id: row.id,
    full_name: row.full_name,
    nis_number: row.nis_number,
    date_of_birth: row.date_of_birth.toISOString(),
    position: row.position,
    id_number: row.id_number,
    corporation_id: row.corporation_id,
    corporation_name: row.corporation_name,
    electoral_district: row.electoral_district,
    wage_rate: Number(row.wage_rate),
    cola_rate: Number(row.cola_rate),
    allowance_rate: Number(row.allowance_rate),
    bank_name: row.bank_name,
    account_number: row.account_number,
    branch_name: row.branch_name,
    documents: docs.map(d => ({
      name: d.name,
      status: d.status,
      file_name: d.file_name,
      uploaded_at: isoOrNull(d.uploaded_at),
    })),
    custom_allowances: allowances.map(a => ({
      id: a.id,
      name: a.name,
      rate: Number(a.rate),
      per_day_worked: a.per_day_worked,
      is_active: a.is_active,
      created_at: a.created_at.toISOString(),
      note: a.note,
    })),
    date_registered: row.date_registered.toISOString(),
    is_active: row.is_active,
    contact: row.contact,
    address: row.address,
    bir_number: row.bir_number,
    driver_permit_number: row.driver_permit_number,
    passport_number: row.passport_number,
    start_date: isoOrNull(row.start_date),
    end_date: isoOrNull(row.end_date),
    reference_number: row.reference_number,
  };
}

app.get('/api/workers', asyncRoute(async (req, res) => {
  const w = await pool.query(`SELECT * FROM workers ORDER BY id`);
  const docs = await pool.query(
    `SELECT worker_id, doc_name AS name, status, file_name, uploaded_at
       FROM worker_documents`);
  const allows = await pool.query(
    `SELECT worker_id, id, name, rate, per_day_worked, is_active, created_at, note
       FROM worker_allowances`);
  const docsByWorker = new Map();
  for (const d of docs.rows) {
    if (!docsByWorker.has(d.worker_id)) docsByWorker.set(d.worker_id, []);
    docsByWorker.get(d.worker_id).push(d);
  }
  const allowsByWorker = new Map();
  for (const a of allows.rows) {
    if (!allowsByWorker.has(a.worker_id)) allowsByWorker.set(a.worker_id, []);
    allowsByWorker.get(a.worker_id).push(a);
  }
  res.json(w.rows.map(r => shapeWorker(
    r, docsByWorker.get(r.id) || [], allowsByWorker.get(r.id) || []
  )));
}));

app.get('/api/workers/:id', asyncRoute(async (req, res) => {
  const w = await fetchWorkerRow(req.params.id);
  if (!w) return res.status(404).json({ error: 'worker not found' });
  res.json(w);
}));

app.post('/api/workers', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO workers (
         id, full_name, nis_number, date_of_birth, position, id_number,
         corporation_id, corporation_name, electoral_district,
         wage_rate, cola_rate, allowance_rate,
         bank_name, account_number, branch_name,
         date_registered, is_active,
         contact, address, bir_number, driver_permit_number, passport_number,
         start_date, end_date, reference_number
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25)`,
      [
        b.id, b.full_name, b.nis_number, b.date_of_birth, b.position, b.id_number,
        b.corporation_id, b.corporation_name, b.electoral_district,
        b.wage_rate, b.cola_rate ?? 0, b.allowance_rate,
        b.bank_name, b.account_number, b.branch_name,
        b.date_registered, b.is_active ?? true,
        b.contact, b.address, b.bir_number, b.driver_permit_number, b.passport_number,
        b.start_date, b.end_date, b.reference_number,
      ]
    );

    // Documents — seed missing rows for all required docs.
    const REQUIRED_DOCS = [
      'NIS Registration', 'Birth Certificate', 'Bank Verification Letter',
      'National ID Card', 'Police Certificate of Good Character',
    ];
    const provided = new Map((b.documents || []).map(d => [d.name, d]));
    for (const name of REQUIRED_DOCS) {
      const d = provided.get(name) || { name, status: 'missing' };
      await client.query(
        `INSERT INTO worker_documents (worker_id, doc_name, status, file_name, uploaded_at)
         VALUES ($1,$2,$3::document_status_enum,$4,$5)
         ON CONFLICT (worker_id, doc_name) DO UPDATE
           SET status = EXCLUDED.status,
               file_name = EXCLUDED.file_name,
               uploaded_at = EXCLUDED.uploaded_at`,
        [b.id, name, d.status || 'missing', d.file_name || null, d.uploaded_at || null]
      );
    }

    // Custom allowances — full replace on create.
    for (const a of (b.custom_allowances || [])) {
      await client.query(
        `INSERT INTO worker_allowances
           (id, worker_id, name, rate, per_day_worked, is_active, note, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [a.id, b.id, a.name, a.rate, a.per_day_worked, a.is_active, a.note,
         a.created_at || new Date().toISOString()]
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  res.status(201).json(await fetchWorkerRow(b.id));
}));

app.patch('/api/workers/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};
  // Only update columns the caller actually included.
  const editable = {
    full_name: b.full_name,
    nis_number: b.nis_number,
    date_of_birth: b.date_of_birth,
    position: b.position,
    id_number: b.id_number,
    corporation_id: b.corporation_id,
    corporation_name: b.corporation_name,
    electoral_district: b.electoral_district,
    wage_rate: b.wage_rate,
    cola_rate: b.cola_rate,
    allowance_rate: b.allowance_rate,
    bank_name: b.bank_name,
    account_number: b.account_number,
    branch_name: b.branch_name,
    is_active: b.is_active,
    contact: b.contact,
    address: b.address,
    bir_number: b.bir_number,
    driver_permit_number: b.driver_permit_number,
    passport_number: b.passport_number,
    start_date: b.start_date,
    end_date: b.end_date,
    reference_number: b.reference_number,
  };
  const cols = Object.keys(editable).filter(k => editable[k] !== undefined);
  if (cols.length === 0) {
    const existing = await fetchWorkerRow(req.params.id);
    if (!existing) return res.status(404).json({ error: 'worker not found' });
    return res.json(existing);
  }
  const sets = cols.map((c, i) => `${c} = $${i + 1}`).join(', ');
  const values = cols.map(c => editable[c]);
  values.push(req.params.id);
  const r = await pool.query(
    `UPDATE workers SET ${sets}, updated_at = NOW() WHERE id = $${values.length}`,
    values
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'worker not found' });
  res.json(await fetchWorkerRow(req.params.id));
}));

app.delete('/api/workers/:id', asyncRoute(async (req, res) => {
  // Soft-delete by deactivating; preserves all FKs (timesheets, audit, etc).
  const r = await pool.query(
    `UPDATE workers SET is_active = FALSE, updated_at = NOW()
       WHERE id = $1`,
    [req.params.id]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'worker not found' });
  res.status(204).end();
}));

// Worker allowances ----------------------------------------------------------

app.post('/api/workers/:id/allowances', asyncRoute(async (req, res) => {
  const a = req.body || {};
  await pool.query(
    `INSERT INTO worker_allowances
       (id, worker_id, name, rate, per_day_worked, is_active, note, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [a.id, req.params.id, a.name, a.rate, a.per_day_worked ?? true,
     a.is_active ?? true, a.note, a.created_at || new Date().toISOString()]
  );
  res.status(201).json(a);
}));

app.patch('/api/worker-allowances/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const editable = {
    name: b.name,
    rate: b.rate,
    per_day_worked: b.per_day_worked,
    is_active: b.is_active,
    note: b.note,
  };
  const cols = Object.keys(editable).filter(k => editable[k] !== undefined);
  if (cols.length === 0) return res.status(204).end();
  const sets = cols.map((c, i) => `${c} = $${i + 1}`).join(', ');
  const values = [...cols.map(c => editable[c]), req.params.id];
  const r = await pool.query(
    `UPDATE worker_allowances SET ${sets} WHERE id = $${values.length}`,
    values
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'allowance not found' });
  res.status(204).end();
}));

app.delete('/api/worker-allowances/:id', asyncRoute(async (req, res) => {
  const r = await pool.query(
    `DELETE FROM worker_allowances WHERE id = $1`, [req.params.id]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'allowance not found' });
  res.status(204).end();
}));

// Worker documents -----------------------------------------------------------

app.put('/api/workers/:id/documents/:name', asyncRoute(async (req, res) => {
  const b = req.body || {};
  await pool.query(
    `INSERT INTO worker_documents (worker_id, doc_name, status, file_name, uploaded_at)
       VALUES ($1,$2,$3::document_status_enum,$4,$5)
       ON CONFLICT (worker_id, doc_name) DO UPDATE
         SET status = EXCLUDED.status,
             file_name = EXCLUDED.file_name,
             uploaded_at = EXCLUDED.uploaded_at`,
    [req.params.id, req.params.name, b.status || 'missing',
     b.file_name || null, b.uploaded_at || null]
  );
  res.status(204).end();
}));

// ─── Worker replacements ─────────────────────────────────────────────────────

app.get('/api/worker-replacements', asyncRoute(async (req, res) => {
  const r = await pool.query(
    `SELECT id, original_worker_id, replacement_worker_id, days_missed,
            reason, replaced_at FROM worker_replacements ORDER BY replaced_at DESC`);
  res.json(r.rows.map(x => ({
    id: x.id,
    original_worker_id: x.original_worker_id,
    replacement_worker_id: x.replacement_worker_id,
    days_missed: x.days_missed,
    reason: x.reason,
    replaced_at: x.replaced_at.toISOString(),
  })));
}));

app.post('/api/worker-replacements', asyncRoute(async (req, res) => {
  const b = req.body || {};
  await pool.query(
    `INSERT INTO worker_replacements
       (id, original_worker_id, replacement_worker_id, days_missed, reason, replaced_at)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (original_worker_id) DO UPDATE
       SET replacement_worker_id = EXCLUDED.replacement_worker_id,
           days_missed = EXCLUDED.days_missed,
           reason = EXCLUDED.reason,
           replaced_at = EXCLUDED.replaced_at`,
    [b.id, b.original_worker_id, b.replacement_worker_id,
     b.days_missed, b.reason, b.replaced_at]
  );
  res.status(201).json(b);
}));

// ─── Timesheets ──────────────────────────────────────────────────────────────

function shapeTimesheet(row, dailyRows, approvalRows) {
  const days = Array.from({ length: 14 }, (_, idx) => {
    const r = dailyRows.find(d => d.day_index === idx);
    return {
      time_in: r?.time_in ? r.time_in.slice(0, 5) : null,
      time_out: r?.time_out ? r.time_out.slice(0, 5) : null,
    };
  });
  return {
    id: row.id,
    worker_id: row.worker_id,
    worker_name: row.worker_name,
    position: row.position,
    id_number: row.id_number,
    nis_number: row.nis_number,
    wage_rate: Number(row.wage_rate),
    cola_rate: Number(row.cola_rate),
    allowance_rate: Number(row.allowance_rate),
    corporation_id: row.corporation_id,
    corporation_name: row.corporation_name,
    electoral_district: row.electoral_district,
    group_number: row.group_number,
    fortnight_start: row.fortnight_start.toISOString(),
    fortnight_end: row.fortnight_end.toISOString(),
    bank_name: row.bank_name,
    account_number: row.account_number,
    branch_name: row.branch_name,
    daily_entries: days,
    allowance_days: row.allowance_days,
    remarks: row.remarks,
    stage: row.stage,
    approval_history: approvalRows.map(a => ({
      reviewer_name: a.reviewer_name,
      reviewer_role: a.reviewer_role,
      state: a.state,
      note: a.note,
      ts: a.ts.toISOString(),
    })),
    created_at: row.created_at.toISOString(),
    updated_at: row.updated_at.toISOString(),
  };
}

app.get('/api/timesheets', asyncRoute(async (req, res) => {
  const ts = await pool.query(`SELECT * FROM timesheets ORDER BY id`);
  const daily = await pool.query(
    `SELECT timesheet_id, day_index,
            to_char(time_in, 'HH24:MI:SS') AS time_in,
            to_char(time_out, 'HH24:MI:SS') AS time_out
       FROM timesheet_daily_entries`);
  const approvals = await pool.query(
    `SELECT timesheet_id, reviewer_name, reviewer_role, state, note, ts, sequence_no
       FROM timesheet_approvals ORDER BY timesheet_id, sequence_no`);
  const dailyByTs = new Map();
  for (const d of daily.rows) {
    if (!dailyByTs.has(d.timesheet_id)) dailyByTs.set(d.timesheet_id, []);
    dailyByTs.get(d.timesheet_id).push(d);
  }
  const approvalsByTs = new Map();
  for (const a of approvals.rows) {
    if (!approvalsByTs.has(a.timesheet_id)) approvalsByTs.set(a.timesheet_id, []);
    approvalsByTs.get(a.timesheet_id).push(a);
  }
  res.json(ts.rows.map(r => shapeTimesheet(
    r, dailyByTs.get(r.id) || [], approvalsByTs.get(r.id) || []
  )));
}));

async function fetchTimesheet(id) {
  const ts = await pool.query(`SELECT * FROM timesheets WHERE id = $1`, [id]);
  if (ts.rowCount === 0) return null;
  const daily = await pool.query(
    `SELECT day_index,
            to_char(time_in, 'HH24:MI:SS') AS time_in,
            to_char(time_out, 'HH24:MI:SS') AS time_out
       FROM timesheet_daily_entries WHERE timesheet_id = $1`, [id]);
  const approvals = await pool.query(
    `SELECT reviewer_name, reviewer_role, state, note, ts, sequence_no
       FROM timesheet_approvals WHERE timesheet_id = $1 ORDER BY sequence_no`, [id]);
  return shapeTimesheet(ts.rows[0], daily.rows, approvals.rows);
}

app.post('/api/timesheets', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO timesheets (
         id, worker_id, worker_name, position, id_number, nis_number,
         wage_rate, cola_rate, allowance_rate,
         corporation_id, corporation_name, electoral_district, group_number,
         fortnight_start, fortnight_end,
         bank_name, account_number, branch_name,
         allowance_days, remarks, stage, created_at, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21::timesheet_stage_enum,$22,$23)`,
      [
        b.id, b.worker_id, b.worker_name, b.position, b.id_number, b.nis_number,
        b.wage_rate, b.cola_rate ?? 0, b.allowance_rate,
        b.corporation_id, b.corporation_name, b.electoral_district, b.group_number,
        b.fortnight_start, b.fortnight_end,
        b.bank_name, b.account_number, b.branch_name,
        b.allowance_days ?? 0, b.remarks ?? '', b.stage || 'notStarted',
        b.created_at || new Date().toISOString(), b.updated_at || new Date().toISOString(),
      ]
    );
    const entries = b.daily_entries || [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      await client.query(
        `INSERT INTO timesheet_daily_entries (timesheet_id, day_index, time_in, time_out)
         VALUES ($1,$2,$3,$4)`,
        [b.id, i, e.time_in || null, e.time_out || null]
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  res.status(201).json(await fetchTimesheet(b.id));
}));

app.patch('/api/timesheets/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (b.stage || b.allowance_days !== undefined || b.remarks !== undefined) {
      const cols = [];
      const vals = [];
      if (b.stage) { cols.push(`stage = $${cols.length + 1}::timesheet_stage_enum`); vals.push(b.stage); }
      if (b.allowance_days !== undefined) { cols.push(`allowance_days = $${cols.length + 1}`); vals.push(b.allowance_days); }
      if (b.remarks !== undefined) { cols.push(`remarks = $${cols.length + 1}`); vals.push(b.remarks); }
      cols.push(`updated_at = NOW()`);
      vals.push(req.params.id);
      const sql = `UPDATE timesheets SET ${cols.join(', ')} WHERE id = $${vals.length}`;
      const r = await client.query(sql, vals);
      if (r.rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'timesheet not found' });
      }
    }
    if (Array.isArray(b.daily_entries)) {
      for (let i = 0; i < b.daily_entries.length; i++) {
        const e = b.daily_entries[i];
        await client.query(
          `INSERT INTO timesheet_daily_entries (timesheet_id, day_index, time_in, time_out)
           VALUES ($1,$2,$3,$4)
           ON CONFLICT (timesheet_id, day_index) DO UPDATE
             SET time_in = EXCLUDED.time_in, time_out = EXCLUDED.time_out`,
          [req.params.id, i, e.time_in || null, e.time_out || null]
        );
      }
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  res.json(await fetchTimesheet(req.params.id));
}));

app.post('/api/timesheets/:id/approvals', asyncRoute(async (req, res) => {
  const a = req.body || {};
  const seqRow = await pool.query(
    `SELECT COALESCE(MAX(sequence_no), 0) + 1 AS next FROM timesheet_approvals WHERE timesheet_id = $1`,
    [req.params.id]
  );
  const seq = seqRow.rows[0].next;
  await pool.query(
    `INSERT INTO timesheet_approvals
       (timesheet_id, sequence_no, reviewer_name, reviewer_role, state, note, ts)
     VALUES ($1,$2,$3,$4,$5::approval_state_enum,$6,$7)`,
    [req.params.id, seq, a.reviewer_name, a.reviewer_role,
     a.state || 'approved', a.note, a.ts || new Date().toISOString()]
  );
  res.status(201).json({ ...a, sequence_no: seq });
}));

// ─── Audit log ───────────────────────────────────────────────────────────────

app.get('/api/audit-logs', asyncRoute(async (req, res) => {
  const logs = await pool.query(
    `SELECT * FROM app_audit_logs ORDER BY sequence_no`);
  const fields = await pool.query(
    `SELECT audit_log_id, sequence_no, field_name, old_value, new_value
       FROM app_audit_field_changes ORDER BY audit_log_id, sequence_no`);
  const atts = await pool.query(
    `SELECT audit_log_id, id, file_name, mime_type, size_bytes, content_hash, uploaded_at
       FROM app_audit_attachments`);
  const fByLog = new Map();
  for (const f of fields.rows) {
    if (!fByLog.has(f.audit_log_id)) fByLog.set(f.audit_log_id, []);
    fByLog.get(f.audit_log_id).push(f);
  }
  const aByLog = new Map();
  for (const a of atts.rows) {
    if (!aByLog.has(a.audit_log_id)) aByLog.set(a.audit_log_id, []);
    aByLog.get(a.audit_log_id).push(a);
  }
  res.json(logs.rows.map(r => ({
    id: r.id,
    timestamp: r.timestamp.toISOString(),
    user_id: r.user_id,
    user_name: r.user_name,
    user_role: r.user_role,
    session_id: r.session_id,
    action: r.action,
    entity_type: r.entity_type,
    entity_id: r.entity_id,
    entity_display_name: r.entity_display_name,
    field_changes: (fByLog.get(r.id) || []).map(f => ({
      field_name: f.field_name,
      old_value: f.old_value,
      new_value: f.new_value,
    })),
    attachments: (aByLog.get(r.id) || []).map(a => ({
      id: a.id,
      file_name: a.file_name,
      mime_type: a.mime_type,
      size_bytes: Number(a.size_bytes),
      content_hash: a.content_hash,
      uploaded_at: a.uploaded_at.toISOString(),
    })),
    note: r.note,
    actor_context: r.actor_context,
    hash: r.hash,
    previous_hash: r.previous_hash,
  })));
}));

app.post('/api/audit-logs', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO app_audit_logs (
         id, timestamp, user_id, user_name, user_role, session_id,
         action, entity_type, entity_id, entity_display_name,
         note, actor_context, hash, previous_hash
       ) VALUES ($1,$2,$3,$4,$5,$6,$7::audit_action_enum,$8::audit_entity_type_enum,$9,$10,$11,$12,$13,$14)`,
      [b.id, b.timestamp, b.user_id, b.user_name, b.user_role, b.session_id,
       b.action, b.entity_type, b.entity_id, b.entity_display_name,
       b.note, b.actor_context, b.hash, b.previous_hash || '']
    );
    const fcs = b.field_changes || [];
    for (let i = 0; i < fcs.length; i++) {
      await client.query(
        `INSERT INTO app_audit_field_changes
           (audit_log_id, sequence_no, field_name, old_value, new_value)
         VALUES ($1,$2,$3,$4,$5)`,
        [b.id, i + 1, fcs[i].field_name, fcs[i].old_value, fcs[i].new_value]
      );
    }
    const atts = b.attachments || [];
    for (const a of atts) {
      await client.query(
        `INSERT INTO app_audit_attachments
           (id, audit_log_id, file_name, mime_type, size_bytes, content_hash, uploaded_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [a.id, b.id, a.file_name, a.mime_type, a.size_bytes, a.content_hash, a.uploaded_at]
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  res.status(201).json(b);
}));

// ─── Roster settings + Rosters ───────────────────────────────────────────────

app.get('/api/roster-settings', asyncRoute(async (req, res) => {
  const r = await pool.query(
    `SELECT corporation_id, max_days_per_fortnight, allow_weekend_work,
            allow_max_days_override, data_entry_can_override
       FROM roster_settings`);
  res.json(r.rows);
}));

app.patch('/api/roster-settings/:corporationId', asyncRoute(async (req, res) => {
  const b = req.body || {};
  await pool.query(
    `INSERT INTO roster_settings (
       corporation_id, max_days_per_fortnight, allow_weekend_work,
       allow_max_days_override, data_entry_can_override, updated_at
     ) VALUES ($1,$2,$3,$4,$5, NOW())
     ON CONFLICT (corporation_id) DO UPDATE SET
       max_days_per_fortnight = EXCLUDED.max_days_per_fortnight,
       allow_weekend_work = EXCLUDED.allow_weekend_work,
       allow_max_days_override = EXCLUDED.allow_max_days_override,
       data_entry_can_override = EXCLUDED.data_entry_can_override,
       updated_at = NOW()`,
    [req.params.corporationId,
     b.max_days_per_fortnight ?? 10,
     b.allow_weekend_work ?? false,
     b.allow_max_days_override ?? true,
     b.data_entry_can_override ?? false]
  );
  res.status(204).end();
}));

app.get('/api/rosters', asyncRoute(async (req, res) => {
  const rosters = await pool.query(
    `SELECT * FROM rosters ORDER BY fortnight_start DESC, corporation_id`);
  const recs = await pool.query(
    `SELECT rwr.roster_id, rwr.worker_id, w.full_name AS worker_name,
            w.position, w.corporation_id, rwr.max_days_override, rwr.notes
       FROM roster_worker_records rwr
       JOIN workers w ON w.id = rwr.worker_id`);
  const days = await pool.query(
    `SELECT roster_id, worker_id, day_index, entry_date, is_present, absence_reason
       FROM roster_day_entries`);
  const recsByRoster = new Map();
  for (const r of recs.rows) {
    if (!recsByRoster.has(r.roster_id)) recsByRoster.set(r.roster_id, []);
    recsByRoster.get(r.roster_id).push(r);
  }
  const daysByKey = new Map();
  for (const d of days.rows) {
    const k = `${d.roster_id}|${d.worker_id}`;
    if (!daysByKey.has(k)) daysByKey.set(k, []);
    daysByKey.get(k).push(d);
  }
  res.json(rosters.rows.map(r => ({
    id: r.id,
    corporation_id: r.corporation_id,
    corporation_name: r.corporation_name,
    fortnight_start: r.fortnight_start.toISOString(),
    fortnight_end: r.fortnight_end.toISOString(),
    last_modified: r.last_modified.toISOString(),
    last_modified_by: r.last_modified_by,
    worker_records: (recsByRoster.get(r.id) || []).map(rec => {
      const ds = (daysByKey.get(`${r.id}|${rec.worker_id}`) || [])
        .sort((a, b) => a.day_index - b.day_index);
      return {
        worker_id: rec.worker_id,
        worker_name: rec.worker_name,
        position: rec.position,
        corporation_id: rec.corporation_id,
        max_days_override: rec.max_days_override,
        notes: rec.notes,
        days: ds.map(d => ({
          entry_date: d.entry_date.toISOString(),
          is_present: d.is_present,
          absence_reason: d.absence_reason,
        })),
      };
    }),
  })));
}));

app.put('/api/rosters/:rosterId/workers/:workerId/days/:dayIndex',
  asyncRoute(async (req, res) => {
    const b = req.body || {};
    await pool.query(
      `UPDATE roster_day_entries
          SET is_present = $1,
              absence_reason = $2
        WHERE roster_id = $3 AND worker_id = $4 AND day_index = $5`,
      [b.is_present, b.absence_reason || null,
       req.params.rosterId, req.params.workerId, parseInt(req.params.dayIndex, 10)]
    );
    await pool.query(
      `UPDATE rosters SET last_modified = NOW(), last_modified_by = $1
         WHERE id = $2`,
      [b.modified_by || null, req.params.rosterId]
    );
    res.status(204).end();
  })
);

// ─── Backpay ─────────────────────────────────────────────────────────────────

app.get('/api/backpay-records', asyncRoute(async (req, res) => {
  const recs = await pool.query(
    `SELECT * FROM backpay_records ORDER BY calculated_at DESC`);
  const lines = await pool.query(
    `SELECT backpay_record_id, timesheet_id, fortnight_start, days_worked,
            old_daily_rate, new_daily_rate, old_cola_rate, new_cola_rate
       FROM backpay_line_items`);
  const linesByRec = new Map();
  for (const l of lines.rows) {
    if (!linesByRec.has(l.backpay_record_id)) linesByRec.set(l.backpay_record_id, []);
    linesByRec.get(l.backpay_record_id).push(l);
  }
  res.json(recs.rows.map(r => ({
    id: r.id,
    worker_id: r.worker_id,
    worker_name: r.worker_name,
    corporation_id: r.corporation_id,
    corporation_name: r.corporation_name,
    effective_from: r.effective_from.toISOString(),
    old_wage_rate: Number(r.old_wage_rate),
    new_wage_rate: Number(r.new_wage_rate),
    old_cola_rate: Number(r.old_cola_rate),
    new_cola_rate: Number(r.new_cola_rate),
    line_items: (linesByRec.get(r.id) || []).map(l => ({
      timesheet_id: l.timesheet_id,
      fortnight_start: l.fortnight_start.toISOString(),
      days_worked: l.days_worked,
      old_daily_rate: Number(l.old_daily_rate),
      new_daily_rate: Number(l.new_daily_rate),
      old_cola_rate: Number(l.old_cola_rate),
      new_cola_rate: Number(l.new_cola_rate),
    })),
    status: r.status,
    calculated_at: r.calculated_at.toISOString(),
    calculated_by_user_id: r.calculated_by_user_id,
    note: r.note,
  })));
}));

app.post('/api/backpay-records', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO backpay_records (
         id, worker_id, worker_name, corporation_id, corporation_name,
         effective_from, old_wage_rate, new_wage_rate, old_cola_rate, new_cola_rate,
         status, note, calculated_at, calculated_by_user_id
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::backpay_status_enum,$12,$13,$14)`,
      [b.id, b.worker_id, b.worker_name, b.corporation_id, b.corporation_name,
       b.effective_from, b.old_wage_rate, b.new_wage_rate,
       b.old_cola_rate, b.new_cola_rate,
       b.status || 'calculated', b.note, b.calculated_at, b.calculated_by_user_id]
    );
    for (const l of (b.line_items || [])) {
      await client.query(
        `INSERT INTO backpay_line_items
           (backpay_record_id, timesheet_id, fortnight_start, days_worked,
            old_daily_rate, new_daily_rate, old_cola_rate, new_cola_rate)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [b.id, l.timesheet_id, l.fortnight_start, l.days_worked,
         l.old_daily_rate, l.new_daily_rate, l.old_cola_rate, l.new_cola_rate]
      );
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
  res.status(201).json(b);
}));

app.patch('/api/backpay-records/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!b.status) return res.status(400).json({ error: 'status required' });
  const r = await pool.query(
    `UPDATE backpay_records SET status = $1::backpay_status_enum WHERE id = $2`,
    [b.status, req.params.id]
  );
  if (r.rowCount === 0) return res.status(404).json({ error: 'backpay record not found' });
  res.status(204).end();
}));

// ─── Error handler ───────────────────────────────────────────────────────────

app.use((err, req, res, next) => {
  console.error(`[error] ${req.method} ${req.path}:`, err);
  res.status(500).json({
    error: err.message || 'internal error',
    path: req.path,
  });
});

// ─── Boot ────────────────────────────────────────────────────────────────────

app.listen(PORT, () => {
  console.log(`workforce-api listening on :${PORT}`);
});
