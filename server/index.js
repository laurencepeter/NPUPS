// ─────────────────────────────────────────────────────────────────────────────
// WorkForce REST API — backed by Supabase
//
// Run:
//   SUPABASE_URL=https://supabase.fireydev.com \
//   SUPABASE_ANON_KEY=eyJ... \
//   PORT=8080 node index.js
// ─────────────────────────────────────────────────────────────────────────────

const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const { createClient } = require('@supabase/supabase-js');

const PORT = parseInt(process.env.PORT || '8080', 10);
// Trim so a stray space/newline pasted into the Coolify env UI doesn't turn a
// valid value into a "fails to parse as URL" crash that's hard to spot.
const SUPABASE_URL = (process.env.SUPABASE_URL || '').trim();
const SUPABASE_ANON_KEY = (process.env.SUPABASE_ANON_KEY || '').trim();

// ─── Auth / transport config ──────────────────────────────────────────────
const NODE_ENV = process.env.NODE_ENV || 'development';
const API_JWT_SECRET = (process.env.API_JWT_SECRET || '').trim();
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '8h';
// Explicit, logged opt-out for running WITHOUT auth (local demo / CI only).
const ALLOW_INSECURE_NO_AUTH = process.env.ALLOW_INSECURE_NO_AUTH === 'true';
// Cross-origin allowlist. Empty ⇒ CORS disabled (same-origin only), which is
// correct for the nginx same-origin proxy the web app uses.
const CORS_ALLOWED_ORIGINS = (process.env.CORS_ALLOWED_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
// Auth is ON whenever a secret is configured. It is the required posture in
// production; see the fail-secure check below.
const AUTH_ENABLED = API_JWT_SECRET.length > 0;

// Fail fast WITH a specific reason. A bare crash here just shows up in Coolify
// as "no containers running"; naming the exact missing/invalid var is the
// difference between a 30-second fix and an hour of guessing.
const missing = [];
if (!SUPABASE_URL) missing.push('SUPABASE_URL');
if (!SUPABASE_ANON_KEY) missing.push('SUPABASE_ANON_KEY');
if (missing.length) {
  console.error(
    `FATAL: missing required environment variable(s): ${missing.join(', ')}. ` +
      'Set them on the api service in the Coolify UI (Environment Variables).',
  );
  process.exit(1);
}
try {
  // Validate before handing to createClient, which throws an opaque error on a
  // malformed URL. This message points straight at the typo.
  new URL(SUPABASE_URL);
} catch {
  console.error(
    `FATAL: SUPABASE_URL is not a valid URL: "${SUPABASE_URL}". ` +
      'Expected something like https://your-project.supabase.co (no trailing space).',
  );
  process.exit(1);
}

// Fail secure: the API is the only path to the database, so it must not run
// unauthenticated in production. Require a strong JWT secret; allow an explicit,
// loudly-logged opt-out only for local/demo use.
if (AUTH_ENABLED && API_JWT_SECRET.length < 32) {
  console.error(
    'FATAL: API_JWT_SECRET is too short. Use at least 32 random characters ' +
      '(e.g. `openssl rand -base64 48`).',
  );
  process.exit(1);
}
if (!AUTH_ENABLED) {
  if (NODE_ENV === 'production' && !ALLOW_INSECURE_NO_AUTH) {
    console.error(
      'FATAL: API_JWT_SECRET is not set. Refusing to start unauthenticated in ' +
        'production. Set API_JWT_SECRET, or set ALLOW_INSECURE_NO_AUTH=true to ' +
        'explicitly run open (NEVER in production).',
    );
    process.exit(1);
  }
  console.warn(
    '⚠  API_JWT_SECRET not set — authentication is DISABLED and every /api ' +
      'route is open. Acceptable only for local demo / CI. Do NOT deploy like this.',
  );
}

let supabase;
try {
  supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} catch (e) {
  console.error(`FATAL: failed to initialise Supabase client: ${e.message}`);
  process.exit(1);
}

const app = express();
// Behind the nginx proxy: trust the first hop so req.ip / rate-limit key use
// the real client IP from X-Forwarded-For rather than the proxy's address.
app.set('trust proxy', 1);

// Security headers (HSTS, nosniff, frame-deny, referrer policy, etc.). The API
// returns JSON only, so the HTML-oriented CSP is not needed here.
app.use(helmet({ contentSecurityPolicy: false }));

// CORS: only the configured origins may make cross-origin calls. Empty list ⇒
// no Access-Control-Allow-Origin emitted, so browsers block cross-origin use —
// the correct default for the same-origin nginx proxy.
app.use(
  cors({
    origin: CORS_ALLOWED_ORIGINS.length ? CORS_ALLOWED_ORIGINS : false,
    credentials: true,
  }),
);

app.use(express.json({ limit: '5mb' }));

// Rate limiting — a broad ceiling on the whole API plus a tight limit on the
// auth endpoint to blunt credential brute-forcing.
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
});
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'too many login attempts, try again later' },
});
app.use('/api/', apiLimiter);

