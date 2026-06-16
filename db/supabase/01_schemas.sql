-- =============================================================================
-- NPUPS — Supabase multi-schema layout (Step 1 of 9)
-- =============================================================================
-- Run these files in numeric order in the Supabase SQL Editor.
-- They create isolated `npups_*` schemas so NPUPS can coexist with other
-- projects in the same Postgres instance and be exposed selectively through
-- PostgREST.
--
-- After running all 9 files: Settings -> API -> Exposed schemas, add:
--   npups_core, npups_ref, npups_hr, npups_time, npups_pay, npups_bank
-- (Leave npups_audit unexposed — service_role only.)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS npups_core;
CREATE SCHEMA IF NOT EXISTS npups_ref;
CREATE SCHEMA IF NOT EXISTS npups_hr;
CREATE SCHEMA IF NOT EXISTS npups_time;
CREATE SCHEMA IF NOT EXISTS npups_pay;
CREATE SCHEMA IF NOT EXISTS npups_bank;
CREATE SCHEMA IF NOT EXISTS npups_audit;

GRANT USAGE ON SCHEMA
  npups_core, npups_ref, npups_hr, npups_time, npups_pay, npups_bank
  TO authenticated, service_role;

GRANT USAGE ON SCHEMA npups_audit TO service_role;
