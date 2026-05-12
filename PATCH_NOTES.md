# WorkForce — Patch Notes

Branch: `claude/fix-database-connection-epcaS`

This release fixes the "data not appearing at home / dashboard shows 2,847
workers but the database has none" report. The root cause was a missing
backend service plus client-side mutations that never persisted — both have
been resolved end to end.

## TL;DR

| # | What was broken | What now happens |
|---|---|---|
| 1 | No HTTP service implemented `/api/*` — schemas existed but nothing served them | A Node.js + Express + `pg` API now lives in `server/` and implements every endpoint the Flutter client expects |
| 2 | `WorkerDataStore.addWorker` (and 9 other mutations) only mutated in-memory state | Every mutation now `POST`/`PATCH`/`DELETE`s through `ApiClient` with optimistic UI + rollback on failure |
| 3 | Dashboard KPIs were hardcoded strings (`'2,847'`, `'$1.2M'`, `'14'`) | KPIs are computed live from the data stores and rebuild on `notifyListeners` |
| 4 | "Recent Activity" was four hardcoded fixture lines | Pulls the most recent six entries from the live `AuditService` chain |
| 5 | `API_BASE_URL` unset / unreachable was silently swallowed | New `BackendStatusBanner` warns the user with actionable instructions |
| 6 | Missing schema columns (`driver_permit_number`, `passport_number`) and missing enum value (`duplicateIdAttempt`) | Added so the round-trip POST never gets rejected by Postgres |
| 7 | No way to stand up the demo end to end | `docker compose up --build` starts Postgres + API + nginx-served Flutter web together |

---

## 1. Backend service (NEW)

**Files:** `server/index.js`, `server/package.json`, `server/Dockerfile`,
`server/README.md`

The Flutter app's `api_client.dart` has always been wired to talk to a
backend at `API_BASE_URL`, but no backend ever existed in this repo. When
`API_BASE_URL` was empty the client returned empty results from every
read; when it was set to a URL nothing was listening on, every read failed
silently and every write was a no-op. Either way, you saw an empty
dashboard *or* hardcoded numbers.

The new `server/index.js` is a single ~600-line Express app that:

- Pings Postgres on `GET /api/health` for liveness/readiness probes.
- Implements full CRUD for **workers** (with documents and custom
  allowances joined inline), **worker replacements**, **timesheets**
  (with daily entries and approval history), **audit logs** (with field
  changes and attachments), **roster settings**, **rosters** (with
  worker_records and 14-day day_entries), and **backpay records** (with
  line items).
- Returns JSON whose shape exactly matches each Dart model's
  `fromJson` / `toJson` so the frontend can deserialize without
  translation.
- Wraps multi-table writes (workers + documents + allowances; timesheets
  + daily entries; audit logs + field changes + attachments; backpay +
  line items) in transactions so a failure mid-write leaves no orphans.
- Soft-deletes workers (`is_active = false`) instead of hard-deleting, so
  the FK chain to historical timesheets and audit entries is preserved.

**Why:** Without this, the "100% CRUD" requirement is impossible — there
is literally nothing to talk to.

## 2. Mutations now persist (the "users disappeared between work and home" bug)

**Files:** `lib/services/worker_data_store.dart`,
`lib/services/timesheet_data_store.dart`, `lib/services/audit_service.dart`,
`lib/services/roster_service.dart`, `lib/services/backpay_service.dart`,
`lib/services/api_client.dart`

The previous `WorkerDataStore.addWorker(worker)` was:

```dart
void addWorker(Worker worker, {AppUser? actor}) {
  _workers.add(worker);                  // ← only RAM
  if (actor != null) _audit.log(...);    // ← only RAM
  notifyListeners();                     // ← UI re-renders
}
```

It looked like it worked because the UI updated instantly. But the worker
existed only in the browser tab's memory — refresh the page and it was
gone, sign in from another machine and it was never there.

Every mutation in every store now follows the same pattern:

