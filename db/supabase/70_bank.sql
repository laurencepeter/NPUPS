-- =============================================================================
-- NPUPS — Banking: payment batches, instructions, files (Step 8 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_bank.payment_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  run_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  approved_by uuid,
  approved_at timestamptz,
  total_amount numeric(16,2) NOT NULL,
  currency char(3) NOT NULL
);

CREATE TABLE IF NOT EXISTS npups_bank.payment_instructions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES npups_bank.payment_batches ON DELETE CASCADE,
  payslip_id uuid NOT NULL REFERENCES npups_pay.payslips,
  bank_code text NOT NULL,
  branch_code text,
  account_number text NOT NULL,
  amount numeric(14,2) NOT NULL,
  reference text NOT NULL
);
-- Covering indexes for the payment_instructions FKs (lint 0001). The batch_id
-- index also speeds the ON DELETE CASCADE when a payment_batch is removed.
CREATE INDEX IF NOT EXISTS payment_instructions_batch_idx   ON npups_bank.payment_instructions (batch_id);
CREATE INDEX IF NOT EXISTS payment_instructions_payslip_idx ON npups_bank.payment_instructions (payslip_id);

CREATE TABLE IF NOT EXISTS npups_bank.bank_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES npups_bank.payment_batches,
  format text NOT NULL,
  storage_path text NOT NULL,
  sha256 bytea NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now()
);
-- Covering index for the bank_files.batch_id FK (lint 0001).
CREATE INDEX IF NOT EXISTS bank_files_batch_idx ON npups_bank.bank_files (batch_id);
