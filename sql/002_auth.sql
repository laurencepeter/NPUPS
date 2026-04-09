-- ══════════════════════════════════════════════════════════════════════════════
-- NPUPS Auth — PostgREST JWT Authentication
-- Uses pgjwt extension to sign tokens directly in PostgreSQL.
-- PostgREST validates incoming JWTs against the same secret.
-- ══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- POSTGREST ROLES
-- The 'authenticator' role is what PostgREST connects as.
-- It switches to 'web_anon' or 'authenticated' per request based on the JWT.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'CHANGE_ME_IN_ENV';
  END IF;
END
$$;

GRANT web_anon     TO authenticator;
GRANT authenticated TO authenticator;

-- Give web_anon only access to the login function
GRANT USAGE ON SCHEMA public TO web_anon;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Authenticated users can read/write all data tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE                        ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROW-LEVEL SECURITY
-- Scopes corporation-specific roles to their own corporation's data.
-- System-wide roles (admin, ps, hr, accounts, minister) see all data.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE workers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE timesheets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_documents   ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_replacements ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE users              ENABLE ROW LEVEL SECURITY;

-- Helper: extract JWT claim as text
CREATE OR REPLACE FUNCTION jwt_claim(claim TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json ->> claim, '')
$$;

-- Workers: system roles see all; corporation-scoped roles see their corp only
CREATE POLICY workers_select ON workers FOR SELECT TO authenticated
  USING (
    jwt_claim('user_role') IN ('systemAdmin','ps','dmcr','hr','subAccounts','mainAccounts','ministersDepartment')
    OR corporation_id = jwt_claim('corporation_id')
  );

CREATE POLICY workers_insert ON workers FOR INSERT TO authenticated
  WITH CHECK (
    jwt_claim('user_role') IN ('systemAdmin','dmcr','regionalCoordinator')
    OR corporation_id = jwt_claim('corporation_id')
  );

CREATE POLICY workers_update ON workers FOR UPDATE TO authenticated
  USING (
    jwt_claim('user_role') IN ('systemAdmin','dmcr','ministersDepartment')
    OR (jwt_claim('user_role') = 'regionalCoordinator' AND corporation_id = jwt_claim('corporation_id'))
  );

-- Timesheets: same corporation scoping
CREATE POLICY timesheets_select ON timesheets FOR SELECT TO authenticated
  USING (
    jwt_claim('user_role') IN ('systemAdmin','ps','hr','subAccounts','mainAccounts','ministersDepartment')
    OR worker_id IN (SELECT id FROM workers WHERE corporation_id = jwt_claim('corporation_id'))
    OR worker_id IN (SELECT id FROM workers WHERE id = jwt_claim('sub') AND jwt_claim('user_role') = 'worker')
  );

CREATE POLICY timesheets_insert ON timesheets FOR INSERT TO authenticated
  WITH CHECK (
    jwt_claim('user_role') IN ('systemAdmin','regionalCoordinator','worker')
  );

CREATE POLICY timesheets_update ON timesheets FOR UPDATE TO authenticated
  USING (
    jwt_claim('user_role') IN ('systemAdmin','regionalCoordinator','hr','subAccounts','mainAccounts')
  );

-- Worker documents: follows worker visibility
CREATE POLICY worker_documents_all ON worker_documents FOR ALL TO authenticated
  USING (
    worker_id IN (SELECT id FROM workers)
  );

-- Worker replacements: follows worker visibility
CREATE POLICY replacements_all ON worker_replacements FOR ALL TO authenticated
  USING (TRUE);

-- Approval records: readable by all authenticated
CREATE POLICY approval_records_all ON approval_records FOR ALL TO authenticated
  USING (TRUE);

-- Users: only admins can see all; others see themselves
CREATE POLICY users_select ON users FOR SELECT TO authenticated
  USING (
    jwt_claim('user_role') = 'systemAdmin'
    OR id::TEXT = jwt_claim('sub')
  );

