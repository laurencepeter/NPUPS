-- =============================================================================
-- NPUPS / WorkForce — Domain Schema + Seed Data
-- =============================================================================
-- This script is the single source of truth for all application data that
-- previously lived as hardcoded demo data inside the Flutter frontend
-- (lib/services/worker_data_store.dart, timesheet_data_store.dart,
-- audit_service.dart, roster_service.dart, backpay_service.dart and the
-- 8 demo accounts in auth_service.dart).
--
-- It is intentionally independent of db/rbac_schema.sql — that file covers
-- RBAC tables (users / roles / permissions). Domain data is stored separately
-- so the two schemas can evolve at different rates and so the existing RBAC
-- seed is left untouched.
--
-- Run order:   psql -f db/rbac_schema.sql -f db/domain_schema.sql
--
-- Target:      PostgreSQL 14+
-- Deterministic: yes — every timestamp/date is derived from seed_anchor_date.
-- Idempotent:    yes within a fresh DB (uses DROP ... CASCADE at top).
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------------------------------------------------------------------
-- Drop existing objects so the script can be re-run during development.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS backpay_line_items        CASCADE;
DROP TABLE IF EXISTS backpay_records           CASCADE;
DROP TABLE IF EXISTS roster_day_entries        CASCADE;
DROP TABLE IF EXISTS roster_worker_records     CASCADE;
DROP TABLE IF EXISTS rosters                   CASCADE;
DROP TABLE IF EXISTS roster_settings           CASCADE;
DROP TABLE IF EXISTS app_audit_attachments     CASCADE;
DROP TABLE IF EXISTS app_audit_field_changes   CASCADE;
DROP TABLE IF EXISTS app_audit_logs            CASCADE;
DROP TABLE IF EXISTS timesheet_approvals       CASCADE;
DROP TABLE IF EXISTS timesheet_daily_entries   CASCADE;
DROP TABLE IF EXISTS timesheets                CASCADE;
DROP TABLE IF EXISTS worker_replacements       CASCADE;
DROP TABLE IF EXISTS worker_allowances         CASCADE;
DROP TABLE IF EXISTS worker_documents          CASCADE;
DROP TABLE IF EXISTS workers                   CASCADE;
DROP TABLE IF EXISTS app_users                 CASCADE;
DROP TABLE IF EXISTS corporations              CASCADE;

DROP TYPE  IF EXISTS document_status_enum      CASCADE;
DROP TYPE  IF EXISTS timesheet_stage_enum      CASCADE;
DROP TYPE  IF EXISTS approval_state_enum       CASCADE;
DROP TYPE  IF EXISTS audit_action_enum         CASCADE;
DROP TYPE  IF EXISTS audit_entity_type_enum    CASCADE;
DROP TYPE  IF EXISTS backpay_status_enum       CASCADE;
DROP TYPE  IF EXISTS app_user_role_enum        CASCADE;

-- =============================================================================
-- Enum types — names match Dart enum `.name` values exactly so the API can
-- pass them through without translation.
-- =============================================================================

CREATE TYPE document_status_enum AS ENUM ('uploaded', 'missing', 'pending');

CREATE TYPE timesheet_stage_enum AS ENUM (
    'notStarted', 'draft', 'submitted',
    'coordinatorReview', 'hrProcessing', 'accountsProcessing',
    'approvedForPayment', 'exported', 'chequePrinting'
);

CREATE TYPE approval_state_enum AS ENUM ('pending', 'approved', 'rejected');

CREATE TYPE audit_action_enum AS ENUM (
    'create', 'update', 'delete', 'activate', 'deactivate',
    'documentUpload', 'documentReject', 'documentApprove',
    'approve', 'reject', 'login', 'logout', 'export', 'import',
    'rosterUpdate', 'settingsChange', 'replacementAdded',
    'stageAdvanced', 'stageRejected', 'attachmentAdded', 'attachmentRemoved',
    'wageRateChanged', 'backpayCalculated', 'backpayApproved', 'backpayDisbursed',
    'paymentRecorded', 'paymentReversed',
    'allowanceAdded', 'allowanceUpdated', 'allowanceRemoved',
    -- Recorded when a worker registration is blocked because one of the
    -- regulated unique credentials (NIS / National ID / BIR / Driver Permit /
    -- Passport) is already in use. Mirrors AuditAction.duplicateIdAttempt.
    'duplicateIdAttempt'
);

CREATE TYPE audit_entity_type_enum AS ENUM (
    'worker', 'timesheet', 'document', 'userAccount',
    'rosterEntry', 'rosterSettings', 'payroll', 'payment',
    'backpay', 'attachment', 'system'
);

CREATE TYPE backpay_status_enum AS ENUM ('calculated', 'approved', 'disbursed', 'cancelled');

CREATE TYPE app_user_role_enum AS ENUM (
    'systemAdmin', 'ps', 'dmcr', 'regionalCoordinator', 'hr',
    'subAccounts', 'mainAccounts', 'ministersDepartment', 'worker'
);

-- =============================================================================
-- Reference tables
-- =============================================================================

