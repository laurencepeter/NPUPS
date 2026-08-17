# NPUPS / WorkForce — Security Audit Report

**Classification:** Confidential — Internal Security Review
**Assessment type:** White-box source-code audit (full repository access)
**Scope:** Flutter web frontend, Node.js REST API, PostgreSQL/Supabase data layer, container & CI/CD infrastructure
**Date:** 17 August 2026
**Assessor:** Senior Cyber-Security Specialist

> **Data-handling note:** This report deliberately contains **no live secrets, credentials, keys, or real personal data**. Sensitive artefacts found in the codebase are described by *location and type only* — never reproduced — so the report itself introduces no new data-leak surface.

---

## 1. Executive Summary

WorkForce/NPUPS is an HR and payroll platform that stores highly sensitive personal
and financial data for municipal workers — full names, dates of birth, national ID
numbers, NIS numbers, passport and driver's-permit numbers, home addresses, bank
name / account number / branch, and wage/COLA/allowance rates — and drives a
multi-stage payroll approval pipeline across nine organisational roles.

The audit finds that, **as currently wired, the platform is not secure and must not
be operated against real employee data.** Authentication exists only inside the
browser; the backend that actually holds the data trusts every caller. The strong
security design that *does* exist in the repository (Supabase Auth + row-level
security) is present but **not connected to the running application**.

| Metric | Assessment |
|---|---|
| **Overall risk rating** | **CRITICAL** |
| **Security maturity (current)** | **Level 1 of 5 — Ad-hoc / Prototype** |
| **Production-ready for real PII/payroll?** | **No** |
| **Assessor confidence** | **High (~95%)** — conclusions drawn from direct white-box review of the full source, not inference |
| **Critical findings** | 4 |
| **High findings** | 6 |
| **Medium findings** | 5 |
| **Low / hygiene** | 4 |

**The single most important fact:** every `/api/*` endpoint on the backend is
reachable with **no authentication of any kind**. Anyone who can route a request
to the API can read, create, modify, or delete every worker record, timesheet,
payroll/back-pay record, and audit-log entry in the system. Today the *only*
control standing between an attacker and the full PII dataset is network
placement (the API is meant to be internal-only) — a single, fragile line of
defence.

---

## 2. Architecture as Actually Deployed

```
Browser ──▶ nginx (serves Flutter web, port 80) ──▶ Node/Express API (:8080) ──▶ Supabase (PostgreSQL)
              public origin                            internal-only, ONE shared key, NO auth
```

The repository contains **two divergent security models**, and the audit's central
problem is that the insecure one is the one that runs:

| | **Model A — what runs today** | **Model B — designed but dormant** |
|---|---|---|
| Authentication | `AuthService` — hardcoded demo credentials, entirely in-browser | `SupabaseAuthService` — real Supabase Auth (JWT) |
| Data path | Flutter → Node API (shared anon key, no user identity) | Flutter → Supabase directly, per-user JWT |
| Authorization | UI-only role gating; `switchRole()` with no re-auth | Postgres **row-level security** (`db/supabase/99_rls.sql`), tenant isolation by JWT `corporation_id` |
| Audit integrity | Hash chain computed *client-side*, stored verbatim | RLS: audit insert restricted to `service_role` |

`lib/main.dart` initialises Supabase and calls `SupabaseAuthService().start()`, but
the app's actual sign-in gate is `_authService.isAuthenticated` — the **demo**
service. `SupabaseAuthService` is instantiated and then never used to authorise
anything. RLS therefore never executes, because no end-user JWT ever reaches the
database on the live path.

---

## 3. Findings

Severity uses standard CVSS-style banding (Critical / High / Medium / Low) weighted
by data sensitivity (PII + financial + payroll).

### CRITICAL

#### C-1 — Backend REST API has no authentication or authorization
**Location:** `server/index.js` (entire file)
Every route — `/api/workers`, `/api/timesheets`, `/api/backpay-records`,
`/api/audit-logs`, `/api/rosters`, allowances, documents, approvals — is registered
with **no auth middleware, no token check, no session check**. `GET /api/workers`
returns the *complete* unmasked PII and banking dataset for every worker. `POST` /
`PATCH` / `DELETE` allow arbitrary creation, modification, and (soft-)deletion.
**Impact:** Total loss of confidentiality *and* integrity of all worker, payroll,
and audit data to anyone who can reach the API. This is the dominant risk in the
system.

#### C-2 — Authentication is client-side only and cosmetic
**Location:** `lib/services/auth_service.dart`, `lib/main.dart`
Login is a hardcoded credential map compiled into the shipped web app. It gates only
what the browser *renders*; it places **no constraint on the API**, which is where
the data lives. An attacker never needs to log in — they call the API directly.
Passwords live in source (and thus in the compiled bundle) in plaintext.
**Impact:** The "login" provides no security boundary. Authentication is
effectively absent from the system as a whole.