// ─── Helpers ─────────────────────────────────────────────────────────────────

function asyncRoute(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function isoOrNull(v) {
  return v == null ? null : new Date(v).toISOString();
}

// ─── Authentication & RBAC ────────────────────────────────────────────────
//
// Passwords are verified against a scrypt hash ("scrypt:<saltHex>:<hashHex>")
// using Node's built-in crypto — no native/bcrypt dependency to build in the
// image, and a constant-time comparison. On success the API issues a short-
// lived HS256 JWT that the client returns as `Authorization: Bearer <token>`.

function verifyPassword(password, stored) {
  if (typeof stored !== 'string') return false;
  const parts = stored.split(':');
  if (parts.length !== 3 || parts[0] !== 'scrypt') return false;
  const salt = Buffer.from(parts[1], 'hex');
  const expected = Buffer.from(parts[2], 'hex');
  let actual;
  try {
    actual = crypto.scryptSync(String(password), salt, expected.length);
  } catch {
    return false;
  }
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

function signToken(u) {
  return jwt.sign(
    {
      sub: u.id,
      email: u.email,
      role: u.role,
      corporation_id: u.corporation_id ?? null,
      name: u.full_name ?? null,
    },
    API_JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN },
  );
}

// Verify the bearer token. When auth is disabled (local/demo) a synthetic admin
// principal is injected so downstream role checks and the app still function.
function requireAuth(req, res, next) {
  if (!AUTH_ENABLED) {
    req.user = { sub: 'insecure-open', role: 'systemAdmin' };
    return next();
  }
  const m = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || '');
  if (!m) return res.status(401).json({ error: 'missing bearer token' });
  try {
    // Pin the algorithm so only our HS256-signed tokens are accepted.
    req.user = jwt.verify(m[1], API_JWT_SECRET, { algorithms: ['HS256'] });
    return next();
  } catch {
    return res.status(401).json({ error: 'invalid or expired token' });
  }
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!AUTH_ENABLED) return next();
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ error: `forbidden: requires role ${roles.join('/')}` });
    }
    return next();
  };
}

// Provenance must come from the *verified* token, never the request body: a
// client can put any name/id/role in a payload, so trusting it lets one user
// attribute an action (audit entry, approval, backpay) to another. When auth is
// enabled we stamp identity from req.user (the signed JWT). In the local/demo
// server (auth disabled) there is no token identity, so we fall back to the
// body just to keep the demo functional — never a production path.
function actorFromToken(req, body = {}) {
  if (AUTH_ENABLED && req.user) {
    return {
      user_id: req.user.sub,
      user_name: req.user.name ?? body.user_name ?? null,
      user_role: req.user.role,
    };
  }
  return {
    user_id: body.user_id ?? null,
    user_name: body.user_name ?? null,
    user_role: body.user_role ?? null,
  };
}

// ─── Role authorization (mirrors lib/models/user_model.dart UserRole) ───────
//
// Coarse per-endpoint role allowlists for write operations. Reads stay open to
// any authenticated principal (already corporation-scoped). systemAdmin is
// included in every set so it retains full access. When auth is disabled
// (local/demo) requireRole is a no-op, so these are advisory there.
const WORKER_EDITORS = ['systemAdmin', 'ministersDepartment'];
const WORKER_DOC_EDITORS = ['systemAdmin', 'ministersDepartment', 'hr'];
const REPLACEMENT_EDITORS = ['systemAdmin', 'dmcr', 'regionalCoordinator'];
const TIMESHEET_EDITORS = ['systemAdmin', 'worker', 'regionalCoordinator'];
const ROSTER_EDITORS = ['systemAdmin', 'dmcr', 'regionalCoordinator'];
const BACKPAY_EDITORS = ['systemAdmin', 'subAccounts', 'mainAccounts'];

