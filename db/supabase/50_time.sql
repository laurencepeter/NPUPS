-- =============================================================================
-- NPUPS — Time: rosters, timesheets, leave (Step 6 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_time.rosters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL REFERENCES npups_core.corporations,
  period_start date NOT NULL,
  period_end date NOT NULL,
  attendance_settings jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Covering index for the rosters.corporation_id FK (lint 0001).
CREATE INDEX IF NOT EXISTS rosters_corp_idx ON npups_time.rosters (corporation_id);

CREATE TABLE IF NOT EXISTS npups_time.roster_day_entries (
  roster_id uuid REFERENCES npups_time.rosters ON DELETE CASCADE,
  worker_id uuid REFERENCES npups_hr.workers,
  day date NOT NULL,
  worked boolean NOT NULL DEFAULT true,
  absence_reason text,
  PRIMARY KEY (roster_id, worker_id, day)
);
-- roster_id is the PK's leading column, so it's already covered. worker_id is
-- not a PK prefix, so its FK needs its own covering index (lint 0001).
CREATE INDEX IF NOT EXISTS roster_day_entries_worker_idx ON npups_time.roster_day_entries (worker_id);

CREATE TABLE IF NOT EXISTS npups_time.timesheets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  period_start date NOT NULL,
  period_end date NOT NULL,
  stage text NOT NULL DEFAULT 'not_started',
  submitted_by uuid,
  submitted_at timestamptz,
  UNIQUE (worker_id, period_start, period_end)
);

CREATE TABLE IF NOT EXISTS npups_time.timesheet_daily_entries (
  timesheet_id uuid REFERENCES npups_time.timesheets ON DELETE CASCADE,
  day date NOT NULL,
  hours numeric(5,2) NOT NULL DEFAULT 0,
  notes text,
  PRIMARY KEY (timesheet_id, day)
);

CREATE TABLE IF NOT EXISTS npups_time.timesheet_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  timesheet_id uuid NOT NULL REFERENCES npups_time.timesheets ON DELETE CASCADE,
  approver_id uuid NOT NULL,
  stage text NOT NULL,
  decision text NOT NULL,
  comment text,
  at timestamptz NOT NULL DEFAULT now()
);
-- Covering index for the timesheet_approvals.timesheet_id FK (lint 0001); also
-- speeds the ON DELETE CASCADE when a timesheet is removed.
CREATE INDEX IF NOT EXISTS timesheet_approvals_timesheet_idx ON npups_time.timesheet_approvals (timesheet_id);

CREATE TABLE IF NOT EXISTS npups_time.leave_types (
  code text PRIMARY KEY,
  name text NOT NULL,
  accrual_per_year numeric(6,2),
  paid boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS npups_time.leave_balances (
  worker_id uuid REFERENCES npups_hr.workers,
  leave_code text REFERENCES npups_time.leave_types,
  as_of date NOT NULL,
  balance_days numeric(6,2) NOT NULL,
  PRIMARY KEY (worker_id, leave_code, as_of)
);
-- worker_id is the PK's leading column (already covered). leave_code is not a
-- PK prefix, so its FK to leave_types needs its own covering index (lint 0001).
CREATE INDEX IF NOT EXISTS leave_balances_leave_idx ON npups_time.leave_balances (leave_code);

CREATE TABLE IF NOT EXISTS npups_time.leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  leave_code text REFERENCES npups_time.leave_types,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  reason text
);
-- Covering indexes for the leave_requests.worker_id / leave_code FKs (lint 0001).
CREATE INDEX IF NOT EXISTS leave_requests_worker_idx ON npups_time.leave_requests (worker_id);
CREATE INDEX IF NOT EXISTS leave_requests_leave_idx  ON npups_time.leave_requests (leave_code);

INSERT INTO npups_time.leave_types(code, name, accrual_per_year) VALUES
  ('VAC','Vacation',14),
  ('SICK','Sick',14),
  ('BEREAVE','Bereavement',3),
  ('MAT','Maternity',98)
ON CONFLICT DO NOTHING;
