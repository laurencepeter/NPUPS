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

## Endpoints

| Verb   | Path                                                       | Notes                                           |
|--------|------------------------------------------------------------|-------------------------------------------------|
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
