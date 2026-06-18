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

## 2. Environment variables — `.env` + Coolify (do both)

Flutter web compiles to static JS, so `SUPABASE_URL` / `SUPABASE_ANON_KEY` must
be present **at `flutter build` time** — they are baked into the bundle. There
is no runtime env-var read in the browser. That makes the layout:

| Where | Purpose | Committed? |
|-------|---------|------------|
| `.env.example` | Template documenting which keys exist | ✅ yes |
| `.env` (root) | Local dev convenience | ❌ gitignored |
| **Coolify → Build Environment Variables** | Production source of truth | (Coolify-managed) |

| Variable | Value | Notes |
|----------|-------|-------|
| `SUPABASE_URL` | `https://<your-supabase-domain>` | Your Coolify Supabase Kong/API gateway URL |
| `SUPABASE_ANON_KEY` | `eyJhbGc...` | The **anon / public** key (never the service_role key) |

> The anon key is **public by design** — it appears in the compiled JS bundle no
> matter how you provide it. Security comes from RLS (script `99_rls.sql`), not
> from hiding the anon key. The `service_role` key must never touch the Flutter
> code or any build arg.

### Local dev — using `.env`

```bash
cp .env.example .env          # one-time
# edit .env with your values

flutter run -d chrome --dart-define-from-file=.env
# or
flutter build web --release --dart-define-from-file=.env
```

`.env` is gitignored, so values never leave your machine.

### Production — Coolify

1. **Coolify dashboard → your NPUPS service → Environment Variables**, set as
   *Build* (not Runtime) variables:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
2. **Build command / image** — the `Dockerfile` already declares matching
   `ARG`s and forwards them into `flutter build web --dart-define=...`. Make
   sure Coolify passes the env vars as build args (in Coolify's Dockerfile
   build, "Build Variables" or equivalent → toggle "Pass as build arg"). With
   docker build directly:
   ```bash
   docker build \
     --build-arg SUPABASE_URL=$SUPABASE_URL \
     --build-arg SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
     -t npups-web .
   ```

### Why both?

| Scenario | What protects you |
|----------|-------------------|
| Dev pushes code to git | `.gitignore` keeps `.env` out of history |
| Dev runs `flutter run` locally | `--dart-define-from-file=.env` injects values |
| Coolify rebuilds on push | Build env vars → ARGs → `--dart-define` |
| Browser DevTools opens the bundle | Anon key visible (expected); RLS denies cross-tenant data |
| A team member rotates the anon key | Update Coolify (prod) + your local `.env`; redeploy |

### Backend / server (only if you keep `server/index.js`)

> ⚠️ **Different schema from the `db/supabase/` scripts above.** The REST server
> (`server/index.js`) queries flat, denormalised tables in the **`public`**
> schema (`public.workers`, `public.timesheets`, …) — it does **not** use the
> `npups_*` multi-schema layout. If you run the server and only loaded
> `db/supabase/*.sql`, every request fails with
> `relation "public.workers" does not exist`.
>
> **To run the server, load `db/domain_schema.sql` into your database** (Supabase
> SQL Editor, or `psql "$DATABASE_URL" -f db/domain_schema.sql`). It creates all
> the tables the server expects in `public`, plus seed data, and is independent
> of `db/rbac_schema.sql`. The server connects with the anon key and no RLS, so
> it relies on the default `public`-schema grants Supabase gives the `anon` role.
>
> The `db/supabase/*.sql` (`npups_*`) scripts are for the direct
> Flutter→Supabase path (`lib/.../Db`), which is a separate, staged migration —
> see section 3 below. Pick one backend; the two schemas are not interchangeable.

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
