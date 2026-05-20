# WorkForce

**Developed by Laurence Peter · Built with AI support**

Digital workflow for employee enrollment, payroll processing, and HR reporting. Replaces paper-based workflows with an end-to-end digital platform built on Flutter and self-hosted Supabase.

The system covers the complete lifecycle: Programme Initiation, Worker Data Compilation, Employment Processing, Payroll Processing, Payment Authorisation & Disbursement, and Fortnightly Recurring Cycle.

**Primary Objectives:**
- Eliminate paper forms from worker registration through payment
- Provide real-time visibility into worker file status across all departments
- Automate timesheet collection, Return of Personnel generation, and payroll package assembly
- Enforce role-based access control (RBAC) with full audit trail
- Reduce worker time-to-first-payment from weeks to days
- Deploy to a self-hosted, dockerised environment


# Animations & UX
Staggered entrance: Logo → Title → Card → Button fade+slide in sequence (1.4s total)
Floating particles: 20 softly animated dots on the gradient background
Shake on error: Card shakes with elastic curve on invalid login
Pulse glow: Sign-in button has a breathing shadow effect
Page transitions: AnimatedSwitcher with slide+fade between login and authenticated shell
Dashboard cards: Staggered slide-up entrance per card


# Workflow Phases

1. **Programme Initiation** — Director dashboard with approval counts
2. **Worker Data Compilation** — Coordinator views, document upload
3. **Employment Processing** — HR dashboard with payroll queue and employment notes
4. **Payroll Processing** — Sub-Accounts KPIs (pay sheets, vouchers)
5. **Payment & Disbursement** — Main Accounts cheque tracking
6. **Fortnightly Cycle** — Full timesheet entry with 14-day attendance grid, auto-calculations, and sign-off workflow


# Demo Accounts

These are the **only** hardcoded values left in the frontend — they exist as
proof-of-concept credentials so a freshly deployed demo can be signed into
without the auth backend wired up. All other data (workers, timesheets,
rosters, audit logs, backpay) has been moved to the PostgreSQL database.

| Email | Password | Role |
|---|---|---|
| admin@workforce.app | admin123 | System Admin — views all data |
| coordinator@workforce.app | test123 | Regional Coordinator |
| hr@workforce.app | test123 | HR Department |
| worker@workforce.app | test123 | Worker |
| accounts@workforce.app | test123 | Sub-Accounts Clerk |
| ps@workforce.app | test123 | Director |
| mainaccounts@workforce.app | test123 | Main Accounts Clerk |
| executive@workforce.app | test123 | Executive Department |

# Database

The frontend no longer carries any hardcoded worker/timesheet/roster/audit
data — every row originates in PostgreSQL.

```sh
# Apply the RBAC schema first, then the domain schema + seed.
psql "$DATABASE_URL" -f db/rbac_schema.sql
psql "$DATABASE_URL" -f db/domain_schema.sql
psql "$DATABASE_URL" -f db/edit_locks_schema.sql
```

Sanity-check the seed counts:

```sql
SELECT count(*) FROM workers;                  -- 19
SELECT count(*) FROM timesheets;               -- 17
SELECT count(*) FROM timesheet_daily_entries;  -- 238
SELECT count(*) FROM rosters;                  -- 6
SELECT count(*) FROM app_audit_logs;           -- 13
```

# Backend service

The Flutter app talks to a small Node.js + Express + `pg` API in `server/`
(see `server/README.md` for the endpoint table). The API is the **only**
process that touches PostgreSQL — the browser does not connect to it
directly.

The browser calls `/api/*` on the **same origin** it was served from; nginx
forwards those requests to the API (`API_UPSTREAM`, default `http://api:8080`).
This means no backend URL is baked into the web build, the deployed bundle
needs no per-environment rebuild, and there is no cross-origin CORS preflight
on every request. To point the app at a backend on a *different* origin,
build with `--dart-define=API_BASE_URL=https://api.example.com` — an explicit
value always overrides the same-origin default.

# One-command demo (recommended)

```sh
docker compose up --build
```

That brings up:

| Container | Port | Purpose |
|---|---|---|
| `postgres` | 5432 | Postgres 16 with `db/*.sql` auto-loaded on first boot |
| `api`      | 8080 | The REST backend (`server/`) — `GET /api/health` for liveness |
| `web`      | 8081 | Flutter web served by nginx; `/api/*` proxied to the `api` service |

Open <http://localhost:8081> and sign in with one of the demo accounts
above. The dashboard will load the seeded 19 workers / 17 timesheets / 13
audit entries, and any worker you register at this machine will show up on
any other machine pointed at the same Postgres.

If the dashboard shows a red "Backend unreachable" banner, the `api`
container is down or `API_UPSTREAM` points at the wrong host — check
`docker compose logs api` and confirm <http://localhost:8080/api/health>
responds.

# Manual run (without Docker)

```sh
# 1. Postgres + schemas
createdb workforce
psql workforce -f db/rbac_schema.sql
psql workforce -f db/domain_schema.sql
psql workforce -f db/edit_locks_schema.sql

# 2. API
cd server
npm install
DATABASE_URL=postgres://localhost/workforce PORT=8080 npm start

# 3. Flutter web pointed at the API
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

`flutter run` serves the app from its own dev-server origin, which has no
`/api` proxy, so the `--dart-define` above is required for local dev.

For a release build, no API URL is needed — the bundle reaches the backend
through the nginx `/api` proxy (see "Backend service" above):

```sh
flutter build web --release
```

Only pass `--dart-define=API_BASE_URL=...` if the backend lives on a
different origin than the one serving the web app.

# Frontend ↔ backend contract

After login, `Bootstrap.loadAll()` fans out to:

| Endpoint | Store |
|---|---|
| `GET /api/workers` | `WorkerDataStore` |
| `GET /api/worker-replacements` | `WorkerDataStore` |
| `GET /api/timesheets` | `TimesheetDataStore` |
| `GET /api/audit-logs` | `AuditService` |
| `GET /api/roster-settings` | `RosterService` |
| `GET /api/rosters` | `RosterService` |
| `GET /api/backpay-records` | `BackpayService` |

Mutations round-trip through the same client. Each store performs an
optimistic local update first, then `POST` / `PATCH` / `DELETE`s to the
API; on backend rejection the local change is rolled back and listeners
are notified again so the UI re-renders with the canonical state. See
`PATCH_NOTES.md` for the list of mutations that were silently in-memory
before this change.

If the API is unreachable the dashboard shows a banner explaining the
failure mode instead of silently rendering empty — this used to be the
cause of the "I created users at work but they're not at home" complaint.
