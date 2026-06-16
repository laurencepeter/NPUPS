# NPUPS — Supabase schema

Multi-schema layout so NPUPS can live alongside other projects in one
self-hosted (Coolify) Supabase Postgres instance and be exposed selectively
through PostgREST.

## Run order (Supabase SQL Editor)

Run each file top to bottom, in numeric order:

| # | File | Creates |
|---|------|---------|
| 1 | `01_schemas.sql` | `npups_*` schemas + grants |
| 2 | `10_ref.sql` | countries, currencies, banks, holidays |
| 3 | `20_core.sql` | corporations, app_users, roles |
| 4 | `30_audit.sql` | append-only audit log |
| 5 | `40_hr.sql` | workers, documents, allowances, replacements |
| 6 | `50_time.sql` | rosters, timesheets, leave |
| 7 | `60_pay.sql` | tax, deductions, payslips, backpay |
| 8 | `70_bank.sql` | payment batches, instructions, files |
| 9 | `99_rls.sql` | RLS + tenant isolation |

All scripts are idempotent (`IF NOT EXISTS` / `DROP POLICY IF EXISTS`), so
re-running them is safe.

## Schemas

```
npups_core    corporations, app_users, roles, user_roles
npups_ref     countries, currencies, banks, public_holidays
npups_hr      workers, worker_documents, worker_allowances, worker_replacements
npups_time    rosters, timesheets, daily entries, approvals, leave
npups_pay     tax_brackets, nis_rates, deductions, payslips, backpay, tax certs
npups_bank    payment_batches, payment_instructions, bank_files
npups_audit   audit_logs (service_role only — NOT exposed via the API)
```

## After running the scripts

1. **Expose schemas to the API.** Supabase Studio → *Settings → API → Exposed
   schemas*, add:
   ```
   npups_core, npups_ref, npups_hr, npups_time, npups_pay, npups_bank
   ```
   Leave `npups_audit` out.

2. **Add the tenant claim to JWTs.** Studio → *Authentication → Hooks →
   Customize Access Token (JWT) Claims*, point it at this function:
   ```sql
   CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
   RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
   DECLARE corp uuid;
   BEGIN
     SELECT corporation_id INTO corp
     FROM npups_core.app_users
     WHERE id = (event->>'user_id')::uuid;
     RETURN jsonb_set(event, '{claims,corporation_id}', to_jsonb(corp::text), true);
   END $$;
   GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb)
     TO supabase_auth_admin;
   ```
   Then enable the hook. The RLS policies in `99_rls.sql` read this claim.

3. **Seed a corporation + link a user** (after the user signs up in the app):
   ```sql
   INSERT INTO npups_core.corporations(code, name, country_iso2, base_currency)
   VALUES ('DEMO','Demo Corporation','TT','TTD')
   RETURNING id;
   -- then, using the new corporation id and the auth.users id:
   INSERT INTO npups_core.app_users(id, email, full_name, corporation_id, is_global)
   VALUES ('<auth.users id>','admin@example.com','Admin','<corporation id>', true);
   ```

## Notes

- These scripts are for the **Supabase** instance only. They are intentionally
  kept out of the docker-compose Postgres init (`db/*.sql`) because they use
  Supabase-only roles (`authenticated`, `service_role`) and `auth.uid()`.
- No partitioning / `pg_cron` / `pg_partman` is required — the audit table is a
  plain table to keep setup portable across Supabase plans.
