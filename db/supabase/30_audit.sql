-- =============================================================================
-- NPUPS — Append-only audit log (Step 4 of 9)
-- =============================================================================
-- Plain (non-partitioned) table — simple to run on any Supabase plan. UPDATE/
-- DELETE are revoked so rows are tamper-resistant; writes go through
-- service_role only (see RLS in 99_rls.sql).
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_audit.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  actor_user_id uuid,
  actor_email citext,
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  before_data jsonb,
  after_data jsonb,
  ip_address inet,
  user_agent text,
  previous_hash bytea,
  hash bytea NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- Access-path indexes. Each backs a specific, intended read pattern for the
-- audit trail — they mirror the query methods in lib/services/audit_service.dart
-- and the RLS policy in 99_rls.sql.
--
-- NOTE ON THE SUPABASE "unused index" LINT (0005):
-- https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index
-- These indexes will be flagged as unused until the audit-viewer feature issues
-- reads against npups_audit.audit_logs. That is expected on a fresh deployment:
-- the current Node backend (server/index.js) reads the parallel demo tables
-- (app_audit_logs, seeded in db/domain_schema.sql), so nothing has SELECTed from
-- this Supabase table yet. The lint is INFO-level and safe to ignore here — do
-- NOT drop these to silence it, or the first tenant-scoped audit read will fall
-- back to a sequential scan on an append-only, ever-growing table.

-- Primary read path: tenant-scoped, newest-first listing. Also backs the RLS
-- `audit_read` filter (corporation_id = npups_core.current_corp()) that gates
-- every read of this table, so this index in particular must be retained.
CREATE INDEX IF NOT EXISTS audit_logs_corp_time_idx
  ON npups_audit.audit_logs (corporation_id, occurred_at DESC);
-- "History for this resource" lookups (cf. AuditService.getForEntity).
CREATE INDEX IF NOT EXISTS audit_logs_resource_idx
  ON npups_audit.audit_logs (resource_type, resource_id);
-- "Actions by this user", newest-first (cf. AuditService.getForUser).
CREATE INDEX IF NOT EXISTS audit_logs_actor_idx
  ON npups_audit.audit_logs (actor_user_id, occurred_at DESC);

REVOKE UPDATE, DELETE ON npups_audit.audit_logs FROM PUBLIC;
