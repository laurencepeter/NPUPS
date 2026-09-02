# NPUPS / WorkForce — Demo Brief

> One-stop reference for the demo: what the system is, every API and how it flows,
> how secure it is, the plan to remove hard-coded users and add LDAP, and how the
> database is backed up.
> All facts below are drawn directly from the source (`server/index.js`,
> `lib/`, `db/`, `docker-compose.prod.yml`), not invented.

---

## 1. What NPUPS Is (30-second pitch)

A Flutter-web HR & payroll platform for Trinidad & Tobago municipal corporations.
It replaces paper timesheets with a digital **9-stage payroll approval pipeline**,
a worker registry with document tracking, roster/attendance capture, back-pay
calculation, and a tamper-evident audit log.

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x / Dart web (dart2js), served by nginx |
| Backend | Node.js 18 + Express 4 REST API (`server/index.js`) |
| Database | PostgreSQL via Supabase (`supabase.fireydev.com`) |
| Hosting | Docker Compose on Coolify (`web` public, `api` internal-only) |

---

## 2. Architecture

```mermaid
flowchart LR
    U[Browser<br/>Flutter web app] -->|HTTPS| N[nginx<br/>serves bundle + proxies /api/*]
    N -->|/api/* same origin| A[Node/Express API<br/>:8080 internal-only]
    A -->|Supabase JS client<br/>shared anon key| S[(Supabase / PostgreSQL)]
    N -.serves static.-> U
```

**How the base URL is resolved** (`lib/services/api_client.dart`): on web the app
always talks to its **own origin**; nginx proxies `/api/*` to the internal Node
service. A stray build-time `API_BASE_URL` pointing at the same host is ignored
(prevents pointing the browser at an internal-only port). If no backend is
configured, the client returns empty results instead of throwing ("graceful
degradation").

---

## 3. The Payroll Approval Pipeline (the core flow)

Timesheet stages, in order (`lib/models/timesheet_model.dart`):

```mermaid
flowchart TD
    A[Not Started] --> B[Draft]
    B --> C[Submitted]
    C --> D[Coordinator Review]
    D --> E[HR Processing]
    E --> F[Accounts Processing]
    F --> G[Approved for Payment]
    G --> H[Exported]
    H --> I[Cheque / Direct Deposit]
    D -. reject to previous .-> C
    E -. reject to previous .-> D
    F -. reject to previous .-> E
```

- **Advance:** `advanceStage()` moves to the next stage and appends an
  `ApprovalRecord` (reviewer name, role, state, note, timestamp).
- **Reject:** `rejectToPreviousStage()` moves back one stage with a mandatory note.
- **Approval history** is an append-only list persisted via
  `POST /api/timesheets/:id/approvals`, which auto-assigns an incrementing
  `sequence_no`.

**Roles** (`lib/models/user_model.dart`): System Admin, Director (PS), DMCR,
Regional Coordinator, HR Department, Sub-Accounts Clerk, Main Accounts Clerk,
Executive Department, Worker.

---

## 4. Complete API Reference

Base path: `/api`. All handlers live in `server/index.js`. Content type is JSON.
The Node layer shapes rows to match the Flutter models' `fromJson` (e.g.
`shapeWorker`, `shapeTimesheet`). **Client supplies primary keys** (`id`) on create.

### 4.1 Health & readiness

| Method | Path | What it does | Notes |
|---|---|---|---|
| GET | `/api/health` | **Liveness.** Returns `{ok:true, version}` instantly. | Never touches Supabase — used by the container healthcheck so a Supabase outage can't restart-loop the container. |
| GET | `/api/ready` | **Readiness.** Probes `workers` table (3s timeout). | `200` if Supabase reachable, `503` if error/unreachable. For debugging, not polled. |

### 4.2 Workers (worker registry + PII)