// Stage-scoped authorization for the timesheet approval pipeline: only the role
// that OWNS the current stage may advance (or reject) it. Mirrors
// TimesheetStage.stageOwner in lib/models/timesheet_model.dart. systemAdmin may
// act on any stage; terminal stage (chequePrinting) advances nowhere.
const STAGE_ADVANCERS = {
  notStarted: ['worker', 'regionalCoordinator'],
  draft: ['worker', 'regionalCoordinator'],
  submitted: ['regionalCoordinator'],
  coordinatorReview: ['regionalCoordinator'],
  hrProcessing: ['hr'],
  accountsProcessing: ['subAccounts', 'mainAccounts'],
  approvedForPayment: ['subAccounts', 'mainAccounts'],
  exported: ['subAccounts', 'mainAccounts'],
  chequePrinting: [],
};

function canAdvanceFrom(req, currentStage) {
  if (!AUTH_ENABLED) return true;
  const role = req.user && req.user.role;
  if (role === 'systemAdmin') return true;
  return (STAGE_ADVANCERS[currentStage] || []).includes(role);
}

// Server-authoritative audit hash. Byte-for-byte identical to the Dart
// AuditService._computeHash and the SQL seed in db/domain_schema.sql, so a
// server-written entry still verifies on the client after a reload:
//   sha256( previousHash || id || millisSinceEpoch || userId
//         || action || entityType || entityId || changesStr || attachStr )
// changesStr ordered as received (persisted by sequence_no); attachStr ordered
// by id (the order the GET endpoint re-hydrates).
function computeAuditHash({ previousHash, id, timestamp, userId, action, entityType, entityId, fieldChanges, attachments }) {
  const changesStr = (fieldChanges || [])
    .map((f) => `${f.field_name}|${f.old_value ?? ''}|${f.new_value ?? ''}`)
    .join(';');
  const attachStr = (attachments || [])
    .slice()
    // Bytewise (not locale-aware) ascending, to match how the GET endpoint and
    // the SQL seed order attachments by id when the chain is re-verified.
    .sort((a, b) => (String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0))
    .map((a) => `${a.id}|${a.content_hash}|${a.size_bytes}`)
    .join(';');
  const millis = String(new Date(timestamp).getTime());
  const payload = [
    previousHash, id, millis, userId, action, entityType, entityId, changesStr, attachStr,
  ].join('||');
  return crypto.createHash('sha256').update(payload, 'utf8').digest('hex');
}

// ─── Tenant isolation (row-level, corporation-scoped) ───────────────────────
//
// A principal whose token carries a corporation_id (regional coordinator, HR,
// worker) is confined to that corporation. Global roles (systemAdmin, ps,
// subAccounts, mainAccounts, dmcr, ministersDepartment) have a null
// corporation_id and see every corporation. Enforced server-side so the API —
// the only path to the DB — never returns another tenant's rows.

/// The corporation a request is confined to, or null when it may see all
/// corporations (global role, or auth disabled in the local/demo server).
function scopeCorporation(req) {
  if (!AUTH_ENABLED) return null;
  const c = req.user && req.user.corporation_id;
  return c ? String(c) : null;
}

/// True when the request may touch a row belonging to [corporationId].
function corpAllows(req, corporationId) {
  const scope = scopeCorporation(req);
  return scope === null || String(corporationId) === scope;
}

/// Applies the corporation filter to a Supabase query when the request is
/// scoped; a no-op for global roles. `column` defaults to corporation_id.
function scopeQuery(req, query, column = 'corporation_id') {
  const scope = scopeCorporation(req);
  return scope === null ? query : query.eq(column, scope);
}

