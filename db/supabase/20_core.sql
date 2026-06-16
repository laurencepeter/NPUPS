-- =============================================================================
-- NPUPS — Core: corporations, users, roles (Step 3 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_core.corporations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  country_iso2 char(2) REFERENCES npups_ref.countries,
  base_currency char(3) REFERENCES npups_ref.currencies,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

-- app_users.id mirrors auth.users.id (one row per Supabase Auth user).
CREATE TABLE IF NOT EXISTS npups_core.app_users (
  id uuid PRIMARY KEY,
  email citext NOT NULL UNIQUE,
  full_name text,
  corporation_id uuid REFERENCES npups_core.corporations,
  is_global boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS npups_core.roles (
  code text PRIMARY KEY,
  name text NOT NULL
);

CREATE TABLE IF NOT EXISTS npups_core.user_roles (
  user_id uuid REFERENCES npups_core.app_users ON DELETE CASCADE,
  role_code text REFERENCES npups_core.roles,
  corporation_id uuid REFERENCES npups_core.corporations,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_code, corporation_id)
);

CREATE INDEX IF NOT EXISTS app_users_corp_idx  ON npups_core.app_users (corporation_id);
CREATE INDEX IF NOT EXISTS user_roles_corp_idx ON npups_core.user_roles (corporation_id);

INSERT INTO npups_core.roles(code, name) VALUES
  ('system_admin','System Administrator'),
  ('ps','Permanent Secretary'),
  ('dmcr','DMCR'),
  ('regional_coordinator','Regional Coordinator'),
  ('hr','HR'),
  ('sub_accounts','Sub Accounts'),
  ('main_accounts','Main Accounts'),
  ('executive','Executive'),
  ('worker','Worker')
ON CONFLICT DO NOTHING;
