// ─────────────────────────────────────────────────────────────────────────────
// WorkForce REST API — backed by Supabase
//
// Run:
//   SUPABASE_URL=https://supabase.fireydev.com \
//   SUPABASE_ANON_KEY=eyJ... \
//   PORT=8080 node index.js
// ─────────────────────────────────────────────────────────────────────────────

const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');

const PORT = parseInt(process.env.PORT || '8080', 10);
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('FATAL: SUPABASE_URL and SUPABASE_ANON_KEY must be set');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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
//
// Two distinct checks, on purpose:
//
//   /api/health  — LIVENESS. Answers "is this process up and accepting
//                  connections?" and nothing more. It must NOT touch Supabase
//                  or any other external dependency: the container healthcheck
//                  (docker-compose.prod.yml) polls this, and if it depended on
//                  Supabase, any Supabase slowness/outage would make Docker
//                  mark the container unhealthy and Coolify would restart-loop
//                  it — even though Express is fine. Returns 200 instantly.
//
//   /api/ready   — READINESS. Answers "can I actually reach Supabase right
//                  now?". Used for debugging/observability, NOT by the
//                  container healthcheck. Bounded by a short timeout so a
//                  hung/unreachable Supabase host can never make this request
//                  hang either.

app.get('/api/health', (req, res) => {
  res.json({ ok: true, version: '1.0.0' });
});

app.get('/api/ready', asyncRoute(async (req, res) => {
  const TIMEOUT_MS = 3000;
  const probe = supabase.from('workers').select('id').limit(1);
  const timeout = new Promise((_, reject) =>
    setTimeout(() => reject(new Error('supabase probe timed out')), TIMEOUT_MS),
  );
  try {
    const { error } = await Promise.race([probe, timeout]);
    if (error) {
      return res.status(503).json({ ok: false, supabase: 'error', detail: error.message });
    }
    res.json({ ok: true, supabase: 'reachable', version: '1.0.0' });
  } catch (e) {
    res.status(503).json({ ok: false, supabase: 'unreachable', detail: e.message });
  }
}));

// ─── Workers ─────────────────────────────────────────────────────────────────
// JSON shape mirrors lib/models/worker_model.dart Worker.fromJson.

async function fetchWorkerRow(id) {
  const { data: wRow, error: wErr } = await supabase.from('workers').select('*').eq('id', id).single();
  if (wErr || !wRow) return null;
  const { data: docs } = await supabase
    .from('worker_documents')
    .select('doc_name, status, file_name, uploaded_at')
    .eq('worker_id', id)
    .order('doc_name');
  const { data: allows } = await supabase
    .from('worker_allowances')
    .select('id, name, rate, per_day_worked, is_active, created_at, note')
    .eq('worker_id', id)
    .order('created_at');
  return shapeWorker(wRow, docs || [], allows || []);
}