// Global gate: every /api route requires a valid token except the liveness/
// readiness probes and the login endpoint itself.
const OPEN_PATHS = new Set(['/api/health', '/api/ready', '/api/auth/login']);
app.use((req, res, next) => {
  // Case-fold the path: Express routing is case-insensitive by default, so a
  // case-sensitive gate here (e.g. accepting "/API/workers") would let a
  // request skip auth yet still reach the lower-cased route handler.
  const path = req.path.toLowerCase();
  if (!path.startsWith('/api/')) return next();
  if (OPEN_PATHS.has(path)) return next();
  return requireAuth(req, res, next);
});

// ─── Auth endpoint ─────────────────────────────────────────────────────────

app.post('/api/auth/login', authLimiter, asyncRoute(async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password are required' });
  }
  if (!AUTH_ENABLED) {
    // Server is running open (no secret configured): there is no token to
    // issue. The client treats this as "auth not enforced" and proceeds.
    return res.status(501).json({ error: 'authentication is disabled on this server' });
  }
  const { data: u } = await supabase
    .from('app_users')
    .select('id, email, full_name, role, corporation_id, corporation_name, is_active, password_hash')
    .eq('email', String(email).toLowerCase().trim())
    .maybeSingle();
  // Uniform failure for unknown user, inactive user, or bad password — no
  // enumeration of which one it was.
  if (!u || u.is_active === false || !verifyPassword(password, u.password_hash)) {
    return res.status(401).json({ error: 'invalid credentials' });
  }
  const token = signToken(u);
  res.json({
    token,
    user: {
      id: u.id,
      email: u.email,
      full_name: u.full_name,
      role: u.role,
      corporation_id: u.corporation_id,
      corporation_name: u.corporation_name,
    },
  });
}));

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
  const { data: wRows, error: wErr } =
    await scopeQuery(req, supabase.from('workers').select('*').order('id'));
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
  // Return 404 (not 403) for a worker outside the caller's corporation so the
  // response can't be used to probe which worker ids exist in other tenants.
  if (!w || !corpAllows(req, w.corporation_id)) {
    return res.status(404).json({ error: 'worker not found' });
  }
  res.json(w);
}));

