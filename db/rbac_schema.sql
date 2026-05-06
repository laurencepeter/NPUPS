-- =============================================================================
-- NPUPS - Database-Driven Role-Based Access Control (RBAC) Schema
-- =============================================================================
-- PostgreSQL script that fully replaces the current hardcoded users / roles /
-- permissions logic with a normalized, extensible, audit-friendly schema.
--
-- Design highlights:
--   * UUID primary keys everywhere (gen_random_uuid via pgcrypto).
--   * created_at / updated_at / deleted_at on every business table.
--   * Many-to-many user<->role and role<->permission tables.
--   * Permissions stored as (resource, action) pairs for granularity.
--   * Audit log table (audit_logs) consumed by the existing frontend.
--   * Views to support legacy "role check" code paths cleanly.
--   * Trigger to maintain updated_at automatically.
--   * Indexes on every FK / join column / commonly filtered column.
--   * Seed data: 5 roles, 14 permissions, 12 users distributed across roles.
--
-- The script is idempotent within a fresh database (uses IF NOT EXISTS where
-- possible) and can be executed top-to-bottom without modification.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid(), crypt()
CREATE EXTENSION IF NOT EXISTS "citext";     -- case-insensitive emails

-- -----------------------------------------------------------------------------
-- Drop existing objects (safe re-run during development)
-- -----------------------------------------------------------------------------
DROP VIEW  IF EXISTS admin_users_view        CASCADE;
DROP VIEW  IF EXISTS standard_users_view     CASCADE;
DROP VIEW  IF EXISTS user_permissions_view   CASCADE;
DROP VIEW  IF EXISTS active_user_roles_view  CASCADE;

DROP TABLE IF EXISTS audit_logs              CASCADE;
DROP TABLE IF EXISTS role_permissions        CASCADE;
DROP TABLE IF EXISTS user_roles              CASCADE;
DROP TABLE IF EXISTS permissions             CASCADE;
DROP TABLE IF EXISTS roles                   CASCADE;
DROP TABLE IF EXISTS users                   CASCADE;

DROP FUNCTION IF EXISTS set_updated_at()     CASCADE;
DROP FUNCTION IF EXISTS user_has_permission(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS user_has_role(UUID, TEXT)       CASCADE;

-- -----------------------------------------------------------------------------
-- Helper: trigger function to maintain updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Core tables
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users
-- -----------------------------------------------------------------------------
-- Stores account identity only. Roles / permissions live in their own tables
-- so they can be changed at runtime without code changes.
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email           CITEXT      NOT NULL UNIQUE,
    username        VARCHAR(64) NOT NULL UNIQUE,
    -- Stores a hash (bcrypt / argon2 / scrypt). Never plaintext.
    password_hash   TEXT        NOT NULL,
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,            -- soft delete
    CONSTRAINT users_password_hash_not_plain CHECK (length(password_hash) >= 20)
);

CREATE INDEX idx_users_email          ON users (email)        WHERE deleted_at IS NULL;
CREATE INDEX idx_users_username       ON users (username)     WHERE deleted_at IS NULL;
CREATE INDEX idx_users_is_active      ON users (is_active)    WHERE deleted_at IS NULL;
CREATE INDEX idx_users_deleted_at     ON users (deleted_at);
CREATE INDEX idx_users_last_login_at  ON users (last_login_at);

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- roles
-- -----------------------------------------------------------------------------
-- Roles are *data*, not enums. New roles are inserted into this table with no
-- schema or code change required. `is_system` flags built-in roles that the
-- application should not allow deletion of via the admin UI.
-- -----------------------------------------------------------------------------
CREATE TABLE roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(64) NOT NULL UNIQUE,   -- machine name, e.g. 'admin'
    label       VARCHAR(128) NOT NULL,         -- human-readable, e.g. 'Administrator'
    description TEXT,
    is_system   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_roles_name       ON roles (name)      WHERE deleted_at IS NULL;
CREATE INDEX idx_roles_is_system  ON roles (is_system) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- permissions
-- -----------------------------------------------------------------------------
-- Permissions are modelled as (resource, action) so the app can ask
-- "can this user do `delete` on `user`?" rather than relying on a role name.
-- The combined `name` (e.g. 'user.delete') gives a stable wire identifier.
-- -----------------------------------------------------------------------------
CREATE TABLE permissions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(128) NOT NULL UNIQUE,   -- e.g. 'user.delete', 'report.view'
    resource    VARCHAR(64)  NOT NULL,          -- e.g. 'user'
    action      VARCHAR(64)  NOT NULL,          -- e.g. 'delete'
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ,
    CONSTRAINT permissions_resource_action_unique UNIQUE (resource, action)
);

