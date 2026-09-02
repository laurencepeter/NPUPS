# NPUPS / WorkForce — Network & Infrastructure Securing Guide

> For the network / infrastructure / security team.
> **Everything here is verified against the repository** (`docker-compose.prod.yml`,
> `nginx.conf`, `server/index.js`, `lib/config/supabase_config.dart`,
> `lib/services/`). It states the deployment as it actually is, then what must be
> true to secure it.

---

## 1. The one fact that drives everything

**The backend REST API has no application-layer authentication today.** Every
`/api/*` route in `server/index.js` is served with no token, session, or role
check. `GET /api/workers` returns the complete, unmasked PII + banking dataset.

**Therefore, right now, network placement is the only real control.** The app team
is adding server-side auth (see §7), but until that ships, the network tier *is* the
security boundary. This guide is written accordingly.

---

## 2. Deployment topology (as built)

```
                 public domain (TLS at edge — Coolify/reverse proxy)
                          │
                          ▼
        ┌─────────────────────────────────┐
        │  web  (nginx)  — listens :80     │   ← ONLY service that should be public
        │  serves Flutter bundle           │
        │  proxies /api/*  ─────────────┐  │
        └───────────────────────────────┼──┘
                                        ▼
        ┌─────────────────────────────────┐
        │  api  (Node/Express) — :8080     │   ← MUST stay internal-only
        │  no auth · shared Supabase key   │
        └───────────────┬─────────────────┘
                        ▼
        ┌─────────────────────────────────┐
        │  Supabase / PostgreSQL           │   ← external host
        │  https://supabase.fireydev.com   │
        └─────────────────────────────────┘
```

| Service | Port | Exposure (intended) | Source of truth |
|---|---|---|---|
| `web` (nginx + Flutter) | 80 | **Public** (behind edge TLS) | `docker-compose.prod.yml`, `nginx.conf` |
| `api` (Node/Express) | 8080 | **Internal only — `expose:`, no `ports:`, no domain** | `docker-compose.prod.yml` (header + `api` service) |
| Supabase (Postgres) | — | External SaaS/self-host | `SupabaseConfig`, server env |

- `web` and `api` talk over the Docker/Coolify private network. nginx forwards
  `/api/*` to `http://api:8080` (`API_UPSTREAM`).
- The compose file explicitly says: *"Do NOT give `api` a domain — it must stay
  internal."* Confirm this is honored in Coolify.

---

## 3. How the API authenticates to the database (important)

The Node API queries Supabase using a **single shared Supabase `anon` key**
(`SUPABASE_ANON_KEY`, set on the `api` service). It carries **no per-user
identity**. Consequences your team must account for:

- The per-user, tenant-isolating Row-Level Security policies in
  `db/supabase/99_rls.sql` key off a **user JWT's `corporation_id`**. On the live
  path there is no user JWT — so **those RLS policies cannot be enforcing** here.
- For the app to work at all through the anon key, the live tables must currently
  be readable/writable by the `anon` role (RLS off, or permissive `anon` policies).
- **Action:** confirm the live RLS state in the Supabase dashboard for every table
  the API touches (`workers`, `worker_documents`, `worker_allowances`,
  `worker_replacements`, `timesheets`, `timesheet_daily_entries`,
  `timesheet_approvals`, `rosters`, `roster_*`, `backpay_*`, `app_audit_*`,
  `roster_settings`). Treat "anon can read/write PII" as expected-until-fixed, and
  compensate at the network tier.

The **anon key is committed in source** (`lib/config/supabase_config.dart`, ~year-2126
expiry). It must be rotated (§4).

---

## 4. Network / infra checklist (do these now)