function shapeWorker(row, docs, allowances) {
  return {
    id: row.id,
    full_name: row.full_name,
    nis_number: row.nis_number,
    date_of_birth: new Date(row.date_of_birth).toISOString(),
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
      name: d.doc_name,
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
      created_at: new Date(a.created_at).toISOString(),
      note: a.note,
    })),
    date_registered: new Date(row.date_registered).toISOString(),
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
  const { data: wRows, error: wErr } = await supabase.from('workers').select('*').order('id');
  if (wErr) throw new Error(wErr.message);
  const { data: docs } = await supabase
    .from('worker_documents')
    .select('worker_id, doc_name, status, file_name, uploaded_at');
  const { data: allows } = await supabase
    .from('worker_allowances')
    .select('worker_id, id, name, rate, per_day_worked, is_active, created_at, note');
  const docsByWorker = new Map();
  for (const d of (docs || [])) {
    if (!docsByWorker.has(d.worker_id)) docsByWorker.set(d.worker_id, []);
    docsByWorker.get(d.worker_id).push(d);
  }
  const allowsByWorker = new Map();
  for (const a of (allows || [])) {
    if (!allowsByWorker.has(a.worker_id)) allowsByWorker.set(a.worker_id, []);
    allowsByWorker.get(a.worker_id).push(a);
  }
  res.json((wRows || []).map(r => shapeWorker(
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

  const { error: wErr } = await supabase.from('workers').insert({
    id: b.id,
    full_name: b.full_name,
    nis_number: b.nis_number,
    date_of_birth: b.date_of_birth,
    position: b.position,
    id_number: b.id_number,
    corporation_id: b.corporation_id,
    corporation_name: b.corporation_name,
    electoral_district: b.electoral_district,
    wage_rate: b.wage_rate,
    cola_rate: b.cola_rate ?? 0,
    allowance_rate: b.allowance_rate,
    bank_name: b.bank_name,
    account_number: b.account_number,
    branch_name: b.branch_name,
    date_registered: b.date_registered,
    is_active: b.is_active ?? true,
    contact: b.contact,
    address: b.address,
    bir_number: b.bir_number,
    driver_permit_number: b.driver_permit_number,
    passport_number: b.passport_number,
    start_date: b.start_date,
    end_date: b.end_date,
    reference_number: b.reference_number,
  });
  if (wErr) throw new Error(wErr.message);

  // Documents — seed missing rows for all required docs.
  const REQUIRED_DOCS = [
    'NIS Registration', 'Birth Certificate', 'Bank Verification Letter',
    'National ID Card', 'Police Certificate of Good Character',
  ];
  const provided = new Map((b.documents || []).map(d => [d.name, d]));
  for (const name of REQUIRED_DOCS) {
    const d = provided.get(name) || { name, status: 'missing' };
    const { error: docErr } = await supabase.from('worker_documents').upsert(
      {
        worker_id: b.id,
        doc_name: name,
        status: d.status || 'missing',
        file_name: d.file_name || null,
        uploaded_at: d.uploaded_at || null,
      },
      { onConflict: 'worker_id,doc_name' }
    );
    if (docErr) throw new Error(docErr.message);
  }

  // Custom allowances — full replace on create.
  for (const a of (b.custom_allowances || [])) {
    const { error: aErr } = await supabase.from('worker_allowances').insert({
      id: a.id,
      worker_id: b.id,
      name: a.name,
      rate: a.rate,
      per_day_worked: a.per_day_worked,
      is_active: a.is_active,
      note: a.note,
      created_at: a.created_at || new Date().toISOString(),
    });
    if (aErr) throw new Error(aErr.message);
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
  const updateObj = {};
  cols.forEach(c => { updateObj[c] = editable[c]; });
  updateObj.updated_at = new Date().toISOString();
  const { data, error } = await supabase
    .from('workers')
    .update(updateObj)
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'worker not found' });
  res.json(await fetchWorkerRow(req.params.id));
}));

app.delete('/api/workers/:id', asyncRoute(async (req, res) => {
  // Soft-delete by deactivating; preserves all FKs (timesheets, audit, etc).
  const { data, error } = await supabase
    .from('workers')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'worker not found' });
  res.status(204).end();
}));

// Worker allowances ----------------------------------------------------------

app.post('/api/workers/:id/allowances', asyncRoute(async (req, res) => {
  const a = req.body || {};
  const { error } = await supabase.from('worker_allowances').insert({
    id: a.id,
    worker_id: req.params.id,
    name: a.name,
    rate: a.rate,
    per_day_worked: a.per_day_worked ?? true,
    is_active: a.is_active ?? true,
    note: a.note,
    created_at: a.created_at || new Date().toISOString(),
  });
  if (error) throw new Error(error.message);
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
  const updateObj = {};
  cols.forEach(c => { updateObj[c] = editable[c]; });
  const { data, error } = await supabase
    .from('worker_allowances')
    .update(updateObj)
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'allowance not found' });
  res.status(204).end();
}));

app.delete('/api/worker-allowances/:id', asyncRoute(async (req, res) => {
  const { data, error } = await supabase
    .from('worker_allowances')
    .delete()
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'allowance not found' });
  res.status(204).end();
}));

// Worker documents -----------------------------------------------------------

app.put('/api/workers/:id/documents/:name', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const { error } = await supabase.from('worker_documents').upsert(
    {
      worker_id: req.params.id,
      doc_name: req.params.name,
      status: b.status || 'missing',
      file_name: b.file_name || null,
      uploaded_at: b.uploaded_at || null,
    },
    { onConflict: 'worker_id,doc_name' }
  );
  if (error) throw new Error(error.message);
  res.status(204).end();
}));

// ─── Worker replacements ─────────────────────────────────────────────────────