```dart
Future<void> addWorker(Worker worker, {AppUser? actor}) async {
  _workers.add(worker);
  notifyListeners();             // optimistic — UI is responsive
  try {
    await _api.postJson('/api/workers', worker.toJson());
  } catch (e) {
    _workers.removeWhere((w) => w.id == worker.id);
    notifyListeners();           // roll back so UI matches reality
    rethrow;
  }
  // …audit log…
}
```

The full set of mutations now persisting through the API:

- **Workers:** `addWorker`, `updateWorker`, `deactivateWorker`, `setColaRate`,
  `addAllowance`, `updateAllowance`, `removeAllowance`,
  `updateDocumentStatus`, `addReplacement`.
- **Timesheets:** `addTimesheet`, `updateTimesheet`, `advanceStage`,
  `rejectTimesheet`, `batchAdvance`.
- **Audit:** every `AuditService.log()` call posts the entry (and its
  field changes / attachments) to the chain, so the tamper-evident hash
  chain survives across devices.
- **Roster:** `updateSettings`, `toggleDayPresence`.
- **Backpay:** `calculateForWorker`, `approve`, `disburse`.

`api_client.dart` gained `putJson` / `putRaw` (used by the document
status endpoint) to round out the verb coverage.

**Why:** This is the single most important fix — without it, no amount of
backend wiring would have helped, because the client was throwing away
every change.

## 3. Dashboard KPIs are now live

**File:** `lib/screens/dashboard_screen.dart`

Before:

```dart
_KpiData('Active Workers', '2,847', Icons.people, AppColors.accent, '+12%'),
_KpiData('Corporations',   '14',    Icons.location_city, ...),
_KpiData('Pending Approvals', '23', ...),
_KpiData('This Fortnight', '\$1.2M', ...),
```

After:

```dart
_KpiData('Active Workers', _intFmt.format(scopedActive),         // workers in DB
         Icons.people, AppColors.accent, 'Live'),
_KpiData('Corporations',   '$corporations',                       // distinct corp_id
         Icons.location_city, AppColors.success, 'Seeded'),
_KpiData('Pending Approvals',
         '${countByStages([submitted, coordinatorReview, hrProcessing, accountsProcessing])}',
         Icons.pending_actions, AppColors.warning, 'Action'),
_KpiData('This Fortnight', _moneyFmt.format(fortnightPayroll),    // sum of grandTotal
         Icons.payments, AppColors.brandRed, 'Payroll'),
```

The same treatment was applied to the Coordinator, HR, and "default" KPI
sets. Each role's numbers are computed from the data the user is allowed
to see (`corporationId`-scoped) — not the whole cohort.

The dashboard subscribes to `WorkerDataStore`, `TimesheetDataStore`,
`AuditService` and `BackpayService` via `ChangeNotifier.addListener`,
so KPIs refresh the moment a worker is registered, a timesheet is
approved, or a backpay record is cut. Listeners are removed in
`dispose()` to prevent leaks.

**Why:** A demo that shows "2,847 active workers" while the database has
19 is the textbook "looks fake" objection — it kills the proof of
concept on slide one.

## 4. Recent Activity reflects the real audit chain

**File:** `lib/screens/dashboard_screen.dart`

The four hardcoded "Timesheet submitted for Port of Spain — Group 3 / 2
hours ago" rows are gone. The widget now reads
`AuditService().getAll().take(6)` and renders:

- A formatted line: `<userName> <action> — <entityDisplayName>`
  (e.g. *"Priya Maharaj approved — Kevin Rampersad – NIS Registration"*).
- A relative timestamp (`12m ago`, `3h ago`, `Yesterday`, …).
- An action-specific icon and colour, exhaustively mapped over all 33
  values of `AuditAction`.

Empty-state copy distinguishes the two reasons the feed could be empty:

- API configured but no entries yet → *"No audit entries yet — actions
  taken in the app will appear here."*
- API not configured → *"Backend not configured — set
  --dart-define=API_BASE_URL to load audit history."*

**Why:** The audit table already has 13 seeded entries for the demo
(plus everything users do live); they just weren't being shown.

## 5. Backend status banner

**Files:** `lib/widgets/backend_status_banner.dart` (NEW),
`lib/screens/dashboard_screen.dart`

A new widget pings `/api/health` on first build and every 30 seconds
thereafter. It renders one of:

- **Hidden** when the API responds OK.
- **Orange "Backend not configured"** when `API_BASE_URL` is empty,
  with copy that tells the user the exact `--dart-define` flag to pass.
- **Red "Backend unreachable"** when the API is configured but failing,
  showing the URL it's trying to hit and why the data may be stale.

A refresh button forces an immediate re-check.

**Why:** Previously, an unconfigured / unreachable API was indistinguishable
from "the database is empty". This banner makes that failure mode
visible and recoverable in seconds.

## 6. Schema completeness

**File:** `db/domain_schema.sql`

Two latent gaps that would have surfaced as 500s the first time CRUD
actually round-tripped:

- Added `driver_permit_number TEXT` and `passport_number TEXT` columns to
  `workers`. Both are nullable. The Dart `Worker` model and the
  duplicate-ID guard already used them; the schema didn't.
- Added `'duplicateIdAttempt'` to `audit_action_enum`. The Dart audit
  service emits this action when a registration is blocked because of a
  unique-credential conflict, but the enum didn't accept it — so any such
  audit POST would have thrown.

The `server/index.js` worker handlers were updated to read/write the new
columns.

## 7. One-command demo via Docker Compose

**Files:** `docker-compose.yml` (NEW), `Dockerfile` (updated)

```sh
docker compose up --build
```

…starts:

- `postgres:16-alpine` with `db/rbac_schema.sql`,
  `db/domain_schema.sql`, `db/edit_locks_schema.sql` mounted into
  `/docker-entrypoint-initdb.d/`. They run automatically on first boot
  via the official `postgres` image's init mechanism. The named volume
  `workforce_pgdata` persists data across container restarts, so the
  seed only runs once.
- The new `api` service built from `server/Dockerfile`, with
  `DATABASE_URL` pre-set to point at the `postgres` service. Waits on a
  `pg_isready` healthcheck so it doesn't start before the schema has
  loaded.
- The Flutter web bundle built from the existing root `Dockerfile`,
  served by nginx on `:8081`. The `Dockerfile` now accepts
  `API_BASE_URL` as a build-arg and bakes it into the web build so the
  browser hits the API on `:8080`.

**Why:** It now takes a single command to verify "dummy seed shows in the
UI", "data created at machine A is visible at machine B", and "audit log
survives a refresh".

---

## What I deliberately did **not** change

- **The hardcoded demo logins in `auth_service.dart`** stay. The
  `app_users` table mirrors them, so authentication can be ported to a
  real provider when ready, but per the "kept as proof-of-concept
  credentials" note in the README, I left the in-app map alone.
- **Tamper-evident hash chain.** The chain math was correct; I only
  added persistence. The seed rows still carry the deterministic
  synthetic hashes documented at the top of the audit-log seed.
- **CRUD via direct SQL or PostgREST.** Flutter web cannot safely talk
  to Postgres directly from the browser, and a generic PostgREST mapping
  would have meant rewriting every screen's query shape. A purpose-built
  Express service was the smaller change with a tighter contract.
- **Existing screens' demo flows** (Coordinator/HR/Accounts review,
  rosters, exports). They already used the data stores correctly — once
  the stores started persisting, those screens started persisting too,
  for free.

---

## How to verify the fix

```sh
# 1. Bring everything up
docker compose up --build

# 2. Open http://localhost:8081, sign in as admin@workforce.app / admin123
#    Dashboard should show: Active Workers 19, Corporations 3, Pending
#    Approvals 6, This Fortnight ~$25.5K (numbers will drift as you act).

# 3. Register a new worker via "View Workers" → +. Sign out.

# 4. Open the same URL in an Incognito window, sign in again.
#    The new worker is there. (Previously: it was not.)

# 5. Open DB:
docker compose exec postgres psql -U workforce -d workforce \
  -c 'SELECT id, full_name, is_active FROM workers ORDER BY created_at DESC LIMIT 5;'
#    The new worker is in the table. (Previously: not.)

# 6. Stop the API only:
docker compose stop api
#    Reload the dashboard. The red "Backend unreachable" banner appears
#    within ~30s; data continues to render from the last successful load.
```