-- Corporations: all 14 municipal corporations referenced throughout the app.
CREATE TABLE corporations (
    id          TEXT        PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- App-facing user accounts (8 demo logins from auth_service.dart). Kept
-- separate from RBAC `users` so the existing RBAC seed remains untouched.
-- IMPORTANT: password_hash is the proof-of-concept demo placeholder hash.
-- Real authentication should replace these via the API's password-reset flow.
CREATE TABLE app_users (
    id              TEXT        PRIMARY KEY,
    email           TEXT        NOT NULL UNIQUE,
    full_name       TEXT        NOT NULL,
    role            app_user_role_enum NOT NULL,
    corporation_id  TEXT        REFERENCES corporations (id) ON DELETE SET NULL,
    corporation_name TEXT,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    -- Demo-only password (kept as proof of concept per project instructions).
    password_demo   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_app_users_role ON app_users (role);
CREATE INDEX idx_app_users_corporation_id ON app_users (corporation_id);

-- =============================================================================
-- Workers (mirrors lib/models/worker_model.dart Worker)
-- =============================================================================

CREATE TABLE workers (
    id                  TEXT        PRIMARY KEY,
    full_name           TEXT        NOT NULL,
    nis_number          TEXT        NOT NULL UNIQUE,
    date_of_birth       DATE        NOT NULL,
    position            TEXT        NOT NULL,
    id_number           TEXT        NOT NULL,
    corporation_id      TEXT        NOT NULL REFERENCES corporations (id),
    corporation_name    TEXT        NOT NULL,
    electoral_district  TEXT        NOT NULL,
    wage_rate           NUMERIC(10,2) NOT NULL,
    cola_rate           NUMERIC(10,2) NOT NULL DEFAULT 0,
    allowance_rate      NUMERIC(10,2) NOT NULL,
    bank_name           TEXT        NOT NULL,
    account_number      TEXT        NOT NULL,
    branch_name         TEXT        NOT NULL,
    date_registered     DATE        NOT NULL,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    contact                 TEXT,
    address                 TEXT,
    bir_number              TEXT,
    -- Additional regulated identifiers used by the duplicate-ID guard
    -- (lib/services/worker_data_store.dart checkUniqueIds). Both are
    -- nullable — most workers won't have either.
    driver_permit_number    TEXT,
    passport_number         TEXT,
    start_date              DATE,
    end_date                DATE,
    reference_number        TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_workers_corporation_id ON workers (corporation_id);
CREATE INDEX idx_workers_is_active      ON workers (is_active);
CREATE INDEX idx_workers_full_name      ON workers (full_name);

CREATE TABLE worker_documents (
    worker_id   TEXT        NOT NULL REFERENCES workers (id) ON DELETE CASCADE,
    doc_name    TEXT        NOT NULL,
    status      document_status_enum NOT NULL DEFAULT 'missing',
    file_name   TEXT,
    uploaded_at TIMESTAMPTZ,
    PRIMARY KEY (worker_id, doc_name)
);

CREATE TABLE worker_allowances (
    id              TEXT        PRIMARY KEY,
    worker_id       TEXT        NOT NULL REFERENCES workers (id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    rate            NUMERIC(10,2) NOT NULL,
    per_day_worked  BOOLEAN     NOT NULL DEFAULT TRUE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    note            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_worker_allowances_worker_id ON worker_allowances (worker_id);

CREATE TABLE worker_replacements (
    id                      TEXT        PRIMARY KEY,
    original_worker_id      TEXT        NOT NULL REFERENCES workers (id),
    replacement_worker_id   TEXT        NOT NULL REFERENCES workers (id),
    days_missed             INT         NOT NULL,
    reason                  TEXT        NOT NULL,
    replaced_at             TIMESTAMPTZ NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT worker_replacements_unique_original UNIQUE (original_worker_id)
);

-- =============================================================================
-- Timesheets (mirrors lib/models/timesheet_model.dart Timesheet)
-- =============================================================================

CREATE TABLE timesheets (
    id                  TEXT        PRIMARY KEY,
    worker_id           TEXT        NOT NULL REFERENCES workers (id),
    worker_name         TEXT        NOT NULL,
    position            TEXT        NOT NULL,
    id_number           TEXT        NOT NULL,
    nis_number          TEXT        NOT NULL,
    wage_rate           NUMERIC(10,2) NOT NULL,
    cola_rate           NUMERIC(10,2) NOT NULL DEFAULT 0,
    allowance_rate      NUMERIC(10,2) NOT NULL,
    corporation_id      TEXT        NOT NULL REFERENCES corporations (id),
    corporation_name    TEXT        NOT NULL,
    electoral_district  TEXT        NOT NULL,
    group_number        TEXT        NOT NULL,
    fortnight_start     DATE        NOT NULL,
    fortnight_end       DATE        NOT NULL,
    bank_name           TEXT        NOT NULL,
    account_number      TEXT        NOT NULL,
    branch_name         TEXT        NOT NULL,
    allowance_days      INT         NOT NULL DEFAULT 0,
    remarks             TEXT        NOT NULL DEFAULT '',
    stage               timesheet_stage_enum NOT NULL DEFAULT 'notStarted',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_timesheets_worker_id          ON timesheets (worker_id);
CREATE INDEX idx_timesheets_corporation_id     ON timesheets (corporation_id);
CREATE INDEX idx_timesheets_stage              ON timesheets (stage);
CREATE INDEX idx_timesheets_fortnight_start    ON timesheets (fortnight_start);

-- 14 rows per timesheet (one per day in the fortnight).
CREATE TABLE timesheet_daily_entries (
    timesheet_id    TEXT        NOT NULL REFERENCES timesheets (id) ON DELETE CASCADE,
    day_index       INT         NOT NULL CHECK (day_index BETWEEN 0 AND 13),
    time_in         TIME,
    time_out        TIME,
    PRIMARY KEY (timesheet_id, day_index)
);

CREATE TABLE timesheet_approvals (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    timesheet_id    TEXT        NOT NULL REFERENCES timesheets (id) ON DELETE CASCADE,
    sequence_no     INT         NOT NULL,
    reviewer_name   TEXT        NOT NULL,
    reviewer_role   TEXT        NOT NULL,
    state           approval_state_enum NOT NULL,
    note            TEXT,
    ts              TIMESTAMPTZ NOT NULL,
    CONSTRAINT timesheet_approvals_unique UNIQUE (timesheet_id, sequence_no)
);
CREATE INDEX idx_timesheet_approvals_timesheet_id ON timesheet_approvals (timesheet_id);

-- =============================================================================
-- Rosters (mirrors lib/models/roster_model.dart)
-- =============================================================================

CREATE TABLE roster_settings (
    corporation_id            TEXT    PRIMARY KEY REFERENCES corporations (id) ON DELETE CASCADE,
    max_days_per_fortnight    INT     NOT NULL DEFAULT 10,
    allow_weekend_work        BOOLEAN NOT NULL DEFAULT FALSE,
    allow_max_days_override   BOOLEAN NOT NULL DEFAULT TRUE,
    data_entry_can_override   BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE rosters (
    id                  TEXT        PRIMARY KEY,
    corporation_id      TEXT        NOT NULL REFERENCES corporations (id),
    corporation_name    TEXT        NOT NULL,
    fortnight_start     DATE        NOT NULL,
    fortnight_end       DATE        NOT NULL,
    last_modified       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_modified_by    TEXT,
    CONSTRAINT rosters_unique_corp_start UNIQUE (corporation_id, fortnight_start)
);
CREATE INDEX idx_rosters_corporation_id ON rosters (corporation_id);

CREATE TABLE roster_worker_records (
    roster_id           TEXT        NOT NULL REFERENCES rosters (id) ON DELETE CASCADE,
    worker_id           TEXT        NOT NULL REFERENCES workers (id),
    max_days_override   INT,
    notes               TEXT,
    PRIMARY KEY (roster_id, worker_id)
);

CREATE TABLE roster_day_entries (
    roster_id       TEXT        NOT NULL,
    worker_id       TEXT        NOT NULL,
    day_index       INT         NOT NULL CHECK (day_index BETWEEN 0 AND 13),
    entry_date      DATE        NOT NULL,
    is_present      BOOLEAN     NOT NULL DEFAULT TRUE,
    absence_reason  TEXT,
    PRIMARY KEY (roster_id, worker_id, day_index),
    FOREIGN KEY (roster_id, worker_id) REFERENCES roster_worker_records (roster_id, worker_id) ON DELETE CASCADE
);

-- =============================================================================
-- Backpay (mirrors lib/models/backpay_model.dart)
-- =============================================================================

CREATE TABLE backpay_records (
    id                      TEXT        PRIMARY KEY,
    worker_id               TEXT        NOT NULL REFERENCES workers (id),
    worker_name             TEXT        NOT NULL,
    corporation_id          TEXT        NOT NULL REFERENCES corporations (id),
    corporation_name        TEXT        NOT NULL,
    effective_from          DATE        NOT NULL,
    old_wage_rate           NUMERIC(10,2) NOT NULL,
    new_wage_rate           NUMERIC(10,2) NOT NULL,
    old_cola_rate           NUMERIC(10,2) NOT NULL,
    new_cola_rate           NUMERIC(10,2) NOT NULL,
    status                  backpay_status_enum NOT NULL DEFAULT 'calculated',
    note                    TEXT,
    calculated_at           TIMESTAMPTZ NOT NULL,
    calculated_by_user_id   TEXT        NOT NULL
);
CREATE INDEX idx_backpay_records_worker_id ON backpay_records (worker_id);
CREATE INDEX idx_backpay_records_status    ON backpay_records (status);

CREATE TABLE backpay_line_items (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    backpay_record_id   TEXT        NOT NULL REFERENCES backpay_records (id) ON DELETE CASCADE,
    timesheet_id        TEXT        NOT NULL,
    fortnight_start     DATE        NOT NULL,
    days_worked         INT         NOT NULL,
    old_daily_rate      NUMERIC(10,2) NOT NULL,
    new_daily_rate      NUMERIC(10,2) NOT NULL,
    old_cola_rate       NUMERIC(10,2) NOT NULL,
    new_cola_rate       NUMERIC(10,2) NOT NULL
);
CREATE INDEX idx_backpay_line_items_record_id ON backpay_line_items (backpay_record_id);

-- =============================================================================
-- Application Audit Log (mirrors lib/models/audit_model.dart AuditLogEntry)
-- =============================================================================
-- Kept separate from `audit_logs` in rbac_schema.sql so the RBAC schema is
-- untouched. Tamper-evident hash chain matches the Dart implementation:
--   sha256( previousHash || id || microsSinceEpoch || userId
--         || action.name || entityType.name || entityId
--         || changesStr  || attachStr )
-- changesStr = "<field>|<old>|<new>" joined by ';'
-- attachStr  = "<id>|<contentHash>|<sizeBytes>" joined by ';'

CREATE TABLE app_audit_logs (
    id                  TEXT        PRIMARY KEY,
    timestamp           TIMESTAMPTZ NOT NULL,
    user_id             TEXT        NOT NULL,
    user_name           TEXT        NOT NULL,
    user_role           TEXT        NOT NULL,
    session_id          TEXT        NOT NULL,
    action              audit_action_enum NOT NULL,
    entity_type         audit_entity_type_enum NOT NULL,
    entity_id           TEXT        NOT NULL,
    entity_display_name TEXT        NOT NULL,
    note                TEXT,
    actor_context       TEXT,
    hash                TEXT        NOT NULL,
    previous_hash       TEXT        NOT NULL DEFAULT '',
    sequence_no         BIGSERIAL   UNIQUE
);
CREATE INDEX idx_app_audit_logs_user_id     ON app_audit_logs (user_id);
CREATE INDEX idx_app_audit_logs_entity      ON app_audit_logs (entity_type, entity_id);
CREATE INDEX idx_app_audit_logs_action      ON app_audit_logs (action);
CREATE INDEX idx_app_audit_logs_timestamp   ON app_audit_logs (timestamp DESC);

CREATE TABLE app_audit_field_changes (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    audit_log_id    TEXT        NOT NULL REFERENCES app_audit_logs (id) ON DELETE CASCADE,
    sequence_no     INT         NOT NULL,
    field_name      TEXT        NOT NULL,
    old_value       TEXT,
    new_value       TEXT,
    CONSTRAINT app_audit_field_changes_unique UNIQUE (audit_log_id, sequence_no)
);

CREATE TABLE app_audit_attachments (
    id              TEXT        PRIMARY KEY,
    audit_log_id    TEXT        NOT NULL REFERENCES app_audit_logs (id) ON DELETE CASCADE,
    file_name       TEXT        NOT NULL,
    mime_type       TEXT        NOT NULL,
    size_bytes      BIGINT      NOT NULL,
    content_hash    TEXT        NOT NULL,
    uploaded_at     TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_app_audit_attachments_log_id ON app_audit_attachments (audit_log_id);

-- =============================================================================
-- Seed data
-- =============================================================================
-- All timestamps below are derived from a fixed anchor date so re-runs of
-- this seed produce identical rows. Replace the anchor when refreshing demo
-- data for a new release.
-- -----------------------------------------------------------------------------

-- Anchor date used as "now" for seed timestamps (matches the natural
-- fortnight starting Monday 20 April 2026).
DO $$
DECLARE
    seed_now           CONSTANT TIMESTAMPTZ := '2026-04-27 12:00:00+00';
    seed_fortnight_s   CONSTANT DATE        := '2026-04-20';
    seed_fortnight_e   CONSTANT DATE        := '2026-05-03';
BEGIN
    -- The anchor is informational; concrete values are inlined below for
    -- readability and to avoid PL/pgSQL EXECUTE complexity.
    RAISE NOTICE 'Seeding domain data with anchor %', seed_now;
END $$;

-- ── Corporations ─────────────────────────────────────────────────────────────
-- All 14 municipal corporations from worker_registration_form.dart
INSERT INTO corporations (id, name) VALUES
    ('1',  'Arima Borough Corporation'),
    ('2',  'Chaguanas Borough Corporation'),
    ('3',  'San Fernando City Corporation'),
    ('4',  'Diego Martin Regional Corporation'),
    ('5',  'Mayaro-Rio Claro Regional Corporation'),
    ('6',  'Penal-Debe Regional Corporation'),
    ('7',  'Point Fortin Borough Corporation'),
    ('8',  'Port of Spain City Corporation'),
    ('9',  'Princes Town Regional Corporation'),
    ('10', 'Couva-Tabaquite-Talparo Regional Corporation'),
    ('11', 'San Juan-Laventille Regional Corporation'),
    ('12', 'Sangre Grande Regional Corporation'),
    ('13', 'Siparia Regional Corporation'),
    ('14', 'Tunapuna-Piarco Regional Corporation');

-- ── App users (9 demo logins from auth_service.dart) ────────────────────────
INSERT INTO app_users (id, email, full_name, role, corporation_id, corporation_name, password_demo) VALUES
    ('USR-001', 'admin@workforce.app',        'System Administrator', 'systemAdmin',         NULL, 'All Corporations',                'admin123'),
    ('USR-002', 'coordinator@workforce.app',  'Marcus Thompson',      'regionalCoordinator', '8',  'Port of Spain City Corporation',  'test123'),
    ('USR-003', 'hr@workforce.app',           'Priya Maharaj',        'hr',                  '2',  'Chaguanas Borough Corporation',   'test123'),
    ('USR-004', 'worker@workforce.app',       'Kevin Rampersad',      'worker',              '8',  'Port of Spain City Corporation',  'test123'),
    ('USR-005', 'accounts@workforce.app',     'James Roberts',        'subAccounts',         NULL, 'All Corporations',                'test123'),
    ('USR-006', 'ps@workforce.app',           'Dr. Sharon Rowley',    'ps',                  NULL, 'All Corporations',                'test123'),
    ('USR-007', 'mainaccounts@workforce.app', 'Catherine Williams',   'mainAccounts',        NULL, 'All Corporations',                'test123'),
    ('USR-008', 'executive@workforce.app',    'Raymond Ali',          'ministersDepartment', NULL, 'All Corporations',                'test123'),
    ('USR-009', 'dmcr@workforce.app',         'Anika Ramlogan',       'dmcr',                NULL, 'All Corporations',                'test123');

-- ── Workers ──────────────────────────────────────────────────────────────────
-- 12 primary workers (WRK-001..WRK-012) from worker_data_store.dart plus
-- 7 "extras" (WRK-101..WRK-107) referenced by accounts/exported/cheque
-- timesheets in timesheet_data_store.dart but not previously in the worker
-- registry. Seeding them here so timesheet FKs resolve.
INSERT INTO workers (
    id, full_name, nis_number, date_of_birth, position, id_number,
    corporation_id, corporation_name, electoral_district,
    wage_rate, cola_rate, allowance_rate,
    bank_name, account_number, branch_name,
    date_registered, is_active,
    contact, address, bir_number, start_date, end_date, reference_number
) VALUES
    ('WRK-001', 'Kevin Rampersad',    'NIS-2024-00147', '1988-03-15', 'General Worker',    'ID-TT-198803150', '8', 'Port of Spain City Corporation', 'Port of Spain South', 150, 25, 40, 'Republic Bank',       '1102-4587-6321', 'Independence Square', '2024-01-10', TRUE,  '868-555-0101', '14 Cipero Street, Port of Spain',     'BIR-2024-00147', '2024-01-15', NULL,         'ETT-2024-00147'),
    ('WRK-002', 'Sasha Mohammed',     'NIS-2024-00203', '1992-07-22', 'Drain Cleaner',     'ID-TT-199207221', '8', 'Port of Spain City Corporation', 'Port of Spain East',  150, 25, 40, 'First Citizens Bank', '2203-8765-1234', 'Park Street',         '2024-02-05', TRUE,  '868-555-0202', '7 Belmont Circular Road, Belmont',    'BIR-2024-00203', '2024-02-10', NULL,         'ETT-2024-00203'),
    ('WRK-003', 'Andre Williams',     'NIS-2023-01982', '1985-11-03', 'Road Maintenance',  'ID-TT-198511030', '2', 'Chaguanas Borough Corporation',  'Chaguanas North',     150, 25, 40, 'Scotiabank',          '3301-2244-5566', 'Chaguanas Main',      '2023-11-20', TRUE,  '868-555-0303', '22 Montrose Road, Chaguanas',         'BIR-2023-01982', '2023-12-01', NULL,         'ETT-2023-01982'),
    ('WRK-004', 'Lisa Doodnath',      'NIS-2024-00489', '1990-05-18', 'General Worker',    'ID-TT-199005181', '2', 'Chaguanas Borough Corporation',  'Chaguanas South',     150, 25, 40, 'Republic Bank',       '1104-9876-5432', 'Chaguanas',           '2024-03-01', TRUE,  '868-555-0404', '5 Endeavour Road, Chaguanas',         'BIR-2024-00489', '2024-03-10', NULL,         'ETT-2024-00489'),
    ('WRK-005', 'Ravi Doobay',        'NIS-2024-00621', '1995-09-07', 'Landscaper',        'ID-TT-199509071', '8', 'Port of Spain City Corporation', 'Port of Spain West',  150, 25, 40, 'JMMB Bank',           '5501-3322-1144', 'Ariapita Avenue',     '2024-04-12', TRUE,  '868-555-0505', '31 Ariapita Avenue, Woodbrook',       'BIR-2024-00621', '2024-04-20', NULL,         'ETT-2024-00621'),
    ('WRK-006', 'Marcia Boodoo',      'NIS-2024-00788', '1987-01-25', 'Street Cleaner',    'ID-TT-198701251', '3', 'San Fernando City Corporation',  'San Fernando East',   150, 25, 40, 'First Citizens Bank', '2205-6677-8899', 'High Street',         '2024-05-08', FALSE, '868-555-0606', '9 Coffee Street, San Fernando',       'BIR-2024-00788', '2024-05-15', '2025-01-15', 'ETT-2024-00788'),
    ('WRK-007', 'Jason Baptiste',     'NIS-2024-00912', '1993-04-14', 'General Worker',    'ID-TT-199304141', '3', 'San Fernando City Corporation',  'San Fernando West',   150, 25, 40, 'Republic Bank',       '1106-1122-3344', 'San Fernando',        '2024-06-01', TRUE,  '868-555-0707', '17 Pointe-a-Pierre Road, San Fernando','BIR-2024-00912', '2024-06-10', NULL,         'ETT-2024-00912'),
    ('WRK-008', 'Terrence Charles',   'NIS-2024-01055', '1998-12-30', 'Drain Cleaner',     'ID-TT-199812301', '8', 'Port of Spain City Corporation', 'Port of Spain North', 150, 25, 40, 'Scotiabank',          '3303-5544-6677', 'Frederick Street',    '2024-07-15', FALSE, '868-555-0808', '3 Observatory Street, Port of Spain', NULL,             '2024-07-22', '2025-02-01', 'ETT-2024-01055'),
    ('WRK-009', 'Camille Hospedales', 'NIS-2024-01198', '1991-08-19', 'Road Maintenance',  'ID-TT-199108191', '2', 'Chaguanas Borough Corporation',  'Chaguanas East',      150, 25, 40, 'JMMB Bank',           '5502-7788-9900', 'Endeavour Road',      '2024-08-03', TRUE,  '868-555-0909', '42 Caroni Arena Road, Chaguanas',     NULL,             '2024-08-12', NULL,         'ETT-2024-01198'),
    ('WRK-010', 'Denise La Fortune',  'NIS-2024-01342', '1989-06-11', 'Landscaper',        'ID-TT-198906111', '3', 'San Fernando City Corporation',  'San Fernando East',   150, 25, 40, 'Republic Bank',       '1108-2233-4455', 'Coffee Street',       '2024-09-10', TRUE,  '868-555-1010', '88 Navet Road, San Fernando',         NULL,             '2024-09-20', NULL,         'ETT-2024-01342'),
    ('WRK-011', 'Patricia Hernandez', 'NIS-2025-00105', '1994-03-08', 'Street Cleaner',    'ID-TT-199403081', '3', 'San Fernando City Corporation',  'San Fernando East',   150, 25, 40, 'Republic Bank',       '1109-3344-5566', 'Coffee Street',       '2025-01-20', TRUE,  '868-555-1101', '12 Harris Promenade, San Fernando',   'BIR-2025-00105', '2025-01-20', NULL,         'ETT-2025-00105'),
    ('WRK-012', 'Marcus Phillip',     'NIS-2025-00218', '1997-07-14', 'Drain Cleaner',     'ID-TT-199707141', '8', 'Port of Spain City Corporation', 'Port of Spain North', 150, 25, 40, 'Scotiabank',          '3306-7788-9900', 'Frederick Street',    '2025-02-05', TRUE,  '868-555-1202', '56 Laventille Road, Laventille',      'BIR-2025-00218', '2025-02-05', NULL,         'ETT-2025-00218'),
    -- Extras referenced only by demo timesheets:
    ('WRK-101', 'Ronald Persad',      'NIS-2024-01501', '1990-01-01', 'General Worker',    'ID-TT-199001011', '8', 'Port of Spain City Corporation', 'Port of Spain South', 150, 25, 40, 'Republic Bank',       '1109-1234-5678', 'Independence Square', '2024-01-10', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-102', 'Sandra Ramsaran',    'NIS-2024-01502', '1988-02-02', 'Landscaper',        'ID-TT-198802022', '2', 'Chaguanas Borough Corporation',  'Chaguanas North',     150, 25, 40, 'First Citizens Bank', '2206-8765-4321', 'Chaguanas',           '2024-02-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-103', 'Derek Singh',        'NIS-2024-01503', '1992-03-03', 'Road Maintenance',  'ID-TT-199203033', '8', 'Port of Spain City Corporation', 'Laventille',          150, 25, 40, 'Scotiabank',          '3304-5566-7788', 'Frederick Street',    '2024-03-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-104', 'Angela Pierre',      'NIS-2024-01504', '1985-04-04', 'Street Cleaner',    'ID-TT-198504044', '3', 'San Fernando City Corporation',  'San Fernando East',   150, 25, 40, 'Republic Bank',       '1110-4455-6677', 'Coffee Street',       '2024-04-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-105', 'Michael James',      'NIS-2024-01505', '1991-06-05', 'General Worker',    'ID-TT-199106055', '8', 'Port of Spain City Corporation', 'Morvant',             150, 25, 40, 'JMMB Bank',           '5503-2233-4455', 'Ariapita Avenue',     '2024-05-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-106', 'Patricia Garcia',    'NIS-2024-01506', '1987-07-06', 'General Worker',    'ID-TT-198707066', '2', 'Chaguanas Borough Corporation',  'Chaguanas South',     150, 25, 40, 'Republic Bank',       '1111-6677-8899', 'Chaguanas',           '2024-06-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL),
    ('WRK-107', 'Vernon Alexander',   'NIS-2024-01507', '1993-08-07', 'Drain Cleaner',     'ID-TT-199308077', '3', 'San Fernando City Corporation',  'San Fernando West',   150, 25, 40, 'First Citizens Bank', '2207-9988-7766', 'High Street',         '2024-07-15', TRUE,  NULL,           NULL,                                  NULL,             NULL,         NULL,         NULL);

-- ── Worker documents ─────────────────────────────────────────────────────────
-- Required document set per worker: NIS Registration, Birth Certificate,
-- Bank Verification Letter, National ID Card, Police Certificate of Good
-- Character. We seed all 5 per worker; status reflects the original
-- _allUploaded / _partialDocs / _noDocs categories from worker_data_store.dart.

-- All 5 uploaded
WITH all_uploaded(worker_id) AS (
    VALUES ('WRK-001'),('WRK-002'),('WRK-003'),('WRK-004'),('WRK-011'),
           ('WRK-101'),('WRK-102'),('WRK-103'),('WRK-104'),('WRK-105'),('WRK-106'),('WRK-107')
), doc_names(name) AS (
    VALUES ('NIS Registration'),('Birth Certificate'),('Bank Verification Letter'),
           ('National ID Card'),('Police Certificate of Good Character')
)
INSERT INTO worker_documents (worker_id, doc_name, status, file_name, uploaded_at)
SELECT u.worker_id,
       d.name,
       'uploaded'::document_status_enum,
       lower(replace(d.name,' ','_')) || '.pdf',
       '2024-02-01 09:00:00+00'::timestamptz
  FROM all_uploaded u CROSS JOIN doc_names d;

-- Partial docs
INSERT INTO worker_documents (worker_id, doc_name, status, file_name, uploaded_at) VALUES
    ('WRK-005', 'NIS Registration',                       'uploaded', 'nis_registration.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-005', 'Birth Certificate',                      'missing',  NULL,                                          NULL),
    ('WRK-005', 'Bank Verification Letter',               'missing',  NULL,                                          NULL),
    ('WRK-005', 'National ID Card',                       'uploaded', 'national_id_card.pdf',                        '2024-03-15 09:00:00+00'),
    ('WRK-005', 'Police Certificate of Good Character',   'missing',  NULL,                                          NULL),

    ('WRK-006', 'NIS Registration',                       'uploaded', 'nis_registration.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-006', 'Birth Certificate',                      'uploaded', 'birth_certificate.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-006', 'Bank Verification Letter',               'missing',  NULL,                                          NULL),
    ('WRK-006', 'National ID Card',                       'uploaded', 'national_id_card.pdf',                        '2024-03-15 09:00:00+00'),
    ('WRK-006', 'Police Certificate of Good Character',   'missing',  NULL,                                          NULL),

    ('WRK-007', 'NIS Registration',                       'missing',  NULL,                                          NULL),
    ('WRK-007', 'Birth Certificate',                      'uploaded', 'birth_certificate.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-007', 'Bank Verification Letter',               'missing',  NULL,                                          NULL),
    ('WRK-007', 'National ID Card',                       'missing',  NULL,                                          NULL),
    ('WRK-007', 'Police Certificate of Good Character',   'missing',  NULL,                                          NULL),

    ('WRK-012', 'NIS Registration',                       'uploaded', 'nis_registration.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-012', 'Birth Certificate',                      'uploaded', 'birth_certificate.pdf',                       '2024-03-15 09:00:00+00'),
    ('WRK-012', 'Bank Verification Letter',               'missing',  NULL,                                          NULL),
    ('WRK-012', 'National ID Card',                       'uploaded', 'national_id_card.pdf',                        '2024-03-15 09:00:00+00'),
    ('WRK-012', 'Police Certificate of Good Character',   'missing',  NULL,                                          NULL);

-- No docs uploaded
WITH no_docs(worker_id) AS (
    VALUES ('WRK-008'),('WRK-009'),('WRK-010')
), doc_names(name) AS (
    VALUES ('NIS Registration'),('Birth Certificate'),('Bank Verification Letter'),
           ('National ID Card'),('Police Certificate of Good Character')
)
INSERT INTO worker_documents (worker_id, doc_name, status)
SELECT n.worker_id, d.name, 'missing'::document_status_enum
  FROM no_docs n CROSS JOIN doc_names d;

-- ── Worker replacements ──────────────────────────────────────────────────────
INSERT INTO worker_replacements (id, original_worker_id, replacement_worker_id, days_missed, reason, replaced_at) VALUES
    ('REP-001', 'WRK-006', 'WRK-011', 18, 'Repeated absenteeism and conduct issues', '2025-01-20 09:00:00+00'),
    ('REP-002', 'WRK-008', 'WRK-012', 12, 'Unauthorised absence from duty post',     '2025-02-05 09:00:00+00');

-- ── Roster settings ──────────────────────────────────────────────────────────
INSERT INTO roster_settings (corporation_id) VALUES ('2'), ('3'), ('8');

-- ── Timesheets ───────────────────────────────────────────────────────────────
-- Anchor: seed_now = 2026-04-27 12:00:00, fortnight_start = 2026-04-20.
INSERT INTO timesheets (
    id, worker_id, worker_name, position, id_number, nis_number,
    wage_rate, cola_rate, allowance_rate, corporation_id, corporation_name,
    electoral_district, group_number, fortnight_start, fortnight_end,
    bank_name, account_number, branch_name, allowance_days, remarks,
    stage, created_at, updated_at
) VALUES
    ('TS-001', 'WRK-008', 'Terrence Charles',   'Drain Cleaner',    'ID-TT-199812301', 'NIS-2024-01055', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Port of Spain North', '1', '2026-04-20', '2026-05-03', 'Scotiabank',          '3303-5544-6677', 'Frederick Street',     0, '',                'notStarted',           '2026-04-22 12:00:00+00', '2026-04-22 12:00:00+00'),
    ('TS-002', 'WRK-009', 'Camille Hospedales', 'Road Maintenance', 'ID-TT-199108191', 'NIS-2024-01198', 150, 25, 40, '2', 'Chaguanas Borough Corporation',  'Chaguanas East',      '2', '2026-04-20', '2026-05-03', 'JMMB Bank',           '5502-7788-9900', 'Endeavour Road',       0, '',                'notStarted',           '2026-04-23 12:00:00+00', '2026-04-23 12:00:00+00'),
    ('TS-003', 'WRK-005', 'Ravi Doobay',        'Landscaper',       'ID-TT-199509071', 'NIS-2024-00621', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Port of Spain West',  '1', '2026-04-20', '2026-05-03', 'JMMB Bank',           '5501-3322-1144', 'Ariapita Avenue',      2, 'Partial entry',   'draft',                '2026-04-24 12:00:00+00', '2026-04-26 12:00:00+00'),
    ('TS-004', 'WRK-010', 'Denise La Fortune',  'Landscaper',       'ID-TT-198906111', 'NIS-2024-01342', 150, 25, 40, '3', 'San Fernando City Corporation',  'San Fernando East',   '3', '2026-04-20', '2026-05-03', 'Republic Bank',       '1108-2233-4455', 'Coffee Street',        0, 'Saving for later','draft',                '2026-04-24 12:00:00+00', '2026-04-25 12:00:00+00'),
    ('TS-005', 'WRK-001', 'Kevin Rampersad',    'General Worker',   'ID-TT-198803150', 'NIS-2024-00147', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Port of Spain South', '1', '2026-04-20', '2026-05-03', 'Republic Bank',       '1102-4587-6321', 'Independence Square', 10, '',                'submitted',            '2026-04-25 12:00:00+00', '2026-04-26 18:00:00+00'),
    ('TS-006', 'WRK-002', 'Sasha Mohammed',     'Drain Cleaner',    'ID-TT-199207221', 'NIS-2024-00203', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Port of Spain East',  '1', '2026-04-20', '2026-05-03', 'First Citizens Bank', '2203-8765-1234', 'Park Street',         10, '',                'submitted',            '2026-04-25 12:00:00+00', '2026-04-27 00:00:00+00'),
    ('TS-007', 'WRK-003', 'Andre Williams',     'Road Maintenance', 'ID-TT-198511030', 'NIS-2023-01982', 150, 25, 40, '2', 'Chaguanas Borough Corporation',  'Chaguanas North',     '2', '2026-04-20', '2026-05-03', 'Scotiabank',          '3301-2244-5566', 'Chaguanas Main',      10, '',                'coordinatorReview',    '2026-04-24 12:00:00+00', '2026-04-26 00:00:00+00'),
    ('TS-008', 'WRK-004', 'Lisa Doodnath',      'General Worker',   'ID-TT-199005181', 'NIS-2024-00489', 150, 25, 40, '2', 'Chaguanas Borough Corporation',  'Chaguanas South',     '2', '2026-04-20', '2026-05-03', 'Republic Bank',       '1104-9876-5432', 'Chaguanas',           10, '',                'coordinatorReview',    '2026-04-24 12:00:00+00', '2026-04-26 08:00:00+00'),
    ('TS-009', 'WRK-006', 'Marcia Boodoo',      'Street Cleaner',   'ID-TT-198701251', 'NIS-2024-00788', 150, 25, 40, '3', 'San Fernando City Corporation',  'San Fernando East',   '3', '2026-04-20', '2026-05-03', 'First Citizens Bank', '2205-6677-8899', 'High Street',         10, '',                'hrProcessing',         '2026-04-22 12:00:00+00', '2026-04-25 08:00:00+00'),
    ('TS-010', 'WRK-007', 'Jason Baptiste',     'General Worker',   'ID-TT-199304141', 'NIS-2024-00912', 150, 25, 40, '3', 'San Fernando City Corporation',  'San Fernando West',   '3', '2026-04-20', '2026-05-03', 'Republic Bank',       '1106-1122-3344', 'San Fernando',         8, '',                'hrProcessing',         '2026-04-22 12:00:00+00', '2026-04-25 00:00:00+00'),
    ('TS-011', 'WRK-101', 'Ronald Persad',      'General Worker',   'ID-TT-199001011', 'NIS-2024-01501', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Port of Spain South', '1', '2026-04-20', '2026-05-03', 'Republic Bank',       '1109-1234-5678', 'Independence Square', 10, '',                'accountsProcessing',   '2026-04-20 12:00:00+00', '2026-04-25 20:00:00+00'),
    ('TS-012', 'WRK-102', 'Sandra Ramsaran',    'Landscaper',       'ID-TT-198802022', 'NIS-2024-01502', 150, 25, 40, '2', 'Chaguanas Borough Corporation',  'Chaguanas North',     '2', '2026-04-20', '2026-05-03', 'First Citizens Bank', '2206-8765-4321', 'Chaguanas',           10, '',                'accountsProcessing',   '2026-04-20 12:00:00+00', '2026-04-25 20:00:00+00'),
    ('TS-013', 'WRK-103', 'Derek Singh',        'Road Maintenance', 'ID-TT-199203033', 'NIS-2024-01503', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Laventille',          '1', '2026-04-20', '2026-05-03', 'Scotiabank',          '3304-5566-7788', 'Frederick Street',    10, '',                'approvedForPayment',   '2026-04-19 12:00:00+00', '2026-04-25 12:00:00+00'),
    ('TS-014', 'WRK-104', 'Angela Pierre',      'Street Cleaner',   'ID-TT-198504044', 'NIS-2024-01504', 150, 25, 40, '3', 'San Fernando City Corporation',  'San Fernando East',   '3', '2026-04-20', '2026-05-03', 'Republic Bank',       '1110-4455-6677', 'Coffee Street',       10, '',                'exported',             '2026-04-17 12:00:00+00', '2026-04-26 12:00:00+00'),
    ('TS-015', 'WRK-105', 'Michael James',      'General Worker',   'ID-TT-199106055', 'NIS-2024-01505', 150, 25, 40, '8', 'Port of Spain City Corporation', 'Morvant',             '1', '2026-04-20', '2026-05-03', 'JMMB Bank',           '5503-2233-4455', 'Ariapita Avenue',     10, '',                'exported',             '2026-04-17 12:00:00+00', '2026-04-26 12:00:00+00'),
    ('TS-016', 'WRK-106', 'Patricia Garcia',    'General Worker',   'ID-TT-198707066', 'NIS-2024-01506', 150, 25, 40, '2', 'Chaguanas Borough Corporation',  'Chaguanas South',     '2', '2026-04-20', '2026-05-03', 'Republic Bank',       '1111-6677-8899', 'Chaguanas',           10, '',                'chequePrinting',       '2026-04-15 12:00:00+00', '2026-04-26 12:00:00+00'),
    ('TS-017', 'WRK-107', 'Vernon Alexander',   'Drain Cleaner',    'ID-TT-199308077', 'NIS-2024-01507', 150, 25, 40, '3', 'San Fernando City Corporation',  'San Fernando West',   '3', '2026-04-20', '2026-05-03', 'First Citizens Bank', '2207-9988-7766', 'High Street',         10, '',                'chequePrinting',       '2026-04-15 12:00:00+00', '2026-04-26 12:00:00+00');

-- ── Timesheet daily entries ──────────────────────────────────────────────────
-- Helpers expressed as INSERT…SELECT generate_series.
-- "Weekday entries": days 0..13 where day_index % 7 < 5 → 07:00–15:00.
-- "Partial entries": same pattern but only for day_index < 8.
-- "Empty entries":  no times for any day.

-- Weekday entries: TS-005, TS-006, TS-007, TS-008, TS-009, TS-010, TS-011..TS-017
INSERT INTO timesheet_daily_entries (timesheet_id, day_index, time_in, time_out)
SELECT ts.id, d.idx,
       CASE WHEN d.idx % 7 < 5 THEN TIME '07:00' ELSE NULL END,
       CASE WHEN d.idx % 7 < 5 THEN TIME '15:00' ELSE NULL END
  FROM (VALUES ('TS-005'),('TS-006'),('TS-007'),('TS-008'),('TS-009'),('TS-010'),
               ('TS-011'),('TS-012'),('TS-013'),('TS-014'),('TS-015'),('TS-016'),('TS-017')) AS ts(id)
  CROSS JOIN generate_series(0,13) AS d(idx);

-- Partial entries: TS-003, TS-004 — only first 8 days, weekdays only
INSERT INTO timesheet_daily_entries (timesheet_id, day_index, time_in, time_out)
SELECT ts.id, d.idx,
       CASE WHEN d.idx < 8 AND d.idx % 7 < 5 THEN TIME '07:00' ELSE NULL END,
       CASE WHEN d.idx < 8 AND d.idx % 7 < 5 THEN TIME '15:00' ELSE NULL END
  FROM (VALUES ('TS-003'),('TS-004')) AS ts(id)
  CROSS JOIN generate_series(0,13) AS d(idx);

-- Empty entries: TS-001, TS-002 — all NULL
INSERT INTO timesheet_daily_entries (timesheet_id, day_index, time_in, time_out)
SELECT ts.id, d.idx, NULL, NULL
  FROM (VALUES ('TS-001'),('TS-002')) AS ts(id)
  CROSS JOIN generate_series(0,13) AS d(idx);

-- ── Timesheet approval history ───────────────────────────────────────────────
INSERT INTO timesheet_approvals (timesheet_id, sequence_no, reviewer_name, reviewer_role, state, note, ts) VALUES
    -- Coordinator review entries
    ('TS-007', 1, 'Andre Williams',      'Worker',                'approved', 'Submitted for review',     '2026-04-26 12:00:00+00'),
    ('TS-008', 1, 'Lisa Doodnath',       'Worker',                'approved', 'Submitted',                 '2026-04-26 12:00:00+00'),

    -- HR processing entries
    ('TS-009', 1, 'Marcia Boodoo',       'Worker',                'approved', NULL,                        '2026-04-24 12:00:00+00'),
    ('TS-009', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', 'Verified attendance',       '2026-04-25 12:00:00+00'),
    ('TS-010', 1, 'Jason Baptiste',      'Worker',                'approved', NULL,                        '2026-04-24 12:00:00+00'),
    ('TS-010', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', 'All good',                  '2026-04-25 12:00:00+00'),

    -- Accounts processing entries
    ('TS-011', 1, 'Ronald Persad',       'Worker',                'approved', NULL,                        '2026-04-22 12:00:00+00'),
    ('TS-011', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-23 12:00:00+00'),
    ('TS-011', 3, 'Priya Maharaj',       'HR Department',         'approved', 'Compliance verified',       '2026-04-24 12:00:00+00'),
    ('TS-012', 1, 'Sandra Ramsaran',     'Worker',                'approved', NULL,                        '2026-04-22 12:00:00+00'),
    ('TS-012', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-23 12:00:00+00'),
    ('TS-012', 3, 'Priya Maharaj',       'HR Department',         'approved', 'Compliance verified',       '2026-04-24 12:00:00+00'),

    -- Approved for payment
    ('TS-013', 1, 'Derek Singh',         'Worker',                'approved', NULL,                        '2026-04-21 12:00:00+00'),
    ('TS-013', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-22 12:00:00+00'),
    ('TS-013', 3, 'Priya Maharaj',       'HR Department',         'approved', NULL,                        '2026-04-23 12:00:00+00'),
    ('TS-013', 4, 'James Roberts',       'Accounts',              'approved', 'Pay calculations verified', '2026-04-25 12:00:00+00'),

    -- Exported
    ('TS-014', 1, 'Angela Pierre',       'Worker',                'approved', NULL,                        '2026-04-19 12:00:00+00'),
    ('TS-014', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-20 12:00:00+00'),
    ('TS-014', 3, 'Priya Maharaj',       'HR Department',         'approved', NULL,                        '2026-04-21 12:00:00+00'),
    ('TS-014', 4, 'James Roberts',       'Accounts',              'approved', NULL,                        '2026-04-23 12:00:00+00'),
    ('TS-014', 5, 'James Roberts',       'Accounts',              'approved', 'Exported to paysheet',      '2026-04-26 12:00:00+00'),
    ('TS-015', 1, 'Michael James',       'Worker',                'approved', NULL,                        '2026-04-19 12:00:00+00'),
    ('TS-015', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-20 12:00:00+00'),
    ('TS-015', 3, 'Priya Maharaj',       'HR Department',         'approved', NULL,                        '2026-04-21 12:00:00+00'),
    ('TS-015', 4, 'James Roberts',       'Accounts',              'approved', NULL,                        '2026-04-23 12:00:00+00'),
    ('TS-015', 5, 'James Roberts',       'Accounts',              'approved', 'Exported to paysheet',      '2026-04-26 12:00:00+00'),

    -- Cheque printing / direct deposit
    ('TS-016', 1, 'Patricia Garcia',     'Worker',                'approved', NULL,                        '2026-04-17 12:00:00+00'),
    ('TS-016', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-18 12:00:00+00'),
    ('TS-016', 3, 'Priya Maharaj',       'HR Department',         'approved', NULL,                        '2026-04-20 12:00:00+00'),
    ('TS-016', 4, 'James Roberts',       'Accounts',              'approved', NULL,                        '2026-04-22 12:00:00+00'),
    ('TS-016', 5, 'James Roberts',       'Accounts',              'approved', 'Exported',                  '2026-04-24 12:00:00+00'),
    ('TS-016', 6, 'James Roberts',       'Accounts',              'approved', 'Direct deposit initiated',  '2026-04-26 12:00:00+00'),
    ('TS-017', 1, 'Vernon Alexander',    'Worker',                'approved', NULL,                        '2026-04-17 12:00:00+00'),
    ('TS-017', 2, 'Marcus Thompson',     'Regional Coordinator',  'approved', NULL,                        '2026-04-18 12:00:00+00'),
    ('TS-017', 3, 'Priya Maharaj',       'HR Department',         'approved', NULL,                        '2026-04-20 12:00:00+00'),
    ('TS-017', 4, 'James Roberts',       'Accounts',              'approved', NULL,                        '2026-04-22 12:00:00+00'),
    ('TS-017', 5, 'James Roberts',       'Accounts',              'approved', 'Exported',                  '2026-04-24 12:00:00+00'),
    ('TS-017', 6, 'James Roberts',       'Accounts',              'approved', 'Direct deposit initiated',  '2026-04-26 12:00:00+00');

-- ── Rosters ──────────────────────────────────────────────────────────────────
-- Two fortnights per corporation (current + previous).
-- Demo absences match _injectDemoAbsences: first worker absent on day 1
-- with reason 'Sick leave'; second worker absent on day 3 with no reason.

INSERT INTO rosters (id, corporation_id, corporation_name, fortnight_start, fortnight_end, last_modified) VALUES
    ('ROSTER-2-20260420', '2', 'Chaguanas Borough Corporation',  '2026-04-20', '2026-05-03', '2026-04-27 12:00:00+00'),
    ('ROSTER-2-20260406', '2', 'Chaguanas Borough Corporation',  '2026-04-06', '2026-04-19', '2026-04-13 12:00:00+00'),
    ('ROSTER-3-20260420', '3', 'San Fernando City Corporation',  '2026-04-20', '2026-05-03', '2026-04-27 12:00:00+00'),
    ('ROSTER-3-20260406', '3', 'San Fernando City Corporation',  '2026-04-06', '2026-04-19', '2026-04-13 12:00:00+00'),
    ('ROSTER-8-20260420', '8', 'Port of Spain City Corporation', '2026-04-20', '2026-05-03', '2026-04-27 12:00:00+00'),
    ('ROSTER-8-20260406', '8', 'Port of Spain City Corporation', '2026-04-06', '2026-04-19', '2026-04-13 12:00:00+00');

-- One worker_record per active worker per roster (active workers per corp).
INSERT INTO roster_worker_records (roster_id, worker_id)
SELECT r.id, w.id
  FROM rosters r
  JOIN workers w ON w.corporation_id = r.corporation_id AND w.is_active
                AND w.id IN ('WRK-001','WRK-002','WRK-003','WRK-004','WRK-005','WRK-007','WRK-009','WRK-010','WRK-011','WRK-012');

-- Day entries: weekday=present, weekend=absent (no reason). Demo absences
-- override day_index 1 (Tuesday) and day_index 3 (Thursday) for the first
-- two workers per roster, deterministically chosen by worker_id ordering.
INSERT INTO roster_day_entries (roster_id, worker_id, day_index, entry_date, is_present, absence_reason)
SELECT
    rwr.roster_id,
    rwr.worker_id,
    d.idx AS day_index,
    (r.fortnight_start + (d.idx || ' days')::INTERVAL)::DATE,
    -- present on weekdays, absent on weekends, with demo absences carved out
    CASE
        WHEN d.idx = 1 AND row_pos.rn = 1 THEN FALSE
        WHEN d.idx = 3 AND row_pos.rn = 2 THEN FALSE
        WHEN EXTRACT(DOW FROM (r.fortnight_start + (d.idx || ' days')::INTERVAL)) IN (0,6) THEN FALSE
        ELSE TRUE
    END AS is_present,
    CASE WHEN d.idx = 1 AND row_pos.rn = 1 THEN 'Sick leave' ELSE NULL END
  FROM roster_worker_records rwr
  JOIN rosters r ON r.id = rwr.roster_id
  JOIN LATERAL (
       SELECT row_number() OVER (PARTITION BY rwr.roster_id ORDER BY rwr.worker_id) AS rn
  ) row_pos ON TRUE
  CROSS JOIN generate_series(0,13) AS d(idx);

-- ── Backpay records ──────────────────────────────────────────────────────────
-- Seed one calculated record matching the Q1 2026 Backpay audit entry.
INSERT INTO backpay_records (
    id, worker_id, worker_name, corporation_id, corporation_name,
    effective_from, old_wage_rate, new_wage_rate, old_cola_rate, new_cola_rate,
    status, note, calculated_at, calculated_by_user_id
) VALUES
    ('BP-2026-0001', 'WRK-001', 'Kevin Rampersad', '8', 'Port of Spain City Corporation',
     '2026-01-01', 140, 150, 25, 25, 'calculated',
     'Retroactive to 01/01/2026',
     '2026-04-22 09:00:00+00', 'USR-001');

INSERT INTO backpay_line_items (
    backpay_record_id, timesheet_id, fortnight_start, days_worked,
    old_daily_rate, new_daily_rate, old_cola_rate, new_cola_rate
) VALUES
    ('BP-2026-0001', 'TS-005', '2026-04-20', 10, 140, 150, 25, 25);

-- =============================================================================
-- Application audit log seed
-- =============================================================================
-- The Dart audit trail is hash-chained. Computing real chain hashes here would
-- require duplicating the Dart payload format in plpgsql; instead the seeded
-- entries carry explicit `previous_hash` linkage and a deterministic synthetic
-- hash, so the chain is internally consistent for read-only display. The
-- moment a real backend writes the first new entry, that entry will be hashed
-- correctly and the chain continues from there.
--
-- App callers that verify chain integrity should treat seeded rows as the
-- "genesis prefix" by accepting the seeded hashes as authoritative.

WITH seed AS (
    SELECT * FROM (VALUES
        -- (id, days_ago, user_id, user_name, user_role, action, entity_type, entity_id, entity_display_name, note)
        ('AUDIT-000001', 30, 'admin',     'System Administrator', 'System Admin',           'login',             'userAccount',  'admin',                 'System Administrator',                                              'Initial system login'),
        ('AUDIT-000002', 28, 'admin',     'System Administrator', 'System Admin',           'create',            'worker',       'WRK-001',               'Kevin Rampersad',                                                    NULL),
        ('AUDIT-000003', 25, 'hr-001',    'HR Officer',           'HR Department',          'documentUpload',    'document',     'WRK-001-NIS',           'Kevin Rampersad – NIS Registration',                                NULL),
        ('AUDIT-000004', 24, 'hr-001',    'HR Officer',           'HR Department',          'documentApprove',   'document',     'WRK-001-NIS',           'Kevin Rampersad – NIS Registration',                                'Document verified and approved'),
        ('AUDIT-000005', 20, 'coord-001', 'Regional Coordinator', 'Regional Coordinator',   'create',            'timesheet',    'TS-001',                'Kevin Rampersad – Fortnight 17/03/2026',                            NULL),
        ('AUDIT-000006', 18, 'coord-001', 'Regional Coordinator', 'Regional Coordinator',   'stageAdvanced',     'timesheet',    'TS-001',                'Kevin Rampersad – Fortnight 17/03/2026',                            'Time entries verified in field'),
        ('AUDIT-000007', 14, 'admin',     'System Administrator', 'System Admin',           'wageRateChanged',   'worker',       'WRK-001',               'Kevin Rampersad',                                                    'Annual collective-agreement increase'),
        ('AUDIT-000008', 10, 'hr-001',    'HR Officer',           'HR Department',          'update',            'worker',       'WRK-003',               'Andre Williams',                                                     NULL),
        ('AUDIT-000009',  7, 'admin',     'System Administrator', 'System Admin',           'replacementAdded',  'worker',       'WRK-006',               'Marcia Boodoo (replaced by Patricia Hernandez)',                     'Repeated absenteeism and conduct issues'),
        ('AUDIT-000010',  5, 'admin',     'System Administrator', 'System Admin',           'backpayCalculated', 'backpay',      'BP-2026-001',           'Q1 2026 Backpay – Kevin Rampersad',                                  'Retroactive to 01/01/2026'),
        ('AUDIT-000011',  3, 'hr-001',    'HR Officer',           'HR Department',          'rosterUpdate',      'rosterEntry',  'ROSTER-2026-04-11',     'Chaguanas Borough Corporation – Fortnight 11/04/2026',               'Updated absences for fortnight'),
        ('AUDIT-000012',  1, 'admin',     'System Administrator', 'System Admin',           'export',            'timesheet',    'BATCH-2026-04',         'Payroll Export – April 2026 (Port of Spain)',                        '12 timesheets exported to XLSX'),
        ('AUDIT-000013',  1, 'admin',     'System Administrator', 'System Admin',           'paymentRecorded',   'payment',      'PAY-2026-04-A',         'Direct Deposit Run – Port of Spain (April 2026)',                    '12 workers paid via direct deposit')
    ) AS v(id, days_ago, user_id, user_name, user_role, action, entity_type, entity_id, entity_display_name, note)
)
INSERT INTO app_audit_logs (
    id, timestamp, user_id, user_name, user_role, session_id,
    action, entity_type, entity_id, entity_display_name, note,
    hash, previous_hash
)
SELECT
    s.id,
    ('2026-04-27 12:00:00+00'::TIMESTAMPTZ - (s.days_ago || ' days')::INTERVAL),
    s.user_id, s.user_name, s.user_role,
    'demo-session-' || s.user_id,
    s.action::audit_action_enum,
    s.entity_type::audit_entity_type_enum,
    s.entity_id, s.entity_display_name, s.note,
    encode(digest(s.id || '|seed', 'sha256'), 'hex'),
    COALESCE(LAG(encode(digest(s.id || '|seed', 'sha256'), 'hex'))
             OVER (ORDER BY s.id), '')
  FROM seed s;

-- Field changes for entries that record diffs
INSERT INTO app_audit_field_changes (audit_log_id, sequence_no, field_name, old_value, new_value) VALUES
    ('AUDIT-000002', 1, 'Full Name',    NULL,                'Kevin Rampersad'),
    ('AUDIT-000002', 2, 'NIS Number',   NULL,                'NIS-2024-00147'),
    ('AUDIT-000002', 3, 'Position',     NULL,                'General Worker'),
    ('AUDIT-000002', 4, 'Corporation',  NULL,                'Port of Spain City Corporation'),

    ('AUDIT-000003', 1, 'Status',       'Missing',           'Uploaded'),
    ('AUDIT-000003', 2, 'File',         NULL,                'nis_registration.pdf'),

    ('AUDIT-000005', 1, 'Stage',        NULL,                'Draft'),
    ('AUDIT-000005', 2, 'Days Worked',  NULL,                '10'),

    ('AUDIT-000006', 1, 'Stage',        'Submitted',         'Coordinator Review'),

    ('AUDIT-000007', 1, 'Wage Rate',    '140.00',            '150.00'),
    ('AUDIT-000007', 2, 'Effective From', NULL,              '2026-01-01'),

    ('AUDIT-000008', 1, 'Phone Number', '868-555-0303',      '868-777-0303'),
    ('AUDIT-000008', 2, 'Address',      '22 Montrose Road, Chaguanas', '45 Montrose Road, Chaguanas'),

    ('AUDIT-000009', 1, 'Status',              'Active',     'Inactive'),
    ('AUDIT-000009', 2, 'Replacement Worker',  NULL,         'Patricia Hernandez (WRK-011)'),

    ('AUDIT-000010', 1, 'Old Rate',             NULL,        '140.00'),
    ('AUDIT-000010', 2, 'New Rate',             NULL,        '150.00'),
    ('AUDIT-000010', 3, 'Fortnights Affected',  NULL,        '6'),
    ('AUDIT-000010', 4, 'Backpay Amount',       NULL,        '600.00'),

    ('AUDIT-000011', 1, 'Andre Williams – Mon 13/04', 'Present', 'Absent'),
    ('AUDIT-000011', 2, 'Lisa Doodnath – Fri 17/04',  'Present', 'Absent');

-- Attachments on the payment-recorded entry
INSERT INTO app_audit_attachments (id, audit_log_id, file_name, mime_type, size_bytes, content_hash, uploaded_at) VALUES
    ('ATT-001', 'AUDIT-000013', 'paysheet_pos_april_2026.xlsx',
     'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
     24576,
     'a4f2b7c91d8e6053e2f471aa9c3d6b8852f1c0d7e6b9a4f3c1d8e6053e2f471aa',
     '2026-04-26 12:00:00+00'),
    ('ATT-002', 'AUDIT-000013', 'bank_remittance_advice.pdf',
     'application/pdf',
     152432,
     'b9c3d6f2e1a87045d3c5b9e8f0a172bd5e84c2f9a1b6d307f4e8c2b1d50a9f6e',
     '2026-04-26 12:00:00+00');

COMMIT;

-- =============================================================================
-- End of script
-- Validation queries you can run after psql -f db/domain_schema.sql:
--   SELECT count(*) FROM workers;                  -- expect 19
--   SELECT count(*) FROM worker_documents;         -- expect 95
--   SELECT count(*) FROM timesheets;               -- expect 17
--   SELECT count(*) FROM timesheet_daily_entries;  -- expect 238
--   SELECT count(*) FROM timesheet_approvals;      -- expect 38
--   SELECT count(*) FROM rosters;                  -- expect 6
--   SELECT count(*) FROM app_audit_logs;           -- expect 13
-- =============================================================================