app.get('/api/worker-replacements', asyncRoute(async (req, res) => {
  const { data, error } = await supabase
    .from('worker_replacements')
    .select('id, original_worker_id, replacement_worker_id, days_missed, reason, replaced_at')
    .order('replaced_at', { ascending: false });
  if (error) throw new Error(error.message);
  res.json((data || []).map(x => ({
    id: x.id,
    original_worker_id: x.original_worker_id,
    replacement_worker_id: x.replacement_worker_id,
    days_missed: x.days_missed,
    reason: x.reason,
    replaced_at: new Date(x.replaced_at).toISOString(),
  })));
}));

app.post('/api/worker-replacements', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const { error } = await supabase.from('worker_replacements').upsert(
    {
      id: b.id,
      original_worker_id: b.original_worker_id,
      replacement_worker_id: b.replacement_worker_id,
      days_missed: b.days_missed,
      reason: b.reason,
      replaced_at: b.replaced_at,
    },
    { onConflict: 'original_worker_id' }
  );
  if (error) throw new Error(error.message);
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
    fortnight_start: new Date(row.fortnight_start).toISOString(),
    fortnight_end: new Date(row.fortnight_end).toISOString(),
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
      ts: new Date(a.ts).toISOString(),
    })),
    created_at: new Date(row.created_at).toISOString(),
    updated_at: new Date(row.updated_at).toISOString(),
  };
}

app.get('/api/timesheets', asyncRoute(async (req, res) => {
  const { data: tsRows, error: tsErr } = await supabase.from('timesheets').select('*').order('id');
  if (tsErr) throw new Error(tsErr.message);
  const { data: daily } = await supabase
    .from('timesheet_daily_entries')
    .select('timesheet_id, day_index, time_in, time_out');
  const { data: approvals } = await supabase
    .from('timesheet_approvals')
    .select('timesheet_id, reviewer_name, reviewer_role, state, note, ts, sequence_no')
    .order('timesheet_id')
    .order('sequence_no');
  const dailyByTs = new Map();
  for (const d of (daily || [])) {
    if (!dailyByTs.has(d.timesheet_id)) dailyByTs.set(d.timesheet_id, []);
    dailyByTs.get(d.timesheet_id).push(d);
  }
  const approvalsByTs = new Map();
  for (const a of (approvals || [])) {
    if (!approvalsByTs.has(a.timesheet_id)) approvalsByTs.set(a.timesheet_id, []);
    approvalsByTs.get(a.timesheet_id).push(a);
  }
  res.json((tsRows || []).map(r => shapeTimesheet(
    r, dailyByTs.get(r.id) || [], approvalsByTs.get(r.id) || []
  )));
}));

async function fetchTimesheet(id) {
  const { data: tsRow, error: tsErr } = await supabase.from('timesheets').select('*').eq('id', id).single();
  if (tsErr || !tsRow) return null;
  const { data: daily } = await supabase
    .from('timesheet_daily_entries')
    .select('day_index, time_in, time_out')
    .eq('timesheet_id', id);
  const { data: approvals } = await supabase
    .from('timesheet_approvals')
    .select('reviewer_name, reviewer_role, state, note, ts, sequence_no')
    .eq('timesheet_id', id)
    .order('sequence_no');
  return shapeTimesheet(tsRow, daily || [], approvals || []);
}

app.post('/api/timesheets', asyncRoute(async (req, res) => {
  const b = req.body || {};

  const { error: tsErr } = await supabase.from('timesheets').insert({
    id: b.id,
    worker_id: b.worker_id,
    worker_name: b.worker_name,
    position: b.position,
    id_number: b.id_number,
    nis_number: b.nis_number,
    wage_rate: b.wage_rate,
    cola_rate: b.cola_rate ?? 0,
    allowance_rate: b.allowance_rate,
    corporation_id: b.corporation_id,
    corporation_name: b.corporation_name,
    electoral_district: b.electoral_district,
    group_number: b.group_number,
    fortnight_start: b.fortnight_start,
    fortnight_end: b.fortnight_end,
    bank_name: b.bank_name,
    account_number: b.account_number,
    branch_name: b.branch_name,
    allowance_days: b.allowance_days ?? 0,
    remarks: b.remarks ?? '',
    stage: b.stage || 'notStarted',
    created_at: b.created_at || new Date().toISOString(),
    updated_at: b.updated_at || new Date().toISOString(),
  });
  if (tsErr) throw new Error(tsErr.message);

  const entries = b.daily_entries || [];
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    const { error: eErr } = await supabase.from('timesheet_daily_entries').insert({
      timesheet_id: b.id,
      day_index: i,
      time_in: e.time_in || null,
      time_out: e.time_out || null,
    });
    if (eErr) throw new Error(eErr.message);
  }

  res.status(201).json(await fetchTimesheet(b.id));
}));

