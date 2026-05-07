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
```

Sanity-check the seed counts:

```sql
SELECT count(*) FROM workers;                  -- 19
SELECT count(*) FROM timesheets;               -- 17
SELECT count(*) FROM timesheet_daily_entries;  -- 238
SELECT count(*) FROM rosters;                  -- 6
SELECT count(*) FROM app_audit_logs;           -- 13
```

# Wiring the frontend to the backend

The Flutter app talks to the backend exclusively through
`lib/services/api_client.dart`. The base URL is supplied at build time:

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8080
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
```

When `API_BASE_URL` is unset the client returns empty results so the UI
renders blank lists — useful when the database has been seeded but no
backend service has been stood up yet. After login,
`Bootstrap.loadAll()` fans out to:

| Endpoint | Store |
|---|---|
| `GET /api/workers` | `WorkerDataStore` |
| `GET /api/worker-replacements` | `WorkerDataStore` |
| `GET /api/timesheets` | `TimesheetDataStore` |
| `GET /api/audit-logs` | `AuditService` |
| `GET /api/roster-settings` | `RosterService` |
| `GET /api/rosters` | `RosterService` |
| `GET /api/backpay-records` | `BackpayService` |
