-- =============================================================================
-- NPUPS — Row-Level Security & tenant isolation (Step 9 of 9)
-- =============================================================================
-- Every table with a corporation_id is restricted to the caller's tenant.
-- The tenant is read from the JWT custom claim `corporation_id` (set by the
-- Auth access-token hook — see db/supabase/README.md). Global/platform users
-- (npups_core.app_users.is_global = true) bypass the tenant filter.
-- =============================================================================

-- Tenant claim from the request JWT.
CREATE OR REPLACE FUNCTION npups_core.current_corp()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(
    current_setting('request.jwt.claims', true)::jsonb ->> 'corporation_id',
    ''
  )::uuid;
$$;

-- Is the signed-in user a global/platform admin?
CREATE OR REPLACE FUNCTION npups_core.is_global()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT is_global FROM npups_core.app_users WHERE id = auth.uid()),
    false
  );
$$;

-- Apply a uniform tenant-isolation policy to every table that has a
-- corporation_id column across the business schemas.
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT format('%I.%I', n.nspname, c.relname) AS tbl
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'corporation_id'
    WHERE n.nspname IN ('npups_core','npups_hr','npups_time','npups_pay','npups_bank')
      AND c.relkind = 'r'
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t.tbl);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %s', t.tbl);
    EXECUTE format($p$
      CREATE POLICY tenant_isolation ON %s FOR ALL TO authenticated
      USING (corporation_id = npups_core.current_corp() OR npups_core.is_global())
      WITH CHECK (corporation_id = npups_core.current_corp() OR npups_core.is_global())
    $p$, t.tbl);
  END LOOP;
END $$;

-- Audit log: same-tenant read for authenticated users, insert by service_role.
ALTER TABLE npups_audit.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_read   ON npups_audit.audit_logs;
DROP POLICY IF EXISTS audit_insert ON npups_audit.audit_logs;

CREATE POLICY audit_read ON npups_audit.audit_logs FOR SELECT TO authenticated
  USING (corporation_id = npups_core.current_corp() OR npups_core.is_global());

CREATE POLICY audit_insert ON npups_audit.audit_logs FOR INSERT TO service_role
  WITH CHECK (true);