CREATE INDEX idx_permissions_resource ON permissions (resource) WHERE deleted_at IS NULL;
CREATE INDEX idx_permissions_action   ON permissions (action)   WHERE deleted_at IS NULL;

CREATE TRIGGER trg_permissions_updated_at
    BEFORE UPDATE ON permissions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Join tables (many-to-many)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- user_roles  (a user can have many roles)
-- -----------------------------------------------------------------------------
CREATE TABLE user_roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role_id     UUID        NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    -- who granted this role; SET NULL so audit-friendly deletion is possible
    granted_by  UUID        REFERENCES users (id) ON DELETE SET NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,                    -- optional time-bounded grants
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ,
    CONSTRAINT user_roles_unique UNIQUE (user_id, role_id)
);

CREATE INDEX idx_user_roles_user_id    ON user_roles (user_id);
CREATE INDEX idx_user_roles_role_id    ON user_roles (role_id);
CREATE INDEX idx_user_roles_expires_at ON user_roles (expires_at)
    WHERE expires_at IS NOT NULL;

CREATE TRIGGER trg_user_roles_updated_at
    BEFORE UPDATE ON user_roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- role_permissions  (a role grants many permissions)
-- -----------------------------------------------------------------------------
CREATE TABLE role_permissions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id         UUID        NOT NULL REFERENCES roles (id)       ON DELETE CASCADE,
    permission_id   UUID        NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    granted_by      UUID        REFERENCES users (id) ON DELETE SET NULL,
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,
    CONSTRAINT role_permissions_unique UNIQUE (role_id, permission_id)
);

CREATE INDEX idx_role_permissions_role_id       ON role_permissions (role_id);
CREATE INDEX idx_role_permissions_permission_id ON role_permissions (permission_id);

CREATE TRIGGER trg_role_permissions_updated_at
    BEFORE UPDATE ON role_permissions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- Audit log
-- =============================================================================
-- The existing frontend already shows audit information; this table is the
-- backend store that feeds it. Every meaningful change to a row in any of the
-- above tables (or anywhere else) is appended here.
--
-- Design notes:
--   * actor_id is SET NULL on user delete so historical actions remain visible
--     even if the acting user is purged.
--   * before_data / after_data captured as JSONB so any entity can be logged
--     without schema changes.
--   * Indexed by (entity, entity_id) for "history of this record" queries and
--     by actor_id for "what did this user do" queries.
-- -----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id     UUID        REFERENCES users (id) ON DELETE SET NULL,
    action       VARCHAR(64) NOT NULL,           -- e.g. 'create', 'update', 'delete', 'login'
    entity       VARCHAR(64) NOT NULL,           -- e.g. 'user', 'role', 'permission'
    entity_id    UUID,                           -- target record (nullable for global events)
    before_data  JSONB,
    after_data   JSONB,
    ip_address   INET,
    user_agent   TEXT,
    metadata     JSONB,                          -- free-form extra context
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_actor_id          ON audit_logs (actor_id);
CREATE INDEX idx_audit_logs_entity_entity_id  ON audit_logs (entity, entity_id);
CREATE INDEX idx_audit_logs_action            ON audit_logs (action);
CREATE INDEX idx_audit_logs_created_at        ON audit_logs (created_at DESC);
CREATE INDEX idx_audit_logs_metadata          ON audit_logs USING GIN (metadata);

-- =============================================================================
-- Views
-- =============================================================================

-- All non-deleted user/role assignments (handy for joins in app code)
CREATE OR REPLACE VIEW active_user_roles_view AS
SELECT
    u.id            AS user_id,
    u.email,
    u.username,
    r.id            AS role_id,
    r.name          AS role_name,
    r.label         AS role_label,
    ur.granted_at,
    ur.expires_at
FROM users u
JOIN user_roles ur ON ur.user_id = u.id AND ur.deleted_at IS NULL
JOIN roles r       ON r.id       = ur.role_id AND r.deleted_at IS NULL
WHERE u.deleted_at IS NULL
  AND u.is_active = TRUE
  AND (ur.expires_at IS NULL OR ur.expires_at > NOW());

-- Effective permissions per user (flattened across all their roles)
CREATE OR REPLACE VIEW user_permissions_view AS
SELECT DISTINCT
    u.id            AS user_id,
    u.email,
    u.username,
    p.id            AS permission_id,
    p.name          AS permission_name,
    p.resource,
    p.action
