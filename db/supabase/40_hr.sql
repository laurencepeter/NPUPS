-- =============================================================================
-- NPUPS — HR: workers, documents, allowances, replacements (Step 5 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_hr.workers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL REFERENCES npups_core.corporations,
  worker_code text NOT NULL,
  full_name text NOT NULL,
  nis_number text,
  id_number text,
  bank_code text REFERENCES npups_ref.banks,
  bank_account text,
  wage_rate numeric(10,4),
  currency char(3) REFERENCES npups_ref.currencies,
  hired_on date,
  terminated_on date,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  UNIQUE (corporation_id, worker_code)
);
CREATE INDEX IF NOT EXISTS workers_corp_idx ON npups_hr.workers (corporation_id);
-- Covering indexes for the workers.bank_code / workers.currency FKs (lint 0001).
CREATE INDEX IF NOT EXISTS workers_bank_idx     ON npups_hr.workers (bank_code);
CREATE INDEX IF NOT EXISTS workers_currency_idx ON npups_hr.workers (currency);

CREATE TABLE IF NOT EXISTS npups_hr.worker_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id uuid NOT NULL REFERENCES npups_hr.workers ON DELETE CASCADE,
  corporation_id uuid NOT NULL,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'missing',
  storage_path text,
  verified_by uuid,
  verified_at timestamptz
);
-- Covering index for the worker_documents.worker_id FK (lint 0001); also speeds
-- the ON DELETE CASCADE when a worker row is removed.
CREATE INDEX IF NOT EXISTS worker_documents_worker_idx ON npups_hr.worker_documents (worker_id);

CREATE TABLE IF NOT EXISTS npups_hr.worker_allowances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id uuid NOT NULL REFERENCES npups_hr.workers ON DELETE CASCADE,
  corporation_id uuid NOT NULL,
  code text NOT NULL,
  amount numeric(14,2) NOT NULL,
  currency char(3) NOT NULL,
  effective_from date NOT NULL,
  effective_to date
);
-- Covering index for the worker_allowances.worker_id FK (lint 0001); also speeds
-- the ON DELETE CASCADE when a worker row is removed.
CREATE INDEX IF NOT EXISTS worker_allowances_worker_idx ON npups_hr.worker_allowances (worker_id);

CREATE TABLE IF NOT EXISTS npups_hr.worker_replacements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  replaced_worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  replacement_worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  effective_from date NOT NULL,
  effective_to date,
  days_missed int NOT NULL DEFAULT 0
);
-- Covering indexes for the two worker FKs on worker_replacements (lint 0001).
CREATE INDEX IF NOT EXISTS worker_replacements_replaced_idx    ON npups_hr.worker_replacements (replaced_worker_id);
CREATE INDEX IF NOT EXISTS worker_replacements_replacement_idx ON npups_hr.worker_replacements (replacement_worker_id);
