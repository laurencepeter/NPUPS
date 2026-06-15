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

CREATE TABLE IF NOT EXISTS npups_bank.bank_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES npups_bank.payment_batches,
  format text NOT NULL,
  storage_path text NOT NULL,
  sha256 bytea NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now()
);