#### C-3 — Broken access control: role/RBAC enforced only in the UI
**Location:** `lib/services/auth_service.dart` (`switchRole()`), all screens, `server/index.js`
The nine-role approval pipeline (Worker → Coordinator → HR → Sub-/Main-Accounts →
PS → Executive → Admin) is enforced purely in Flutter. `switchRole()` lets any
session assume **any** role instantly with no re-authentication. The API applies no
role checks, so approvals, wage-rate changes, and back-pay can be forged directly
against `/api/timesheets/:id/approvals` and `/api/backpay-records`.
**Impact:** Any actor can approve payroll, change wage rates, and manufacture
financial records — direct fraud and integrity exposure.

#### C-4 — Audit trail is forgeable ("tamper-evident" claim is unsubstantiated)
**Location:** `lib/services/audit_service.dart`, `server/index.js` (`POST /api/audit-logs`)
The SHA-256 hash chain is computed **on the client** and the server stores whatever
`hash`, `previous_hash`, `user_id`, and `user_role` the request supplies. Chain
verification also runs only client-side. An attacker can POST a fully self-consistent
forged chain, or overwrite provenance fields, and it will verify. The design intent
(RLS: audit insert only via `service_role`) is contradicted by the live path, which
inserts via the shared anon key.
**Impact:** The audit log — described in-code as suitable for "legal/compliance
use" — cannot be relied upon as evidence. Actions are non-repudiable in appearance
only.

### HIGH

#### H-1 — Supabase anon key hardcoded in source and git history
**Location:** `lib/config/supabase_config.dart` (also present in git history)
A Supabase anon JWT is committed with a ~100-year expiry (year ~2126). A public anon
key is only safe **when RLS is enforced** — which it is not on the live path. The key
must be rotated and, critically, its safety premise (RLS) must be made true.

#### H-2 — RLS designed but never enforced on the live path
**Location:** `db/supabase/99_rls.sql` vs `server/index.js`
Tenant isolation and audit-insert restrictions are well-designed but never execute,
because all traffic is proxied through the Node API using one shared key with no
per-user JWT. The best control in the codebase is inert.

#### H-3 — CORS fully open
**Location:** `server/index.js` — `app.use(cors())`
No origin allow-list. Combined with C-1, any website a victim visits can drive the
API from the victim's browser/network position.

#### H-4 — No enforced transport security (HTTPS/HSTS)
**Location:** `nginx.conf`, `docker-compose.prod.yml`
nginx listens on port 80 only; there is no HTTP→HTTPS redirect and no HSTS. TLS may
be terminated by the Coolify edge, but nothing in the reviewed configuration
guarantees or enforces it.

#### H-5 — No HTTP security headers
**Location:** `nginx.conf`
No Content-Security-Policy, X-Frame-Options, X-Content-Type-Options, Referrer-Policy,
or Permissions-Policy. Increases clickjacking and XSS blast radius.

#### H-6 — Verbose error responses leak internals
**Location:** `server/index.js` global error handler
Returns raw `err.message` (Supabase/Postgres error text) and the request path to the
client. Aids reconnaissance of schema and internal structure.

### MEDIUM

#### M-1 — No server-side rate limiting / brute-force or DoS protection
Login lockout exists only in the client (`AuthService`, in-memory, resets on reload)
and is moot because the API needs no login. No throttling → scraping, enumeration,
and denial-of-service are unimpeded. `express.json({ limit: '5mb' })` is generous.

#### M-2 — No input / schema validation on writes
**Location:** `server/index.js`
Bodies are trusted as-is; the client even supplies primary keys (`b.id`). No type,
length, or field-whitelist validation; relies on Postgres to reject.

#### M-3 — PII "masking" is cosmetic and client-side only
**Location:** `lib/services/security_utils.dart`
Masks only digits in the display layer and preserves letters; the API returns full
unmasked PII regardless. Not a data-protection control.

#### M-4 — No server-side session management
Sessions are `SharedPreferences` on the client; the 30-minute timeout is
client-enforced only. No revocation, no server session store.

#### M-5 — Client-supplied provenance fields
`user_id`, `user_name`, `reviewer_role`, `reviewer_name`, and `hash` all arrive from
the request body, making all recorded "who did this" data spoofable.

### LOW / HYGIENE

- **L-1** Demo credentials documented in `CLAUDE.md` and `README.md` (acceptable for a
  demo; must be removed and rotated before production).
- **L-2** No dependency-vulnerability scanning (`npm audit` / Dependabot) or container
  image scanning evident in CI.
- **L-3** Backend uses a single broad Supabase key rather than a least-privilege DB role.
- **L-4** No secret-scanning gate to prevent future key commits.

---

## 4. Key Security Features Required (Remediation Roadmap)

These are the capabilities the platform **must** have to be considered secure. They
map directly to the findings above and are ordered by priority.