FROM users u
JOIN user_roles ur       ON ur.user_id       = u.id  AND ur.deleted_at IS NULL
JOIN role_permissions rp ON rp.role_id       = ur.role_id AND rp.deleted_at IS NULL
JOIN permissions p       ON p.id             = rp.permission_id AND p.deleted_at IS NULL
WHERE u.deleted_at IS NULL
  AND u.is_active = TRUE
  AND (ur.expires_at IS NULL OR ur.expires_at > NOW());

-- Admin-facing user view: includes sensitive operational fields and a
-- comma-separated role list for table rendering.
CREATE OR REPLACE VIEW admin_users_view AS
SELECT
    u.id,
    u.email,
    u.username,
    u.first_name,
    u.last_name,
    u.is_active,
    u.last_login_at,
    u.created_at,
    u.updated_at,
    u.deleted_at,
    COALESCE(
        (SELECT string_agg(r.name, ',' ORDER BY r.name)
           FROM user_roles ur
           JOIN roles r ON r.id = ur.role_id
          WHERE ur.user_id = u.id
            AND ur.deleted_at IS NULL
            AND r.deleted_at IS NULL),
        ''
    ) AS roles
FROM users u;

-- Standard (non-admin) user view: hides operational columns. Suitable for
-- exposure to regular signed-in users via a directory-style screen.
CREATE OR REPLACE VIEW standard_users_view AS
SELECT
    u.id,
    u.username,
    u.first_name,
    u.last_name,
    u.created_at
FROM users u
WHERE u.deleted_at IS NULL
  AND u.is_active = TRUE;

-- =============================================================================
-- Helper functions for application code (replace hardcoded role checks)
-- =============================================================================
-- The legacy app has lines like `if (user.role == 'admin') ...`. Going forward
-- it should call user_has_role() / user_has_permission() instead. These can be
-- invoked from SQL or via the ORM.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION user_has_role(p_user_id UUID, p_role_name TEXT)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
          FROM user_roles ur
          JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id    = p_user_id
           AND r.name        = p_role_name
           AND ur.deleted_at IS NULL
           AND r.deleted_at  IS NULL
           AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
    );
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION user_has_permission(p_user_id UUID, p_permission_name TEXT)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
          FROM user_roles ur
          JOIN role_permissions rp ON rp.role_id = ur.role_id
          JOIN permissions p       ON p.id       = rp.permission_id
         WHERE ur.user_id    = p_user_id
           AND p.name        = p_permission_name
           AND ur.deleted_at IS NULL
           AND rp.deleted_at IS NULL
           AND p.deleted_at  IS NULL
           AND (ur.expires_at IS NULL OR ur.expires_at > NOW())
    );
$$ LANGUAGE sql STABLE;

-- =============================================================================
-- Seed data
-- =============================================================================
-- NOTE on passwords: the values below are bcrypt-style placeholder hashes.
-- They are NOT real, working credentials and exist only so the column is
-- never empty. Replace via the application's password-reset flow.
-- -----------------------------------------------------------------------------

-- Roles ----------------------------------------------------------------------
INSERT INTO roles (name, label, description, is_system) VALUES
    ('admin',   'Administrator',  'Full access to every resource and action.', TRUE),
    ('manager', 'Manager',        'Manages users and views all reports.',      TRUE),
    ('user',    'Standard User',  'Default authenticated user.',               TRUE),
    ('auditor', 'Auditor',        'Read-only access including audit logs.',    TRUE),
    ('guest',   'Guest',          'Minimal read-only access.',                 TRUE);

-- Permissions ----------------------------------------------------------------
INSERT INTO permissions (name, resource, action, description) VALUES
    ('user.create',        'user',        'create', 'Create a new user account.'),
    ('user.view',          'user',        'view',   'View user records.'),
    ('user.update',        'user',        'update', 'Modify user records.'),
    ('user.delete',        'user',        'delete', 'Delete user records.'),
    ('role.create',        'role',        'create', 'Create a new role.'),
    ('role.view',          'role',        'view',   'View roles.'),
    ('role.update',        'role',        'update', 'Modify roles.'),
    ('role.delete',        'role',        'delete', 'Delete roles.'),
    ('role.assign',        'role',        'assign', 'Assign a role to a user.'),
    ('permission.manage',  'permission',  'manage', 'Manage permissions and role grants.'),
    ('report.view',        'report',      'view',   'View reports.'),
    ('report.export',      'report',      'export', 'Export reports.'),
    ('audit.view',         'audit',       'view',   'View audit logs.'),
    ('settings.manage',    'settings',    'manage', 'Modify system settings.');

-- Role -> permission mapping --------------------------------------------------
-- admin: everything
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r CROSS JOIN permissions p
 WHERE r.name = 'admin';