app.patch('/api/timesheets/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};

  if (b.stage || b.allowance_days !== undefined || b.remarks !== undefined) {
    const updateObj = { updated_at: new Date().toISOString() };
    if (b.stage !== undefined) updateObj.stage = b.stage;
    if (b.allowance_days !== undefined) updateObj.allowance_days = b.allowance_days;
    if (b.remarks !== undefined) updateObj.remarks = b.remarks;
    const { data, error } = await supabase
      .from('timesheets')
      .update(updateObj)
      .eq('id', req.params.id)
      .select()
      .single();
    if (error || !data) return res.status(404).json({ error: 'timesheet not found' });
  }

  if (Array.isArray(b.daily_entries)) {
    for (let i = 0; i < b.daily_entries.length; i++) {
      const e = b.daily_entries[i];
      const { error: eErr } = await supabase.from('timesheet_daily_entries').upsert(
        {
          timesheet_id: req.params.id,
          day_index: i,
          time_in: e.time_in || null,
          time_out: e.time_out || null,
        },
        { onConflict: 'timesheet_id,day_index' }
      );
      if (eErr) throw new Error(eErr.message);
    }
  }

  res.json(await fetchTimesheet(req.params.id));
}));

app.post('/api/timesheets/:id/approvals', asyncRoute(async (req, res) => {
  const a = req.body || {};
  const { data: seqData } = await supabase
    .from('timesheet_approvals')
    .select('sequence_no')
    .eq('timesheet_id', req.params.id)
    .order('sequence_no', { ascending: false })
    .limit(1);
  const seq = seqData && seqData.length > 0 ? seqData[0].sequence_no + 1 : 1;
  const { error } = await supabase.from('timesheet_approvals').insert({
    timesheet_id: req.params.id,
    sequence_no: seq,
    reviewer_name: a.reviewer_name,
    reviewer_role: a.reviewer_role,
    state: a.state || 'approved',
    note: a.note,
    ts: a.ts || new Date().toISOString(),
  });
  if (error) throw new Error(error.message);
  res.status(201).json({ ...a, sequence_no: seq });
}));

// ─── Audit log ───────────────────────────────────────────────────────────────

app.get('/api/audit-logs', asyncRoute(async (req, res) => {
  const { data: logs, error: lErr } = await supabase
    .from('app_audit_logs')
    .select('*')
    .order('sequence_no');
  if (lErr) throw new Error(lErr.message);
  const { data: fields } = await supabase
    .from('app_audit_field_changes')
    .select('audit_log_id, sequence_no, field_name, old_value, new_value')
    .order('audit_log_id')
    .order('sequence_no');
  const { data: atts } = await supabase
    .from('app_audit_attachments')
    .select('audit_log_id, id, file_name, mime_type, size_bytes, content_hash, uploaded_at');
  const fByLog = new Map();
  for (const f of (fields || [])) {
    if (!fByLog.has(f.audit_log_id)) fByLog.set(f.audit_log_id, []);
    fByLog.get(f.audit_log_id).push(f);
  }
  const aByLog = new Map();
  for (const a of (atts || [])) {
    if (!aByLog.has(a.audit_log_id)) aByLog.set(a.audit_log_id, []);
    aByLog.get(a.audit_log_id).push(a);
  }
  res.json((logs || []).map(r => ({
    id: r.id,
    timestamp: new Date(r.timestamp).toISOString(),
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
      uploaded_at: new Date(a.uploaded_at).toISOString(),
    })),
    note: r.note,
    actor_context: r.actor_context,
    hash: r.hash,
    previous_hash: r.previous_hash,
  })));
}));