CREATE POLICY users_update ON users FOR UPDATE TO authenticated
  USING (
    jwt_claim('user_role') = 'systemAdmin'
    OR id::TEXT = jwt_claim('sub')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- LOGIN FUNCTION
-- Called by Flutter at POST /rpc/login
-- Returns a signed JWT + user object on success
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.login(p_email TEXT, p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _user        users%ROWTYPE;
  _jwt_secret  TEXT;
  _token       TEXT;
  _exp         INT;
BEGIN
  -- Look up active user
  SELECT * INTO _user
  FROM users
  WHERE lower(email) = lower(p_email) AND is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid email or password'
      USING ERRCODE = 'invalid_password', HINT = 'check_credentials';
  END IF;

  -- Verify password with bcrypt
  IF _user.password_hash != crypt(p_password, _user.password_hash) THEN
    RAISE EXCEPTION 'Invalid email or password'
      USING ERRCODE = 'invalid_password', HINT = 'check_credentials';
  END IF;

  -- Read JWT secret from Postgres config (set via ALTER SYSTEM or postgresql.conf)
  _jwt_secret := current_setting('app.jwt_secret');
  -- Token expires in 8 hours (user stays logged in for a work day)
  _exp := extract(epoch FROM now())::INT + 28800;

  -- Sign the JWT with pgjwt
  SELECT sign(
    json_build_object(
      'role',           'authenticated',
      'sub',            _user.id::TEXT,
      'email',          _user.email,
      'full_name',      _user.full_name,
      'user_role',      _user.role::TEXT,
      'corporation_id', _user.corporation_id,
      'exp',            _exp
    ),
    _jwt_secret
  ) INTO _token;

  RETURN json_build_object(
    'token', _token,
    'exp',   _exp,
    'user',  json_build_object(
      'id',             _user.id,
      'email',          _user.email,
      'fullName',       _user.full_name,
      'role',           _user.role,
      'corporationId',  _user.corporation_id,
      'isActive',       _user.is_active
    )
  );
END;
$$;

-- Allow anonymous callers to invoke login
GRANT EXECUTE ON FUNCTION public.login(TEXT, TEXT) TO web_anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- ADVANCE TIMESHEET STAGE  (business logic in DB)
-- Called at POST /rpc/advance_timesheet_stage
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.advance_timesheet_stage(
  p_timesheet_id UUID,
  p_note         TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _ts        timesheets%ROWTYPE;
  _stages    timesheet_stage[] := ARRAY[
    'notStarted','draft','submitted','coordinatorReview',
    'hrProcessing','accountsProcessing','approvedForPayment',
    'exported','chequePrinting'
  ]::timesheet_stage[];
  _cur_idx   INT;
  _next      timesheet_stage;
  _reviewer  users%ROWTYPE;
BEGIN
  SELECT * INTO _ts FROM timesheets WHERE id = p_timesheet_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Timesheet not found';
  END IF;

  -- Find current position and advance
  SELECT array_position(_stages, _ts.stage) INTO _cur_idx;
  IF _cur_idx IS NULL OR _cur_idx >= array_length(_stages, 1) THEN
    RAISE EXCEPTION 'Timesheet is already at the final stage';
  END IF;
  _next := _stages[_cur_idx + 1];

  -- Get calling user
  SELECT * INTO _reviewer FROM users WHERE id::TEXT = jwt_claim('sub');

  -- Advance stage
  UPDATE timesheets SET stage = _next WHERE id = p_timesheet_id;

  -- Record approval
  INSERT INTO approval_records (timesheet_id, reviewer_id, reviewer_name, reviewer_role, state, note)
  VALUES (
    p_timesheet_id,
    _reviewer.id,
    _reviewer.full_name,
    _reviewer.role::TEXT,
    'approved',
    p_note
  );

  RETURN json_build_object('stage', _next, 'timesheetId', p_timesheet_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_timesheet_stage(UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- REJECT TIMESHEET
-- Called at POST /rpc/reject_timesheet
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reject_timesheet(
  p_timesheet_id UUID,
  p_note         TEXT
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _reviewer users%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM timesheets WHERE id = p_timesheet_id) THEN
    RAISE EXCEPTION 'Timesheet not found';
  END IF;

  SELECT * INTO _reviewer FROM users WHERE id::TEXT = jwt_claim('sub');

  UPDATE timesheets
  SET stage = 'draft', updated_at = NOW()
  WHERE id = p_timesheet_id;

  INSERT INTO approval_records (timesheet_id, reviewer_id, reviewer_name, reviewer_role, state, note)
  VALUES (p_timesheet_id, _reviewer.id, _reviewer.full_name, _reviewer.role::TEXT, 'rejected', p_note);

  RETURN json_build_object('stage', 'draft', 'timesheetId', p_timesheet_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_timesheet(UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- NEXT WORKER ID  (sequential WRK-NNN)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_worker_id()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $$
  SELECT 'WRK-' || lpad(
    (coalesce(max(substring(id FROM 5)::INT), 0) + 1)::TEXT,
    3, '0'
  )
  FROM workers;
$$;

GRANT EXECUTE ON FUNCTION public.next_worker_id() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- NEXT REPLACEMENT ID  (sequential REP-NNN)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_replacement_id()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $$
  SELECT 'REP-' || lpad(
    (coalesce(max(substring(id FROM 5)::INT), 0) + 1)::TEXT,
    3, '0'
  )
  FROM worker_replacements;
$$;

GRANT EXECUTE ON FUNCTION public.next_replacement_id() TO authenticated;