| Method | Path | What it does |
|---|---|---|
| GET | `/api/workers` | List all workers, each joined with their documents and custom allowances. |
| GET | `/api/workers/:id` | One worker (full detail). `404` if not found. |
| POST | `/api/workers` | Create a worker. Seeds the 5 **required documents** (NIS Registration, Birth Certificate, Bank Verification Letter, National ID Card, Police Certificate of Good Character) as `missing` if not provided; inserts any custom allowances. Returns `201`. |
| PATCH | `/api/workers/:id` | Partial update — only the columns present in the body are written; sets `updated_at`. |
| DELETE | `/api/workers/:id` | **Soft-delete** — sets `is_active=false` (preserves FKs to timesheets/audit). `204`. |

Worker record fields include: full name, NIS number, DOB, position, ID number,
corporation, electoral district, wage/COLA/allowance rates, bank name / account
number / branch, BIR, driver's-permit, passport, contact, address, reference
number. (This is the sensitive PII/financial dataset.)

### 4.3 Worker allowances

| Method | Path | What it does |
|---|---|---|
| POST | `/api/workers/:id/allowances` | Add a custom allowance (name, rate, per-day-worked flag, active flag, note). |
| PATCH | `/api/worker-allowances/:id` | Update an allowance (fields present only). `204`. |
| DELETE | `/api/worker-allowances/:id` | Delete an allowance. `204` / `404`. |

### 4.4 Worker documents

| Method | Path | What it does |
|---|---|---|
| PUT | `/api/workers/:id/documents/:name` | Upsert a document's status/file for a worker (`onConflict: worker_id,doc_name`). `204`. |

### 4.5 Worker replacements

| Method | Path | What it does |
|---|---|---|
| GET | `/api/worker-replacements` | List replacements (original → replacement worker, days missed, reason), newest first. |
| POST | `/api/worker-replacements` | Upsert a replacement, keyed on `original_worker_id`. |

### 4.6 Timesheets

| Method | Path | What it does |
|---|---|---|
| GET | `/api/timesheets` | List timesheets, each with 14 daily entries (time in/out) and full approval history. |
| POST | `/api/timesheets` | Create a timesheet + its daily entries. Default stage `notStarted`. `201`. |
| PATCH | `/api/timesheets/:id` | Update stage / allowance_days / remarks and/or upsert daily entries (`onConflict: timesheet_id,day_index`). |
| POST | `/api/timesheets/:id/approvals` | Append an approval record with auto-incremented `sequence_no`. `201`. |

### 4.7 Rosters & roster settings

| Method | Path | What it does |
|---|---|---|
| GET | `/api/roster-settings` | Per-corporation roster rules (max days/fortnight, weekend work, override flags). |
| PATCH | `/api/roster-settings/:corporationId` | Upsert a corporation's roster settings (default max 10 days/fortnight). `204`. |
| GET | `/api/rosters` | List rosters with worker records and per-day presence/absence entries. |
| PUT | `/api/rosters/:rosterId/workers/:workerId/days/:dayIndex` | Set a single day's presence/absence; stamps `last_modified` / `last_modified_by`. `204`. |

### 4.8 Back-pay

| Method | Path | What it does |
|---|---|---|
| GET | `/api/backpay-records` | List back-pay records with line items (old/new wage & COLA rates per fortnight). |
| POST | `/api/backpay-records` | Create a back-pay record + line items. `201`. |
| PATCH | `/api/backpay-records/:id` | Update record status (`status` required, else `400`). `204`. |

### 4.9 Audit log

| Method | Path | What it does |
|---|---|---|
| GET | `/api/audit-logs` | List audit entries with field changes and attachments, ordered by `sequence_no`. Returns hash + previous_hash for the tamper-evident chain. |
| POST | `/api/audit-logs` | Insert an audit entry + field changes + attachments. **Hash chain and provenance fields are supplied by the client** (see security note C-4). `201`. |

### 4.10 How a call flows end-to-end

```mermaid
sequenceDiagram
    participant B as Browser (Flutter)
    participant N as nginx
    participant A as Express API
    participant S as Supabase (Postgres)
    B->>N: GET /api/workers
    N->>A: proxy /api/workers
    A->>S: from('workers').select('*') + documents + allowances
    S-->>A: rows
    A->>A: shapeWorker() → model JSON
    A-->>N: 200 [workers]
    N-->>B: 200 [workers]
```

Errors: the global handler returns `500 {error, path}` and logs server-side
(currently leaks raw Postgres messages — see H-6).