app.post('/api/audit-logs', asyncRoute(async (req, res) => {
  const b = req.body || {};

  const { error: lErr } = await supabase.from('app_audit_logs').insert({
    id: b.id,
    timestamp: b.timestamp,
    user_id: b.user_id,
    user_name: b.user_name,
    user_role: b.user_role,
    session_id: b.session_id,
    action: b.action,
    entity_type: b.entity_type,
    entity_id: b.entity_id,
    entity_display_name: b.entity_display_name,
    note: b.note,
    actor_context: b.actor_context,
    hash: b.hash,
    previous_hash: b.previous_hash || '',
  });
  if (lErr) throw new Error(lErr.message);

  const fcs = b.field_changes || [];
  for (let i = 0; i < fcs.length; i++) {
    const { error: fcErr } = await supabase.from('app_audit_field_changes').insert({
      audit_log_id: b.id,
      sequence_no: i + 1,
      field_name: fcs[i].field_name,
      old_value: fcs[i].old_value,
      new_value: fcs[i].new_value,
    });
    if (fcErr) throw new Error(fcErr.message);
  }

  const attachments = b.attachments || [];
  for (const a of attachments) {
    const { error: attErr } = await supabase.from('app_audit_attachments').insert({
      id: a.id,
      audit_log_id: b.id,
      file_name: a.file_name,
      mime_type: a.mime_type,
      size_bytes: a.size_bytes,
      content_hash: a.content_hash,
      uploaded_at: a.uploaded_at,
    });
    if (attErr) throw new Error(attErr.message);
  }

  res.status(201).json(b);
}));

// ─── Roster settings + Rosters ───────────────────────────────────────────────

app.get('/api/roster-settings', asyncRoute(async (req, res) => {
  const { data, error } = await supabase
    .from('roster_settings')
    .select('corporation_id, max_days_per_fortnight, allow_weekend_work, allow_max_days_override, data_entry_can_override');
  if (error) throw new Error(error.message);
  res.json(data || []);
}));

app.patch('/api/roster-settings/:corporationId', asyncRoute(async (req, res) => {
  const b = req.body || {};
  const { error } = await supabase.from('roster_settings').upsert(
    {
      corporation_id: req.params.corporationId,
      max_days_per_fortnight: b.max_days_per_fortnight ?? 10,
      allow_weekend_work: b.allow_weekend_work ?? false,
      allow_max_days_override: b.allow_max_days_override ?? true,
      data_entry_can_override: b.data_entry_can_override ?? false,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'corporation_id' }
  );
  if (error) throw new Error(error.message);
  res.status(204).end();
}));

