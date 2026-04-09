-- ══════════════════════════════════════════════════════════════════════════════
-- NPUPS Database Schema
-- National Programme for the Upkeep of Public Spaces
-- Ministry of Rural Development & Local Government, Trinidad & Tobago
-- ══════════════════════════════════════════════════════════════════════════════

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pgjwt";

-- ─────────────────────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TYPE user_role AS ENUM (
  'systemAdmin',
  'ps',
  'dmcr',
  'regionalCoordinator',
  'hr',
  'subAccounts',
  'mainAccounts',
  'ministersDepartment',
  'worker'
);

CREATE TYPE document_status AS ENUM (
  'uploaded',
  'missing',
  'pending'
);

CREATE TYPE timesheet_stage AS ENUM (
  'notStarted',
  'draft',
  'submitted',
  'coordinatorReview',
  'hrProcessing',
  'accountsProcessing',
  'approvedForPayment',
  'exported',
  'chequePrinting'
);

CREATE TYPE approval_state AS ENUM (
  'pending',
  'approved',
  'rejected'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- CORPORATIONS  (14 Municipal Corporations)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE corporations (
  id        TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  districts TEXT[] NOT NULL DEFAULT '{}'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE users (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  email            TEXT        UNIQUE NOT NULL,
  full_name        TEXT        NOT NULL,
  role             user_role   NOT NULL,
  corporation_id   TEXT        REFERENCES corporations(id),
  is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
  password_hash    TEXT        NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- WORKERS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE workers (
  id                 TEXT        PRIMARY KEY,   -- WRK-001 format
  full_name          TEXT        NOT NULL,
  nis_number         TEXT        NOT NULL UNIQUE,
  date_of_birth      DATE        NOT NULL,
  position           TEXT        NOT NULL,
  id_number          TEXT        NOT NULL,
  corporation_id     TEXT        NOT NULL REFERENCES corporations(id),
  electoral_district TEXT        NOT NULL,
  wage_rate          NUMERIC(10,2) NOT NULL DEFAULT 0,
  cola_rate          NUMERIC(10,2) NOT NULL DEFAULT 0,
  allowance_rate     NUMERIC(10,2) NOT NULL DEFAULT 0,
  bank_name          TEXT        NOT NULL,
  account_number     TEXT        NOT NULL,
  branch_name        TEXT        NOT NULL,
  date_registered    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_active          BOOLEAN     NOT NULL DEFAULT TRUE,
  contact            TEXT,
  address            TEXT,
  bir_number         TEXT,
  start_date         DATE,
  end_date           DATE,
  reference_number   TEXT
);

-- ─────────────────────────────────────────────────────────────────────────────
-- WORKER DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE worker_documents (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  worker_id   TEXT          NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  name        TEXT          NOT NULL,
  status      document_status NOT NULL DEFAULT 'missing',
  file_name   TEXT,
  uploaded_at TIMESTAMPTZ,
  UNIQUE (worker_id, name)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- WORKER REPLACEMENTS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE worker_replacements (
  id                     TEXT        PRIMARY KEY,  -- REP-001 format
  original_worker_id     TEXT        NOT NULL REFERENCES workers(id),
  replacement_worker_id  TEXT        NOT NULL REFERENCES workers(id),
  days_missed            INT         NOT NULL DEFAULT 0,
  reason                 TEXT        NOT NULL,
  replaced_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TIMESHEETS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE timesheets (
  id              UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  worker_id       TEXT            NOT NULL REFERENCES workers(id),
  group_number    TEXT            NOT NULL DEFAULT '',
  fortnight_start DATE            NOT NULL,
  fortnight_end   DATE            NOT NULL,
  allowance_days  INT             NOT NULL DEFAULT 0,
  remarks         TEXT            NOT NULL DEFAULT '',
  stage           timesheet_stage NOT NULL DEFAULT 'notStarted',
  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  UNIQUE (worker_id, fortnight_start)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TIMESHEET DAILY ENTRIES  (14 per timesheet)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE timesheet_daily_entries (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  timesheet_id UUID NOT NULL REFERENCES timesheets(id) ON DELETE CASCADE,
  day_index    INT  NOT NULL CHECK (day_index BETWEEN 0 AND 13),
  time_in      TIME,
  time_out     TIME,
  UNIQUE (timesheet_id, day_index)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- APPROVAL RECORDS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE approval_records (
  id             UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  timesheet_id   UUID           NOT NULL REFERENCES timesheets(id) ON DELETE CASCADE,
  reviewer_id    UUID           REFERENCES users(id),
  reviewer_name  TEXT           NOT NULL,
  reviewer_role  TEXT           NOT NULL,
  state          approval_state NOT NULL,
  note           TEXT,
  created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX idx_workers_corporation  ON workers(corporation_id);
CREATE INDEX idx_workers_active       ON workers(is_active);
CREATE INDEX idx_timesheets_worker    ON timesheets(worker_id);
CREATE INDEX idx_timesheets_stage     ON timesheets(stage);
CREATE INDEX idx_timesheets_fortnight ON timesheets(fortnight_start);
CREATE INDEX idx_approval_timesheet   ON approval_records(timesheet_id);
CREATE INDEX idx_documents_worker     ON worker_documents(worker_id);
CREATE INDEX idx_users_email          ON users(email);

-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATED_AT TRIGGER
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_timesheets_updated_at
  BEFORE UPDATE ON timesheets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