---

## 5. How Secure Is It? (honest assessment)

A full white-box audit already exists: **`security-audit/SECURITY_AUDIT_REPORT.md`**
(+ `.docx` and `.pptx` in the same folder). Summary for the demo:

**Overall rating: CRITICAL. Not production-ready for real PII/payroll — treat as a prototype.**

The core issue is **wiring, not knowledge**: a genuinely secure design (Supabase
Auth + Postgres row-level security in `db/supabase/99_rls.sql`) already exists in
the repo but is **dormant**. The path that actually runs has no server-side auth.

| # | Critical finding | In one line |
|---|---|---|
| C-1 | API has no auth | Every `/api/*` route is reachable with no token/session. `GET /api/workers` returns all unmasked PII. |
| C-2 | Auth is client-side only | Login is a hard-coded credential map compiled into the browser bundle; it constrains only what's *rendered*, not the API. |
| C-3 | RBAC only in the UI | `switchRole()` lets a session assume any role with no re-auth; the API enforces no roles. |
| C-4 | Audit is forgeable | SHA-256 hash chain is computed client-side; server stores whatever hash/provenance the request supplies. |

**High:** anon key committed to source (H-1), RLS never enforced on live path (H-2),
CORS fully open (H-3), no enforced HTTPS/HSTS (H-4), no security headers (H-5),
verbose error leakage (H-6).

**What *is* present today:** client-side login lockout (5 attempts → 2 min),
30-min client session timeout, soft-deletes preserving history, an append-only
audit design, and — crucially — the **network posture is the real control now**:
the `api` service is internal-only with no public ingress.

**The one-line demo talking point:** "The secure architecture is already designed
and in the repo (Supabase Auth + RLS). The remaining work is to make it the live
path — that's exactly what the roadmap below covers."

---

## 6. Roadmap: Remove Hard-Coded Users → Real Auth → LDAP