| # | Control | Why | Status |
|---|---|---|---|
| N-1 | **`api` has no public ingress** — no published port, no DNS, no route from the internet. Only `web` is exposed. | The API has no auth; public exposure = full PII/payroll breach. | ☐ |
| N-2 | **Private networking & segmentation** — web ↔ api ↔ Supabase on a private network; default-deny between tiers. | Contain lateral movement; keep DB unreachable from the internet. | ☐ |
| N-3 | **Restrict egress** — allow `api` outbound **only** to the Supabase host; block all other outbound. | Limits exfil paths and C2 if a tier is compromised. | ☐ |
| N-4 | **Enforce TLS end-to-end** — HTTP→HTTPS redirect, **HSTS**, TLS 1.2+ at the edge. nginx itself listens on plain `:80`, so TLS must be terminated/forced by Coolify or a fronting proxy. | `nginx.conf` sets no TLS and no HSTS. | ☐ |
| N-5 | **Add HTTP security headers at the edge** — CSP, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`. | `nginx.conf` sets none today (clickjacking/XSS blast radius). | ☐ |
| N-6 | **WAF + rate limiting / DDoS** at the edge — throttle `/api/*`; bot/geo rules; IP allow-list any admin surface. | API has no rate limiting; scraping/enumeration/DoS are unimpeded. | ☐ |
| N-7 | **Rotate the committed anon key**; move all secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) into a managed vault; never bake into images; keep `service_role` off the client/proxy entirely. | Key is in git history; a public anon key is only safe once RLS enforces. | ☐ |
| N-8 | **Backups** — offsite, encrypted, **immutable (WORM)**, with tested restores. Prioritise the audit tables. | Ransomware/tamper resilience; the audit log is evidence. | ☐ |
| N-9 | **Centralised logging / SIEM** — ship web+api logs off-host; alert on 4xx/5xx spikes and anomalies; ensure **no PII in logs** (the API's error handler currently echoes raw DB messages). | Detection + incident response. | ☐ |
| N-10 | **Management-plane hardening** — MFA on Coolify, Supabase, and GitHub; admin access via VPN/bastion; least-privilege roles. | The control planes are the highest-value targets. | ☐ |

---

## 5. Database securing (Supabase / PostgreSQL)

| # | Control | Notes |
|---|---|---|
| D-1 | **Confirm & set RLS** on every app table (see §3). Until the app forwards a user JWT, decide deliberately what the `anon` role may do. | `db/supabase/99_rls.sql` is the intended policy set. |
| D-2 | **Least-privilege DB role for the API** — replace the broad anon key with a scoped role/short-lived tokens once the auth path lands. | Currently one broad key. |
| D-3 | **No public route to Supabase** — DB reachable only from the `api` tier's private network. | |
| D-4 | **Backups & PITR** — enable automated backups (+ Point-in-Time Recovery before real payroll data); test restores monthly; verify the audit hash chain after restore. | See `DEMO_BRIEF.md` §7 for `pg_dump`/`pg_restore` commands. |
| D-5 | **Encryption at rest** for the database and for backup artifacts. | Dumps contain full PII. |

---

## 6. Division of responsibility

| Area | Network / Infra team | App / Dev team |
|---|---|---|
| Keep `api` internal-only | ✅ | provides compose/config |
| TLS/HSTS, security headers, WAF, rate limit (edge) | ✅ | — |
| Secrets vault + key rotation | ✅ (store/rotate) | remove keys from source |
| Backups, WORM, SIEM, MFA on control planes | ✅ | — |
| **Server-side auth (JWT verify) on every `/api/*`** | — | ✅ (see §7) |
| **RBAC + per-user RLS enforcement** | provides DB/network | ✅ wiring |
| Tamper-proof, server-authoritative audit | provides DB | ✅ |
| Input validation, sanitised errors | — | ✅ |

Network controls are essential **now** and remain necessary **after** the app is
fixed (defence in depth). They do not substitute for the app-layer fixes in §7.

---

## 7. What the app team is fixing (for context)

So the network team knows what changes are coming and can plan around them
(full detail + estimates in `DEMO_BRIEF.md` §6 and `security-audit/SECURITY_AUDIT_REPORT.md`):

1. Make Supabase Auth the sole sign-in gate; remove the hard-coded demo accounts
   and the demo role-switcher (`lib/services/auth_service.dart`).
2. Verify the Supabase JWT on every `/api/*` request and forward the user JWT so
   **RLS executes per user** — this makes the anon-key premise safe.
3. Add role checks on every pipeline transition; server-authoritative audit.
4. `helmet` headers, locked CORS, input validation, sanitised errors, server-side
   rate limiting (complements the edge WAF).

**Target: ~3–4 weeks to a production-hardened baseline** (then LDAP/AD SSO,
+2–4 weeks).

---

## 8. Quick reference — what to hand the network team

- This file (`NETWORK_HANDOFF.md`) — topology + checklist.
- `docker-compose.prod.yml` — service definitions, ports, healthchecks, the
  "keep `api` internal" note.
- `nginx.conf` — the reverse-proxy config (note: no TLS, no security headers).
- `security-audit/SECURITY_AUDIT_REPORT.md` — full findings + remediation roadmap.
- `DEMO_BRIEF.md` — API catalog, data flows, backup commands.