| # | Required feature | Closes | Priority |
|---|---|---|---|
| **F-1** | **Server-enforced authentication** — retire demo `AuthService`; make `SupabaseAuthService` the sole gate. Every API request must carry a JWT the server verifies (signature against Supabase JWKS); reject anonymous calls. | C-1, C-2 | P0 |
| **F-2** | **Server-side authorization (RBAC + tenant isolation)** — either have the client talk to Supabase/PostgREST directly so RLS executes per-user, or forward the user JWT through the Node API (per-request Supabase client) so RLS applies. Add explicit role checks on every pipeline transition. Remove `switchRole()`. | C-3, H-2 | P0 |
| **F-3** | **Server-authoritative, append-only audit** — compute the hash chain server-side (or in a Postgres trigger), reject client hashes and provenance, restrict insert to `service_role`, deny UPDATE/DELETE, verify the chain server-side. | C-4, M-5 | P0 |
| **F-4** | **Secrets management + key rotation** — remove keys from source, rotate the committed anon key, never expose `service_role` to the client/proxy, store secrets in a vault. | H-1, L-4 | P0 |
| **F-5** | **Transport security** — enforce HTTPS end-to-end, HTTP→HTTPS redirect, HSTS, TLS 1.2+. | H-4 | P1 |
| **F-6** | **HTTP hardening** — `helmet` (CSP, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy); lock CORS to the app origin only. | H-3, H-5 | P1 |
| **F-7** | **Rate limiting + WAF** — throttle auth and data endpoints; edge bot/DoS protection. | M-1 | P1 |
| **F-8** | **Input validation** — schema validation (e.g. zod/express-validator) on every write; server-generated IDs; reject unknown fields. | M-2 | P1 |
| **F-9** | **Least-privilege DB role** for the API; scoped, short-lived tokens. | L-3 | P2 |
| **F-10** | **Sanitised error handling + centralised logging** — generic client errors, no PII in logs, alerting on anomalies and audit-chain breaks. | H-6, M-4 | P2 |
| **F-11** | **Real data protection** — encryption at rest, server-side data minimisation (not cosmetic masking), field-level encryption for bank/NIS where required, tested backups, retention policy. | M-3 | P2 |
| **F-12** | **CI security gates** — SAST, dependency + container scanning, secret scanning. | L-2, L-4 | P2 |

---

## 5. Recommendations for the Network / Infrastructure Team

Because application-layer auth is currently absent, **network controls are today the
only thing protecting the data.** That makes them essential *now* and still necessary
*after* the app is fixed (defence in depth). None of these substitute for F-1…F-4.

1. **Keep the API strictly internal** — confirm the `api` service has *no* public
   ingress and no DNS/route from the internet; only `web` should be exposed.
2. **Private networking & segmentation** — isolate web↔api↔Supabase on a private
   network; no public route to Supabase; default-deny firewall between tiers.
3. **Restrict egress** — allow the API to reach only the Supabase host; block all
   other outbound.
4. **Terminate TLS at the edge** — force HTTPS + HSTS, disable TLS < 1.2, manage
   certificates centrally.
5. **WAF + rate limiting / DDoS protection** at the reverse proxy or edge
   (e.g. Cloudflare); anomaly and geo rules; IP allow-listing for admin surfaces.
6. **Secrets in a managed vault** — rotate the leaked anon key immediately; scope and
   rotate tokens; never bake keys into images.
7. **Centralised logging / SIEM** — ship logs off-host; alert on 4xx/5xx spikes,
   auth failures, and audit-chain verification failures; ensure no PII in logs.
8. **Management-plane hardening** — MFA on Coolify, Supabase, and GitHub; access via
   VPN/bastion; least-privilege admin roles.
9. **Backups & resilience** — offsite, immutable (WORM) backups with periodically
   tested restores; consider immutable/anchored storage for the audit log.
10. **Ongoing assurance** — schedule external penetration testing and re-audit after
    F-1…F-4 land; adopt continuous dependency and image scanning.

---

## 6. Conclusion

The engineering quality of NPUPS/WorkForce is high and — importantly — a genuinely
secure design (Supabase Auth + row-level security) already exists in the repository.
The gap is not knowledge; it is **wiring**: the secure model is dormant while an
authentication-free path serves live data.

Until findings **C-1 through C-4** and features **F-1 through F-4** are addressed, the
platform must be treated as a **prototype** and must **not** process real employee PII
or payroll. Once server-side authentication, authorization, tamper-proof auditing, and
proper secrets handling are in place — backed by the network controls in Section 5 —
the platform can credibly reach a production-hardened posture (target maturity Level
4–5).

*Assessor confidence in these findings: **high (~95%)**, based on complete white-box
review of the source. Residual uncertainty relates only to runtime/edge configuration
(e.g. whether Coolify terminates TLS) that cannot be confirmed from the repository
alone.*
