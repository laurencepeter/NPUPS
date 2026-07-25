-- =============================================================================
-- NPUPS — Reference / lookup data (Step 2 of 9)
-- =============================================================================

CREATE TABLE IF NOT EXISTS npups_ref.countries (
  iso2 char(2) PRIMARY KEY,
  iso3 char(3) NOT NULL,
  name text NOT NULL
);

CREATE TABLE IF NOT EXISTS npups_ref.currencies (
  code char(3) PRIMARY KEY,
  name text NOT NULL,
  minor_unit smallint NOT NULL DEFAULT 2
);

CREATE TABLE IF NOT EXISTS npups_ref.banks (
  bank_code text PRIMARY KEY,
  swift_bic char(11),
  name text NOT NULL,
  country_iso2 char(2) REFERENCES npups_ref.countries
);
-- Covering index for the banks.country_iso2 FK (lint 0001).
CREATE INDEX IF NOT EXISTS banks_country_idx ON npups_ref.banks (country_iso2);

CREATE TABLE IF NOT EXISTS npups_ref.public_holidays (
  jurisdiction text NOT NULL,
  holiday_date date NOT NULL,
  name text NOT NULL,
  PRIMARY KEY (jurisdiction, holiday_date)
);

INSERT INTO npups_ref.currencies(code, name) VALUES
  ('TTD','Trinidad and Tobago Dollar'),
  ('USD','US Dollar')
ON CONFLICT DO NOTHING;

INSERT INTO npups_ref.countries(iso2, iso3, name) VALUES
  ('TT','TTO','Trinidad and Tobago')
ON CONFLICT DO NOTHING;