app.post('/api/workers', requireRole(...WORKER_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  // A scoped user can only create workers within their own corporation.
  if (!corpAllows(req, b.corporation_id)) {
    return res.status(403).json({ error: 'forbidden: worker outside your corporation' });
  }

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

app.patch('/api/workers/:id', requireRole(...WORKER_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  // Tenant check: the worker must belong to the caller's corporation, and a
  // scoped user cannot reassign it into another corporation.
  const current = await fetchWorkerRow(req.params.id);
  if (!current || !corpAllows(req, current.corporation_id)) {
    return res.status(404).json({ error: 'worker not found' });
  }
  if (b.corporation_id !== undefined && !corpAllows(req, b.corporation_id)) {
    return res.status(403).json({ error: 'forbidden: cannot reassign worker to another corporation' });
  }
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

app.delete('/api/workers/:id', requireRole('systemAdmin'), asyncRoute(async (req, res) => {
  // Tenant check before any mutation.
  const current = await fetchWorkerRow(req.params.id);
  if (!current || !corpAllows(req, current.corporation_id)) {
    return res.status(404).json({ error: 'worker not found' });
  }
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

app.post('/api/workers/:id/allowances', requireRole(...WORKER_EDITORS), asyncRoute(async (req, res) => {
  const a = req.body || {};
  const { data: wRow } = await supabase
    .from('workers').select('corporation_id').eq('id', req.params.id).maybeSingle();
  if (!wRow || !corpAllows(req, wRow.corporation_id)) {
    return res.status(404).json({ error: 'worker not found' });
  }
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

app.patch('/api/worker-allowances/:id', requireRole(...WORKER_EDITORS), asyncRoute(async (req, res) => {
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

app.delete('/api/worker-allowances/:id', requireRole(...WORKER_EDITORS), asyncRoute(async (req, res) => {
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

app.put('/api/workers/:id/documents/:name', requireRole(...WORKER_DOC_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  // Tenant check via the parent worker.
  const { data: wRow } = await supabase
    .from('workers').select('corporation_id').eq('id', req.params.id).maybeSingle();
  if (!wRow || !corpAllows(req, wRow.corporation_id)) {
    return res.status(404).json({ error: 'worker not found' });
  }
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

app.post('/api/worker-replacements', requireRole(...REPLACEMENT_EDITORS), asyncRoute(async (req, res) => {
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
  const { data: tsRows, error: tsErr } =
    await scopeQuery(req, supabase.from('timesheets').select('*').order('id'));
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

app.post('/api/timesheets', requireRole(...TIMESHEET_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!corpAllows(req, b.corporation_id)) {
    return res.status(403).json({ error: 'forbidden: timesheet outside your corporation' });
  }

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
  // Tenant check: timesheet must belong to the caller's corporation.
  const { data: tsRow } = await supabase
    .from('timesheets').select('corporation_id, stage').eq('id', req.params.id).maybeSingle();
  if (!tsRow || !corpAllows(req, tsRow.corporation_id)) {
    return res.status(404).json({ error: 'timesheet not found' });
  }

  // Authorization: a stage transition is gated by who owns the current stage;
  // a content-only edit (entries/remarks) is limited to the data-entry roles.
  const changingStage = b.stage !== undefined && b.stage !== tsRow.stage;
  if (changingStage) {
    if (!canAdvanceFrom(req, tsRow.stage)) {
      return res.status(403).json({ error: `forbidden: your role cannot change a timesheet at stage '${tsRow.stage}'` });
    }
  } else if (AUTH_ENABLED && req.user && !TIMESHEET_EDITORS.includes(req.user.role)) {
    return res.status(403).json({ error: 'forbidden: your role cannot edit timesheet entries' });
  }

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
  const { data: tsRow } = await supabase
    .from('timesheets').select('corporation_id, stage').eq('id', req.params.id).maybeSingle();
  if (!tsRow || !corpAllows(req, tsRow.corporation_id)) {
    return res.status(404).json({ error: 'timesheet not found' });
  }
  // Only the role that owns the timesheet's current stage may record an
  // approval/rejection on it.
  if (!canAdvanceFrom(req, tsRow.stage)) {
    return res.status(403).json({ error: `forbidden: your role cannot review a timesheet at stage '${tsRow.stage}'` });
  }
  const { data: seqData } = await supabase
    .from('timesheet_approvals')
    .select('sequence_no')
    .eq('timesheet_id', req.params.id)
    .order('sequence_no', { ascending: false })
    .limit(1);
  const seq = seqData && seqData.length > 0 ? seqData[0].sequence_no + 1 : 1;
  // Reviewer identity comes from the verified token so an approval cannot be
  // recorded under someone else's name/role.
  const who = actorFromToken(req, { user_name: a.reviewer_name, user_role: a.reviewer_role });
  const reviewerName = who.user_name;
  const reviewerRole = who.user_role;
  const { error } = await supabase.from('timesheet_approvals').insert({
    timesheet_id: req.params.id,
    sequence_no: seq,
    reviewer_name: reviewerName,
    reviewer_role: reviewerRole,
    state: a.state || 'approved',
    note: a.note,
    ts: a.ts || new Date().toISOString(),
  });
  if (error) throw new Error(error.message);
  res.status(201).json({ ...a, reviewer_name: reviewerName, reviewer_role: reviewerRole, sequence_no: seq });
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
    .select('audit_log_id, id, file_name, mime_type, size_bytes, content_hash, uploaded_at')
    // Deterministic order so the re-hydrated attachment list matches the order
    // the chain hash was computed over (see AuditService._computeHash / DB seed).
    .order('audit_log_id')
    .order('id');
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
  // Attribute the entry to the authenticated principal, not to whatever the
  // body claims — otherwise the audit trail is trivially forgeable.
  const who = actorFromToken(req, b);

  // Server-authoritative hash chain: the client's hash/previous_hash are
  // ignored. previous_hash is the hash of the current tail (highest
  // sequence_no); the entry's own hash is recomputed here. This makes the
  // chain unforgeable by any client — a tampered or fabricated entry no longer
  // links. (Note: not concurrency-safe across simultaneous writers; a single
  // API instance serialising audit writes, or a DB advisory lock, would close
  // that residual gap.)
  const { data: tail } = await supabase
    .from('app_audit_logs')
    .select('hash')
    .order('sequence_no', { ascending: false })
    .limit(1);
  const previousHash = tail && tail.length > 0 ? tail[0].hash : '';
  const hash = computeAuditHash({
    previousHash,
    id: b.id,
    timestamp: b.timestamp,
    userId: who.user_id ?? '',
    action: b.action,
    entityType: b.entity_type,
    entityId: b.entity_id,
    fieldChanges: b.field_changes,
    attachments: b.attachments,
  });

  const { error: lErr } = await supabase.from('app_audit_logs').insert({
    id: b.id,
    timestamp: b.timestamp,
    user_id: who.user_id ?? '',
    user_name: who.user_name ?? '',
    user_role: who.user_role ?? '',
    session_id: b.session_id,
    action: b.action,
    entity_type: b.entity_type,
    entity_id: b.entity_id,
    entity_display_name: b.entity_display_name,
    note: b.note,
    actor_context: b.actor_context,
    hash,
    previous_hash: previousHash,
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

  res.status(201).json({
    ...b,
    user_id: who.user_id,
    user_name: who.user_name,
    user_role: who.user_role,
    hash,
    previous_hash: previousHash,
  });
}));

// ─── Roster settings + Rosters ───────────────────────────────────────────────

app.get('/api/roster-settings', asyncRoute(async (req, res) => {
  const { data, error } = await scopeQuery(req, supabase
    .from('roster_settings')
    .select('corporation_id, max_days_per_fortnight, allow_weekend_work, allow_max_days_override, data_entry_can_override'));
  if (error) throw new Error(error.message);
  res.json(data || []);
}));

app.patch('/api/roster-settings/:corporationId', requireRole('systemAdmin'), asyncRoute(async (req, res) => {
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
  const { data: rosters, error: rErr } = await scopeQuery(req, supabase
    .from('rosters')
    .select('*')
    .order('fortnight_start', { ascending: false }))
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
  requireRole(...ROSTER_EDITORS),
  asyncRoute(async (req, res) => {
    const b = req.body || {};
    // Tenant check: the roster must belong to the caller's corporation.
    const { data: rosterRow } = await supabase
      .from('rosters').select('corporation_id').eq('id', req.params.rosterId).maybeSingle();
    if (!rosterRow || !corpAllows(req, rosterRow.corporation_id)) {
      return res.status(404).json({ error: 'roster not found' });
    }
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

// ─── Payroll rate tables (statutory rates — admin managed) ────────────────────
//
// Effective-dated PAYE / NIS / Health Surcharge parameters. The Flutter engine
// resolves the applicable row for a fortnight by its effective_from date, so a
// statutory change is a data edit rather than a code change. JSON keys mirror
// lib/models/payroll_deductions_model.dart DeductionRateTable.fromJson.

function shapeRateTable(r) {
  return {
    id: r.id,
    label: r.label,
    effective_from: r.effective_from ? new Date(r.effective_from).toISOString() : null,
    year: r.year,
    pay_periods_per_year: r.pay_periods_per_year,
    nis_employee_rate: Number(r.nis_employee_rate),
    nis_employer_rate: Number(r.nis_employer_rate),
    health_surcharge_weekly_high: Number(r.health_surcharge_weekly_high),
    health_surcharge_weekly_low: Number(r.health_surcharge_weekly_low),
    health_surcharge_high_threshold: Number(r.health_surcharge_high_threshold),
    personal_allowance_annual: Number(r.personal_allowance_annual),
    paye_band_threshold_annual: Number(r.paye_band_threshold_annual),
    paye_rate_low: Number(r.paye_rate_low),
    paye_rate_high: Number(r.paye_rate_high),
  };
}

app.get('/api/rate-tables', asyncRoute(async (req, res) => {
  const { data, error } = await supabase
    .from('payroll_rate_tables')
    .select('*')
    .order('effective_from', { ascending: true });
  if (error) throw new Error(error.message);
  res.json((data || []).map(shapeRateTable));
}));

// Integrity guard: statutory figures must be sane before they can drive
// payroll. Rejects negatives, out-of-range rates, and malformed dates.
function validateRateTable(b) {
  const frac = ['nis_employee_rate', 'nis_employer_rate', 'paye_rate_low', 'paye_rate_high'];
  const money = [
    'health_surcharge_weekly_high', 'health_surcharge_weekly_low',
    'health_surcharge_high_threshold', 'personal_allowance_annual',
    'paye_band_threshold_annual',
  ];
  for (const k of frac) {
    const v = Number(b[k]);
    if (!Number.isFinite(v) || v < 0 || v > 1) return `${k} must be a fraction between 0 and 1`;
  }
  for (const k of money) {
    const v = Number(b[k]);
    if (!Number.isFinite(v) || v < 0) return `${k} must be a non-negative number`;
  }
  const p = Number(b.pay_periods_per_year);
  if (!Number.isInteger(p) || p < 1 || p > 366) return 'pay_periods_per_year must be an integer between 1 and 366';
  if (typeof b.effective_from !== 'string' || Number.isNaN(Date.parse(b.effective_from))) {
    return 'effective_from must be a valid date';
  }
  return null;
}

app.put('/api/rate-tables/:id', requireRole('systemAdmin'), asyncRoute(async (req, res) => {
  const b = req.body || {};
  const invalid = validateRateTable(b);
  if (invalid) return res.status(400).json({ error: invalid });
  const eff = typeof b.effective_from === 'string' ? b.effective_from.slice(0, 10) : null;
  const { error } = await supabase.from('payroll_rate_tables').upsert(
    {
      id: req.params.id,
      label: b.label ?? null,
      effective_from: eff,
      year: b.year ?? (eff ? parseInt(eff.slice(0, 4), 10) : new Date().getFullYear()),
      pay_periods_per_year: b.pay_periods_per_year ?? 26,
      nis_employee_rate: b.nis_employee_rate,
      nis_employer_rate: b.nis_employer_rate,
      health_surcharge_weekly_high: b.health_surcharge_weekly_high,
      health_surcharge_weekly_low: b.health_surcharge_weekly_low,
      health_surcharge_high_threshold: b.health_surcharge_high_threshold,
      personal_allowance_annual: b.personal_allowance_annual,
      paye_band_threshold_annual: b.paye_band_threshold_annual,
      paye_rate_low: b.paye_rate_low,
      paye_rate_high: b.paye_rate_high,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'id' }
  );
  if (error) throw new Error(error.message);
  res.status(204).end();
}));

app.delete('/api/rate-tables/:id', requireRole('systemAdmin'), asyncRoute(async (req, res) => {
  const { data, error } = await supabase
    .from('payroll_rate_tables')
    .delete()
    .eq('id', req.params.id)
    .select()
    .single();
  if (error || !data) return res.status(404).json({ error: 'rate table not found' });
  res.status(204).end();
}));

// ─── Backpay ─────────────────────────────────────────────────────────────────

app.get('/api/backpay-records', asyncRoute(async (req, res) => {
  const { data: recs, error: rErr } = await scopeQuery(req, supabase
    .from('backpay_records')
    .select('*')
    .order('calculated_at', { ascending: false }));
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

app.post('/api/backpay-records', requireRole(...BACKPAY_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!corpAllows(req, b.corporation_id)) {
    return res.status(403).json({ error: 'forbidden: backpay outside your corporation' });
  }

  // Stamp the calculating user from the verified token, not the request body.
  const calculatedBy = AUTH_ENABLED && req.user ? req.user.sub : (b.calculated_by_user_id ?? null);
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
    calculated_by_user_id: calculatedBy,
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

  res.status(201).json({ ...b, calculated_by_user_id: calculatedBy });
}));

app.patch('/api/backpay-records/:id', requireRole(...BACKPAY_EDITORS), asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!b.status) return res.status(400).json({ error: 'status required' });
  const { data: rec } = await supabase
    .from('backpay_records').select('corporation_id').eq('id', req.params.id).maybeSingle();
  if (!rec || !corpAllows(req, rec.corporation_id)) {
    return res.status(404).json({ error: 'backpay record not found' });
  }
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

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // Log the full error server-side; return a generic message to the client in
  // production so internal details (DB errors, stack traces) are never leaked.
  console.error(`[error] ${req.method} ${req.path}:`, err);
  const body = { error: 'internal error', path: req.path };
  if (NODE_ENV !== 'production') body.detail = err.message;
  res.status(500).json(body);
});

// ─── Boot ────────────────────────────────────────────────────────────────────

app.listen(PORT, () => {
  console.log(
    `workforce-api listening on :${PORT} ` +
      `(auth: ${AUTH_ENABLED ? 'enabled' : 'DISABLED'}, env: ${NODE_ENV})`,
  );
});
