# NPUPS → Supabase (self-hosted / Coolify)

This branch adds the Supabase schema and the Flutter integration layer to move
NPUPS off the in-memory demo onto a real, multi-tenant Postgres backend.

The changes are **additive**: with no Supabase env vars set, the app still runs
on the existing demo `AuthService` / REST `ApiClient`. Supplying the env vars
switches on the Supabase plumbing.

## 1. Provision the database

In the Supabase SQL Editor, run the files in `db/supabase/` in numeric order
(`01_schemas.sql` → `99_rls.sql`). All scripts are idempotent. Full details and
the JWT hook in `db/supabase/README.md`.

Then in Studio → **Settings → API → Exposed schemas** add:

```
npups_core, npups_ref, npups_hr, npups_time, npups_pay, npups_bank
```

(Leave `npups_audit` unexposed.)

## 2. Environment variables to update

### Flutter web build (dart-define) — Coolify build args / Dockerfile

| Variable | Value | Notes |
|----------|-------|-------|
| `SUPABASE_URL` | `https://<your-supabase-domain>` | Your Coolify Supabase Kong/API gateway URL |
| `SUPABASE_ANON_KEY` | `eyJhbGc...` | The **anon / public** key (never the service_role key) |

Pass them at build time, e.g.:

```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://supabase.example.com \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
```

In the `Dockerfile`, forward them into the `flutter build web` step as
`--dart-define` args (add `ARG`/`ENV` for `SUPABASE_URL` and
`SUPABASE_ANON_KEY` and reference them in the build command).

> The anon key is public by design — RLS (step 9) is what enforces tenant
> isolation. Do **not** ship the `service_role` key in the Flutter bundle.

### Backend / server (only if you keep `server/index.js`)

| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Postgres connection string to the Supabase DB |
| `SUPABASE_JWT_SECRET` | (recommended) verify incoming bearer JWTs server-side |

## 3. Remaining app wiring (follow-up, intentionally staged)

The schema accessors and auth wrapper are in place; the data stores still call
the REST `ApiClient`. To complete the cutover, migrate each store to `Db`:

- [ ] `lib/services/worker_data_store.dart` → `Db.workers()` / `Db.workerReplacements()`
- [ ] `lib/services/timesheet_data_store.dart` → `Db.timesheets()` / `Db.timesheetDailyEntries()`
- [ ] `lib/services/roster_service.dart` → `Db.rosters()` / `Db.rosterDayEntries()`
- [ ] `lib/services/backpay_service.dart` → `Db.backpayRecords()`
- [ ] `lib/services/audit_service.dart` → `Db.client.schema('npups_audit')...` (read-only)
- [ ] `lib/screens/login_screen.dart` + `lib/main.dart` → swap demo `AuthService`
      for `SupabaseAuthService`, then remove demo accounts + the role switcher
- [ ] `test/unit/auth_service_test.dart` → update for the real auth flow

Each is mechanical: replace `_api.getList('/api/x')` with
`await Db.x().select()` and `_api.postJson(...)` with `await Db.x().insert(...)`.

## Note on this PR

No Flutter/Dart toolchain was available in the authoring environment, so
`flutter analyze` / `dart format` were not run here — CI (`.github/workflows/test.yml`)
is the first place they execute. If the format check flags anything, a single
`dart format .` pass will resolve it.