-- manager: user CRUD (no delete), role view/assign, all reports, audit view
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r, permissions p
 WHERE r.name = 'manager'
   AND p.name IN (
       'user.create', 'user.view', 'user.update',
       'role.view',   'role.assign',
       'report.view', 'report.export',
       'audit.view'
   );

-- user: view self-scope user info, view reports
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r, permissions p
 WHERE r.name = 'user'
   AND p.name IN ('user.view', 'report.view');

-- auditor: read-only including audit logs
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r, permissions p
 WHERE r.name = 'auditor'
   AND p.name IN ('user.view', 'role.view', 'report.view', 'audit.view');

-- guest: bare minimum
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
  FROM roles r, permissions p
 WHERE r.name = 'guest'
   AND p.name IN ('report.view');

-- Users ----------------------------------------------------------------------
-- Placeholder bcrypt hash (not a real password): "$2b$12$PLACEHOLDERPLACEHOLDERPLACEHOLDERPLACEHOLDERPLACEHOLDERPL"
INSERT INTO users (email, username, password_hash, first_name, last_name, is_active) VALUES
    ('alice.admin@example.com',     'alice',    '$2b$12$PLACEHOLDERHASHalice00000000000000000000000000000000ax', 'Alice',   'Anderson', TRUE),
    ('bob.manager@example.com',     'bob',      '$2b$12$PLACEHOLDERHASHbob000000000000000000000000000000000000bx', 'Bob',     'Brown',    TRUE),
    ('carol.manager@example.com',   'carol',    '$2b$12$PLACEHOLDERHASHcarol00000000000000000000000000000000cx', 'Carol',   'Carter',   TRUE),
    ('dave.user@example.com',       'dave',     '$2b$12$PLACEHOLDERHASHdave00000000000000000000000000000000000dx', 'Dave',    'Davis',    TRUE),
    ('erin.user@example.com',       'erin',     '$2b$12$PLACEHOLDERHASHerin00000000000000000000000000000000000ex', 'Erin',    'Edwards',  TRUE),
    ('frank.user@example.com',      'frank',    '$2b$12$PLACEHOLDERHASHfrank0000000000000000000000000000000000fx', 'Frank',   'Foster',   TRUE),
    ('grace.user@example.com',      'grace',    '$2b$12$PLACEHOLDERHASHgrace0000000000000000000000000000000000gx', 'Grace',   'Garcia',   TRUE),
    ('henry.user@example.com',      'henry',    '$2b$12$PLACEHOLDERHASHhenry0000000000000000000000000000000000hx', 'Henry',   'Hughes',   TRUE),
    ('ivy.auditor@example.com',     'ivy',      '$2b$12$PLACEHOLDERHASHivy0000000000000000000000000000000000000ix', 'Ivy',     'Ingram',   TRUE),
    ('jack.guest@example.com',      'jack',     '$2b$12$PLACEHOLDERHASHjack00000000000000000000000000000000000jx', 'Jack',    'Jones',    TRUE),
    ('kate.guest@example.com',      'kate',     '$2b$12$PLACEHOLDERHASHkate00000000000000000000000000000000000kx', 'Kate',    'Kim',      TRUE),
    ('leo.disabled@example.com',    'leo',      '$2b$12$PLACEHOLDERHASHleo000000000000000000000000000000000000lx', 'Leo',     'Lewis',    FALSE);

-- User -> role mapping --------------------------------------------------------
-- alice: admin
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
 WHERE u.username = 'alice' AND r.name = 'admin';

-- bob, carol: manager (bob also has 'user' to demonstrate multi-role)
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
 WHERE (u.username, r.name) IN (
     ('bob',   'manager'),
     ('bob',   'user'),
     ('carol', 'manager')
 );

-- dave..henry: standard user
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
 WHERE r.name = 'user'
   AND u.username IN ('dave', 'erin', 'frank', 'grace', 'henry');

-- ivy: auditor
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
 WHERE u.username = 'ivy' AND r.name = 'auditor';

-- jack, kate: guest
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
 WHERE r.name = 'guest'
   AND u.username IN ('jack', 'kate');

-- leo: deactivated, no role assignment

-- Seed audit trail entry so the frontend has data to render on first run
INSERT INTO audit_logs (actor_id, action, entity, entity_id, after_data, metadata)
SELECT
    u.id,
    'seed',
    'system',
    NULL,
    jsonb_build_object('message', 'Initial RBAC seed completed.'),
    jsonb_build_object('source', 'rbac_schema.sql')
  FROM users u
 WHERE u.username = 'alice';

COMMIT;

-- =============================================================================
-- End of script
-- =============================================================================
