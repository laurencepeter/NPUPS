# WorkForce API

REST backend that bridges the Flutter frontend to the PostgreSQL schemas in
`db/`. All JSON shapes match the `toJson` / `fromJson` of the corresponding
Dart model, so the frontend can deserialise without translation.

## Local run

```sh
psql "$DATABASE_URL" -f ../db/rbac_schema.sql
psql "$DATABASE_URL" -f ../db/domain_schema.sql

cd server
npm install
DATABASE_URL=postgres://workforce:workforce@localhost:5432/workforce \
PORT=8080 npm start
```

Then point the Flutter app at it:

```sh
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

## Authentication & authorization

The API is the only process that reaches the database, so it enforces auth
there.

- **Fail-secure.** With `API_JWT_SECRET` set (min 32 chars), every `/api` route
  except `/api/health`, `/api/ready`, and `/api/auth/login` requires a valid
  `Authorization: Bearer <token>`. In `NODE_ENV=production` the server refuses
  to start without the secret. Running open is possible only outside production
  and only with `ALLOW_INSECURE_NO_AUTH=true` (local demo / CI), which logs a
  loud warning.
- **Login.** `POST /api/auth/login {email,password}` verifies the password
  against a scrypt hash (`app_users.password_hash`, constant-time compare — no
  bcrypt/native dependency) and returns a short-lived HS256 JWT carrying the
  user's id, role, and corporation. Failures are uniform (no user enumeration).
- **RBAC.** `PUT/DELETE /api/rate-tables/*` and `PATCH /api/roster-settings/*`
  require the `systemAdmin` role; all other data routes require authentication.
- **Hardening.** `helmet` security headers, a CORS allowlist
  (`CORS_ALLOWED_ORIGINS`, empty ⇒ same-origin only), a global rate limit plus a
  tight limit on `/api/auth/login`, request-body validation on rate-table
  writes, and generic 500s that never leak internals in production.

See `.env.example` for all variables. Generate a secret with
`openssl rand -base64 48`.

**Existing databases** (that predate `password_hash`) need a one-time migration
before auth can be enabled — the schema files rebuild from scratch, so don't
re-run them on live data:

```sql
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS password_hash text;
-- then set a hash per user (see the UPDATE statements in db/domain_schema.sql,
-- or issue your own via the app's password flow).
```

## Endpoints

| Verb   | Path                                                       | Notes                                           |
|--------|------------------------------------------------------------|-------------------------------------------------|
| POST   | `/api/auth/login`                                          | Exchange email+password for a JWT (public)      |
| GET    | `/api/health`                                              | Liveness + DB ping                              |
| GET    | `/api/workers`                                             | List with documents + custom allowances inline  |
| GET    | `/api/workers/:id`                                         | Single worker                                   |
| POST   | `/api/workers`                                             | Create worker                                   |
| PATCH  | `/api/workers/:id`                                         | Partial update (any subset of editable cols)    |
| DELETE | `/api/workers/:id`                                         | Soft-delete (sets `is_active = false`)          |
| POST   | `/api/workers/:id/allowances`                              | Add custom allowance                            |
| PATCH  | `/api/worker-allowances/:id`                               | Update custom allowance                         |
| DELETE | `/api/worker-allowances/:id`                               | Remove custom allowance                         |
| PUT    | `/api/workers/:id/documents/:name`                         | Set status / file_name for a worker's document  |
| GET    | `/api/worker-replacements`                                 | List                                            |
| POST   | `/api/worker-replacements`                                 | Add (upserts on `original_worker_id`)           |
| GET    | `/api/timesheets`                                          | List with daily entries + approvals inline      |
| POST   | `/api/timesheets`                                          | Create                                          |
| PATCH  | `/api/timesheets/:id`                                      | Update stage / allowance_days / remarks / days  |
| POST   | `/api/timesheets/:id/approvals`                            | Append approval record                          |
| GET    | `/api/audit-logs`                                          | Full chain with field changes + attachments     |
| POST   | `/api/audit-logs`                                          | Append entry (frontend computes hash)           |
| GET    | `/api/roster-settings`                                     | List per-corporation settings                   |
| PATCH  | `/api/roster-settings/:corporationId`                      | Upsert settings                                 |
| GET    | `/api/rosters`                                             | List with worker_records + day_entries inline   |
| PUT    | `/api/rosters/:rosterId/workers/:workerId/days/:dayIndex`  | Update presence/absence reason for a single day |
| GET    | `/api/backpay-records`                                     | List with line items inline                     |
| POST   | `/api/backpay-records`                                     | Create                                          |
| PATCH  | `/api/backpay-records/:id`                                 | Update status                                   |
| GET    | `/api/rate-tables`                                         | List effective-dated statutory rate sets        |
| PUT    | `/api/rate-tables/:id`                                     | Upsert a rate set (admin)                        |
| DELETE | `/api/rate-tables/:id`                                     | Remove a rate set (admin)                        |
