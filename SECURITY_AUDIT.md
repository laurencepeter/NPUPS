# NPUPS Security Audit Report

**Date:** April 2026
**Scope:** Full codebase review — authentication, authorization, data handling, infrastructure, memory, optimization
**Overall Production Readiness:** Prototype/Demo only — critical items must be resolved before production

---

## Executive Summary

NPUPS is a Flutter web/mobile application managing a multi-stage timesheet approval pipeline for 14 municipal corporations in Trinidad & Tobago. The application is currently in **demo/prototype** mode with in-memory data stores and hardcoded credentials. This audit identifies **5 critical**, **4 high**, and **6 medium** severity findings.

---

## Critical Findings

### C1. Hardcoded Credentials in Source Code
**File:** `lib/services/auth_service.dart:67-141`
**Severity:** CRITICAL

7 demo accounts with plaintext passwords (`admin123`, `test123`) are embedded in source code and exposed to the UI via the `demoAccounts` getter (line 231). Passwords are visible in source, compiled binary, Docker image, and Git history.

**Fix:** Replace with Supabase GoTrue authentication (already referenced in code comments). If demo mode is needed, gate it behind `kDebugMode` and load credentials from a non-versioned config.

### C2. No Server-Side Authorization
**File:** All data stores and screen files
**Severity:** CRITICAL

All data stores are client-side singletons. No backend enforces role-based access control. Any role can call any mutation (e.g., `advanceStage`, `batchAdvance`) without verification.

**Fix:** Implement Supabase Row Level Security (RLS) policies enforcing role-based data access at the database level.

### C3. Client-Side-Only Authentication
**File:** `lib/services/auth_service.dart`, `lib/main.dart`
**Severity:** CRITICAL

Authentication is entirely client-side. Users can manipulate the app state via browser DevTools to change roles or bypass login.

**Fix:** Implement server-side authentication with Supabase GoTrue, issuing JWTs validated on every API request.

### C4. Role Switcher Bypasses Authentication
**File:** `lib/main.dart:378-381`, `lib/services/auth_service.dart:210-217`
**Severity:** CRITICAL

The `switchRole()` method allows instant role switching without re-authentication, exposed in the UI navigation bar.

**Fix:** Guard behind `kDebugMode` or remove entirely. Production builds must require re-login for role changes.

### C5. Hardcoded PII in Source Code
**Files:** `lib/services/worker_data_store.dart`, `lib/services/timesheet_data_store.dart`
**Severity:** CRITICAL

Realistic-looking worker PII (names, NIS numbers, ID numbers, bank accounts, DOBs) is hardcoded in source. Even if fictional, this pattern is dangerous when real data is introduced.

**Fix:** Move demo seed data behind a debug flag. Use a database for production data with encryption at rest.

---

## High Findings

### H1. No HTTPS / Missing Security Headers
**Files:** `nginx.conf`, `Dockerfile`
**Severity:** HIGH

Application served over HTTP only (port 80). No TLS, no HSTS, no CSP, no X-Frame-Options, no X-Content-Type-Options headers.

**Fix:** Configure TLS termination, add security headers, redirect HTTP to HTTPS.

### H2. Username Enumeration via Error Messages
**File:** `lib/services/auth_service.dart:160-171`
**Severity:** HIGH

Login distinguishes between "No account found" and "Incorrect password", allowing attackers to confirm valid email addresses.

**Fix:** Use a generic message: "Invalid email or password."

### H3. Dockerfile Runs as Root
**File:** `Dockerfile`
**Severity:** HIGH

The nginx container runs as root by default. No non-root user is configured.

**Fix:** Add `USER nginx` directive after setting file ownership.

### H4. Client-Side-Only Rate Limiting
**File:** `lib/services/auth_service.dart:36-39`
**Severity:** HIGH

Rate limiting (5 attempts / 2-minute lockout) is in-memory and client-side only. Refreshing the page or opening a new tab resets the counter.

**Fix:** Implement server-side rate limiting via Supabase edge functions or nginx `limit_req_zone`.

---

## Medium Findings

### M1. TextEditingController Memory Leak
**File:** `lib/screens/coordinator_review_screen.dart:292-328`
**Severity:** MEDIUM

Controller disposed in `.then()` — won't dispose if dialog dismissed via back button or system gesture.

**Fix:** Use `.whenComplete()` instead of `.then()`.

### M2. Paint Objects Created Every Frame
**File:** `lib/screens/login_screen.dart:815-817`
**Severity:** MEDIUM

20 `Paint()` objects created per animation frame in the particle painter, increasing GC pressure.

**Fix:** Cache and reuse Paint objects, updating only the color property.

### M3. Uncached Computed Values in Data Stores
**File:** `lib/services/timesheet_data_store.dart:51-59`
**Severity:** MEDIUM

`getStageCountsByCorporation()` and similar methods rebuild maps from scratch on every call with no memoization.

**Fix:** Cache results and invalidate on mutation.

### M4. ListenableBuilder Rebuilds Entire Widget Tree
**File:** `lib/screens/worker_detail_screen.dart:54-62`
**Severity:** MEDIUM

Listening to entire `WorkerDataStore` triggers rebuilds for ANY worker change, not just the one being viewed.

**Fix:** Use a `ValueNotifier<Worker>` for single-worker reactivity or implement selector pattern.

### M5. No File Size Limits on Upload
**File:** `lib/screens/timesheet_upload_screen.dart:183-220`
**Severity:** MEDIUM

No size validation on uploaded Excel files. Large or malformed files could exhaust memory.

**Fix:** Add file size check before processing (e.g., reject files > 10MB).

### M6. Unused ScrollController (Dead Code)
**File:** `lib/screens/timesheet_screen.dart:80`
**Severity:** LOW

`_scrollController` is declared and disposed but never attached to any widget.

**Fix:** Remove if unused.

---

## Security Practices Already In Place

| Practice | Implementation | Location |
|---|---|---|
| PII Masking | NIS, bank accounts, ID numbers masked for display | `security_utils.dart:12-35` |
| File Name Sanitization | Path traversal prevention, null byte removal, safe char whitelist | `security_utils.dart:39-52` |
| Email Validation | Basic regex check | `security_utils.dart:55-58` |
| Rate Limiting (client) | 5 attempts / 2-min lockout | `auth_service.dart:36-39` |
| Session Timeout | 30-minute inactivity auto-logout | `auth_service.dart:42-43` |
| Session Touch | Activity tracking on navigation | `main.dart:148-149` |
| Lifecycle-Aware Auth | Session expiry checked on app resume | `main.dart:73-78` |
| Immutable Data Access | `List.unmodifiable()` prevents direct store mutation | Both data stores |
| Mounted Checks | `if (!mounted) return` after async ops | Multiple screens |
| Animation Lifecycle | Animations paused when app backgrounded | `login_screen.dart:83-93` |
| No .env Committed | No environment files in repository | Verified |
| CI Secrets Handled | GitHub Actions uses `secrets` context | `.github/workflows/deploy.yml` |

---

## Priority Action Items

1. Replace demo auth with Supabase GoTrue
2. Implement Row Level Security (RLS) for role-based data access
3. Remove role switcher behind debug flag
4. Add HTTPS + security headers to nginx
5. Run container as non-root user
6. Unify login error messages to prevent enumeration
7. Move rate limiting server-side
8. Fix TextEditingController disposal
9. Cache computed values in data stores
10. Add `.gitignore` rules for `.env*`, `*.key`, `*.pem` as safeguard
