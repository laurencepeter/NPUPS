-- =============================================================================
-- NPUPS — Payroll: tax, deductions, payslips, backpay (Step 7 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_pay.tax_brackets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jurisdiction text NOT NULL,
  tax_year smallint NOT NULL,
  lower_bound numeric(14,2) NOT NULL,
  upper_bound numeric(14,2),
  rate numeric(6,4) NOT NULL,
  fixed_amount numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (jurisdiction, tax_year, lower_bound)
);

CREATE TABLE IF NOT EXISTS npups_pay.nis_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  effective_from date NOT NULL,
  effective_to date,
  weekly_floor numeric(10,2) NOT NULL,
  weekly_ceiling numeric(10,2) NOT NULL,
  employee_rate numeric(6,4) NOT NULL,
  employer_rate numeric(6,4) NOT NULL
);

CREATE TABLE IF NOT EXISTS npups_pay.deduction_types (
  code text PRIMARY KEY,
  name text NOT NULL,
  is_statutory boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS npups_pay.worker_deductions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  deduction_code text REFERENCES npups_pay.deduction_types,
  amount numeric(14,2),
  percent numeric(6,4),
  start_date date NOT NULL,
  end_date date,
  CHECK (amount IS NOT NULL OR percent IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS npups_pay.payslips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  period_start date NOT NULL,
  period_end date NOT NULL,
  gross numeric(14,2) NOT NULL,
  taxable numeric(14,2) NOT NULL,
  paye numeric(14,2) NOT NULL,
  nis_employee numeric(14,2) NOT NULL,
  health_surcharge numeric(14,2) NOT NULL,
  other_deductions numeric(14,2) NOT NULL,
  net numeric(14,2) NOT NULL,
  currency char(3) NOT NULL REFERENCES npups_ref.currencies,
  line_items jsonb NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (corporation_id, worker_id, period_start, period_end)
);

CREATE TABLE IF NOT EXISTS npups_pay.backpay_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  effective_from date NOT NULL,
  effective_to date NOT NULL,
  old_wage_rate numeric(10,4) NOT NULL,
  new_wage_rate numeric(10,4) NOT NULL,
  total_amount numeric(14,2) NOT NULL,
  cola_pct numeric(6,4),
  line_items jsonb
);

CREATE TABLE IF NOT EXISTS npups_pay.tax_certificates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  corporation_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES npups_hr.workers,
  tax_year smallint NOT NULL,
  jurisdiction text NOT NULL,
  total_gross numeric(14,2) NOT NULL,
  total_paye numeric(14,2) NOT NULL,
  total_nis numeric(14,2) NOT NULL,
  total_health_surcharge numeric(14,2) NOT NULL,
  pdf_path text,
  issued_at timestamptz,
  UNIQUE (worker_id, tax_year, jurisdiction)
);

INSERT INTO npups_pay.deduction_types(code, name, is_statutory) VALUES
  ('PAYE','Income Tax',true),
  ('NIS','National Insurance',true),
  ('HEALTH','Health Surcharge',true),
  ('UNION','Union Dues',false),
  ('LOAN','Loan Repayment',false),
  ('GARN','Garnishment',false)
ON CONFLICT DO NOTHING;