Hard-coded users live in `lib/services/auth_service.dart` (`_demoAccounts` map)
and `switchRole()`. Removing them is only meaningful **alongside** server-side
enforcement — otherwise the API is still open. Phased plan with realistic effort
(1 engineer; ranges account for coordination with the org's IT):

| Phase | Goal | Key work | Est. effort |
|---|---|---|---|
| **0. Seed real users** | Stop depending on the demo map | Populate `app_users` table; roles/corporations from `db/rbac_schema.sql`. | **2–3 days** |
| **1. Make Supabase Auth the sole gate** | Remove hard-coded login | Swap the app's gate from `AuthService` → the already-present `SupabaseAuthService`; delete `_demoAccounts` and `switchRole()`; login issues a real JWT. | **3–5 days** |
| **2. Server-side enforcement** (the real security win) | API rejects anonymous calls | Verify the Supabase JWT on every `/api/*` request (signature vs Supabase JWKS); forward the user JWT so **RLS executes per-user** (`99_rls.sql`); add role checks on each pipeline transition. | **1–2 weeks** |
| **3. Harden** | Close High findings | `helmet` headers, lock CORS to app origin, enforce HTTPS/HSTS, input validation (zod), server-side rate limiting, sanitised errors, rotate the committed anon key. | **1 week** |
| **4. LDAP / Active Directory SSO** | Enterprise sign-in | See below. | **2–4 weeks** |

**Total to a production-hardened baseline (Phases 0–3): ~3–4 weeks.**
**Add LDAP (Phase 4): ~2–4 more weeks**, depending on approach and IT access.

### 6.1 LDAP options (municipal orgs typically run Active Directory)

| Approach | How | Trade-off | Est. |
|---|---|---|---|
| **A. SSO via SAML/OIDC bridge (recommended)** | Front AD with Azure AD / ADFS as an OIDC/SAML IdP; connect it to Supabase SSO (SAML) or an OIDC broker. App keeps issuing Supabase JWTs. | Cleanest; no raw LDAP creds in the app; MFA/conditional access come free. Needs Supabase Pro (SSO) + IT to expose the IdP. | **2–3 weeks** |
| **B. Direct LDAP bind in the Node API** | `passport-ldapauth` / `ldapjs` against the AD server; on success the API mints its own JWT. | No IdP dependency, but the app handles credentials and you own session/MFA logic. Requires a network route to the DC. | **3–4 weeks** |
| **C. Keycloak (or similar) in front** | Run Keycloak, federate it to AD via LDAP, expose OIDC to the app. | Most flexible/portable; adds an component to operate. | **3–4 weeks** |

**Recommendation:** Option A (SAML/OIDC bridge) — fastest to a *production-safe*
result, keeps credentials out of the app, and reuses the existing JWT/RLS work
from Phase 2. Biggest schedule risk in all options is **IT coordination** (getting
the DC route / IdP metadata), so start that conversation first.

---

## 7. Database Backup

The database is **PostgreSQL via Supabase** (`SUPABASE_URL=https://supabase.fireydev.com`).
Choose based on whether this is hosted or self-hosted Supabase.

### 7.1 If using Supabase's managed platform
- **Automated daily backups** are included on the Pro plan (retention by tier).
- **Point-in-Time Recovery (PITR)** is available on higher tiers for
  second-level restore — recommended before this holds real payroll data.
- Restores are triggered from the Supabase dashboard (Database → Backups).

### 7.2 Manual / self-hosted backups (works everywhere)

Take a logical dump with `pg_dump` against the Postgres connection string
(Supabase → Project Settings → Database → Connection string):

```bash
# Full compressed dump (schema + data), custom format for selective restore
pg_dump "postgresql://USER:PASSWORD@HOST:5432/postgres" \
  --format=custom --no-owner --no-privileges \
  --file="npups_$(date +%Y%m%d_%H%M%S).dump"

# Plain SQL alternative
pg_dump "postgresql://USER:PASSWORD@HOST:5432/postgres" \
  --no-owner --file="npups_$(date +%Y%m%d).sql"
```

**Restore:**
```bash
# From a custom-format dump into an empty database
pg_restore --clean --if-exists --no-owner \
  --dbname="postgresql://USER:PASSWORD@HOST:5432/postgres" \
  npups_20260902.dump
```

**Schedule (nightly cron on the API host or a small backup box):**
```bash
# /etc/cron.d/npups-backup  → 02:15 daily
15 2 * * *  backupuser  pg_dump "$NPUPS_DB_URL" --format=custom \
  --file=/var/backups/npups/npups_$(date +\%Y\%m\%d).dump \
  && find /var/backups/npups -name '*.dump' -mtime +30 -delete
```

### 7.3 Backup policy checklist (recommended before production)
- **3-2-1:** 3 copies, 2 media, 1 offsite. Push nightly dumps to object storage
  (S3/Backblaze) with a bucket lifecycle rule.
- **Immutability (WORM):** enable object-lock/versioning so backups can't be
  altered or ransomware-encrypted — matters most for the **audit log**.
- **Encryption:** encrypt dumps at rest (`gpg` or SSE) — they contain full PII.
- **Test restores:** restore to a scratch DB monthly; an untested backup is a
  guess. Verify row counts and that the audit hash chain still verifies.
- **Retention:** e.g. 30 daily + 12 monthly; align with any records-retention law.
- **Secrets:** keep `$NPUPS_DB_URL` in a vault / env file (`chmod 600`), never in
  the repo.

---

## 8. Demo Flow Cheat-Sheet

1. **Login** with a demo account (see `CLAUDE.md`; e.g. `admin@workforce.app` / `admin123`).
2. **Worker registry** → open a worker → show documents + allowances (`GET /api/workers/:id`).
3. **Timesheet** → enter the 14-day fortnight grid → submit (`POST /api/timesheets`).
4. **Walk the pipeline** → Coordinator → HR → Accounts, each approval appended
   (`POST /api/timesheets/:id/approvals`); show a rejection bouncing back one stage.
5. **Back-pay** → show a rate change producing line items (`/api/backpay-records`).
6. **Audit log** → show the hash-chained, append-only trail (`/api/audit-logs`).
7. **Close on security & roadmap** → Sections 5–6 above.

> Interactive companion deck already in the repo:
> `presentation/platform-walkthrough.html` (self-contained, keyboard-navigable).
