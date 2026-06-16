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

CREATE INDEX IF NOT EXISTS audit_logs_corp_time_idx
  ON npups_audit.audit_logs (corporation_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_resource_idx
  ON npups_audit.audit_logs (resource_type, resource_id);
CREATE INDEX IF NOT EXISTS audit_logs_actor_idx
  ON npups_audit.audit_logs (actor_user_id, occurred_at DESC);

REVOKE UPDATE, DELETE ON npups_audit.audit_logs FROM PUBLIC;