app.get('/api/rosters', asyncRoute(async (req, res) => {
  const { data: rosters, error: rErr } = await supabase
    .from('rosters')
    .select('*')
    .order('fortnight_start', { ascending: false })
    .order('corporation_id');
  if (rErr) throw new Error(rErr.message);
  const { data: recs } = await supabase
    .from('roster_worker_records')
    .select('roster_id, worker_id, max_days_override, notes, workers(full_name, position, corporation_id)');
  const { data: days } = await supabase
    .from('roster_day_entries')
    .select('roster_id, worker_id, day_index, entry_date, is_present, absence_reason');
  const recsByRoster = new Map();
  for (const r of (recs || [])) {
    if (!recsByRoster.has(r.roster_id)) recsByRoster.set(r.roster_id, []);
    recsByRoster.get(r.roster_id).push(r);
  }
  const daysByKey = new Map();
  for (const d of (days || [])) {
    const k = `${d.roster_id}|${d.worker_id}`;
    if (!daysByKey.has(k)) daysByKey.set(k, []);
    daysByKey.get(k).push(d);
  }
  res.json((rosters || []).map(r => ({
    id: r.id,
    corporation_id: r.corporation_id,
    corporation_name: r.corporation_name,
    fortnight_start: new Date(r.fortnight_start).toISOString(),
    fortnight_end: new Date(r.fortnight_end).toISOString(),
    last_modified: new Date(r.last_modified).toISOString(),
    last_modified_by: r.last_modified_by,
    worker_records: (recsByRoster.get(r.id) || []).map(rec => {
      const ds = (daysByKey.get(`${r.id}|${rec.worker_id}`) || [])
        .sort((a, b) => a.day_index - b.day_index);
      return {
        worker_id: rec.worker_id,
        worker_name: rec.workers?.full_name ?? null,
        position: rec.workers?.position ?? null,
        corporation_id: rec.workers?.corporation_id ?? null,
        max_days_override: rec.max_days_override,
        notes: rec.notes,
        days: ds.map(d => ({
          entry_date: new Date(d.entry_date).toISOString(),
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
    const { error: deErr } = await supabase
      .from('roster_day_entries')
      .update({
        is_present: b.is_present,
        absence_reason: b.absence_reason || null,
      })
      .eq('roster_id', req.params.rosterId)
      .eq('worker_id', req.params.workerId)
      .eq('day_index', parseInt(req.params.dayIndex, 10));
    if (deErr) throw new Error(deErr.message);
    const { error: rErr } = await supabase
      .from('rosters')
      .update({
        last_modified: new Date().toISOString(),
        last_modified_by: b.modified_by || null,
      })
      .eq('id', req.params.rosterId);
    if (rErr) throw new Error(rErr.message);
    res.status(204).end();
  })
);

// ─── Backpay ─────────────────────────────────────────────────────────────────

app.get('/api/backpay-records', asyncRoute(async (req, res) => {
  const { data: recs, error: rErr } = await supabase
    .from('backpay_records')
    .select('*')
    .order('calculated_at', { ascending: false });
  if (rErr) throw new Error(rErr.message);
  const { data: lines } = await supabase
    .from('backpay_line_items')
    .select('backpay_record_id, timesheet_id, fortnight_start, days_worked, old_daily_rate, new_daily_rate, old_cola_rate, new_cola_rate');
  const linesByRec = new Map();
  for (const l of (lines || [])) {
    if (!linesByRec.has(l.backpay_record_id)) linesByRec.set(l.backpay_record_id, []);
    linesByRec.get(l.backpay_record_id).push(l);
  }
  res.json((recs || []).map(r => ({
    id: r.id,
    worker_id: r.worker_id,
    worker_name: r.worker_name,
    corporation_id: r.corporation_id,
    corporation_name: r.corporation_name,
    effective_from: new Date(r.effective_from).toISOString(),
    old_wage_rate: Number(r.old_wage_rate),
    new_wage_rate: Number(r.new_wage_rate),
    old_cola_rate: Number(r.old_cola_rate),
    new_cola_rate: Number(r.new_cola_rate),
    line_items: (linesByRec.get(r.id) || []).map(l => ({
      timesheet_id: l.timesheet_id,
      fortnight_start: new Date(l.fortnight_start).toISOString(),
      days_worked: l.days_worked,
      old_daily_rate: Number(l.old_daily_rate),
      new_daily_rate: Number(l.new_daily_rate),
      old_cola_rate: Number(l.old_cola_rate),
      new_cola_rate: Number(l.new_cola_rate),
    })),
    status: r.status,
    calculated_at: new Date(r.calculated_at).toISOString(),
    calculated_by_user_id: r.calculated_by_user_id,
    note: r.note,
  })));
}));

app.post('/api/backpay-records', asyncRoute(async (req, res) => {
  const b = req.body || {};

  const { error: bErr } = await supabase.from('backpay_records').insert({
    id: b.id,
    worker_id: b.worker_id,
    worker_name: b.worker_name,
    corporation_id: b.corporation_id,
    corporation_name: b.corporation_name,
    effective_from: b.effective_from,
    old_wage_rate: b.old_wage_rate,
    new_wage_rate: b.new_wage_rate,
    old_cola_rate: b.old_cola_rate,
    new_cola_rate: b.new_cola_rate,
    status: b.status || 'calculated',
    note: b.note,
    calculated_at: b.calculated_at,
    calculated_by_user_id: b.calculated_by_user_id,
  });
  if (bErr) throw new Error(bErr.message);

  for (const l of (b.line_items || [])) {
    const { error: lErr } = await supabase.from('backpay_line_items').insert({
      backpay_record_id: b.id,
      timesheet_id: l.timesheet_id,
      fortnight_start: l.fortnight_start,
      days_worked: l.days_worked,
      old_daily_rate: l.old_daily_rate,
      new_daily_rate: l.new_daily_rate,
      old_cola_rate: l.old_cola_rate,
      new_cola_rate: l.new_cola_rate,
    });
    if (lErr) throw new Error(lErr.message);
  }

  res.status(201).json(b);
}));

app.patch('/api/backpay-records/:id', asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!b.status) return res.status(400).json({ error: 'status required' });
  const { data, error } = await supabase
    .from('backpay_records')
    .update({ status: b.status })
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'backpay record not found' });
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
