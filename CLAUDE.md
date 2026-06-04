# WorkForce — Developer Reference

## Project Overview

**WorkForce** is a Flutter web app (+ Node.js REST API + PostgreSQL) for HR and payroll
management across municipal corporations. It replaces paper-based workflows for worker
registration, timesheet submission, and payroll processing.

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x / Dart 3.2+ |
| Backend | Node.js 18 + Express 4 |
| Database | PostgreSQL 16 |
| Infrastructure | Docker + nginx + GitHub Actions |

---

## UI Regression Testing

> **For future reference** — this section explains the complete testing strategy.

### Why UI Regression Tests Matter Here

WorkForce has 27 screens, 9 user roles, and a multi-step payroll approval pipeline. A
change to shared widgets (theme, navigation bar, form fields) or role-based routing can
silently break screens that aren't directly touched. Regression tests catch those breaks
before they reach production.

---

### Test Taxonomy

#### 1. Unit Tests (`test/unit/`)

Pure Dart, no Flutter framework required. Run in milliseconds. Cover:

| File | What It Tests |
|------|--------------|
| `security_utils_test.dart` | PII masking (bank, NIS, ID), file-name sanitisation, email validation |
| `user_model_test.dart` | `AppUser.initials`, role `displayName`/`description` completeness |
| `auth_service_test.dart` | Sign-in success/failure for every demo account, rate-limiting lockout, session management, role switching |

Run alone:
```bash
flutter test test/unit/ --reporter expanded
```

#### 2. Widget Tests (`test/widget/`)

Render Flutter widgets into a virtual canvas using `WidgetTester`. No real device
needed. Cover structural presence, interactions, and navigation routing.

| File | What It Tests |
|------|--------------|
| `login_screen_test.dart` | Fields rendered, demo email pre-fill, password obscure toggle, loading indicator, error message, `onLoginSuccess` callback |
| `app_routing_test.dart` | Unauthenticated → `LoginScreen`; authenticated → `NavigationBar`; worker role → 2 tabs |

Run alone:
```bash
flutter test test/widget/ --reporter expanded
```

#### 3. Golden / Visual Regression Tests (Future — not yet implemented)

Golden tests capture a pixel-perfect screenshot of a widget and compare it to a stored
baseline on every subsequent run. Flutter's built-in `matchesGoldenFile` matcher handles
this.

To add a golden test:
```dart
testWidgets('login screen visual baseline', (tester) async {
  await tester.pumpWidget(buildTestApp(LoginScreen(...)));
  await tester.pump(const Duration(seconds: 2));
  await expectLater(find.byType(LoginScreen), matchesGoldenFile('goldens/login.png'));
});
```

Generate/update baselines:
```bash
flutter test --update-goldens
```

Store golden files in `test/goldens/` and commit them. CI will fail automatically when
a visual change is introduced without an explicit golden update.

Recommended tools for richer visual diffing:
- **Alchemist** (`alchemist: ^0.9.0`) — multi-theme side-by-side golden comparisons
- **golden_toolkit** — provides `GoldenBuilder` for responsive layout grids

#### 4. Integration / E2E Tests (Future — not yet implemented)

End-to-end tests drive the full app on a real device or browser via
`package:integration_test`. They simulate complete user journeys.

Example journey to automate:
```
Login as coordinator → navigate to Timesheet → fill 14-day grid → submit → 
navigate to Review → verify status badge is "Pending HR Review"
```

Setup:
```bash
flutter pub add --dev integration_test
```

Test location: `integration_test/` (Flutter convention).

Run on Chrome:
```bash
flutter test integration_test/ -d chrome
```

---

### Running All Tests

```bash
# Dependencies
flutter pub get

# Linting
flutter analyze

# All automated tests (unit + widget)
flutter test --reporter expanded

# With coverage report
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

### CI/CD Pipeline

**`.github/workflows/test.yml`** — runs on every push and PR:
1. `dart format` check
2. `flutter analyze` (fatal on infos)
3. Unit tests (`test/unit/`)
4. Widget tests (`test/widget/`, Chrome driver)
5. Coverage upload to Codecov

**`.github/workflows/deploy.yml`** — runs on `master`/`main` only:
1. Docker multi-stage build
2. Push to GitHub Container Registry (`ghcr.io`)

The test workflow must pass before Docker deployment is meaningful. Consider adding
`needs: test` to the `build-and-deploy` job once the test suite is stable.

---

### Test Helpers (`test/helpers/test_helpers.dart`)

| Helper | Purpose |
|--------|---------|
| `buildTestApp(child)` | Wraps a widget in `MaterialApp` with WorkForce light/dark themes |
| `resetAuth()` | Clears `SharedPreferences` mock and signs out the singleton `AuthService` |
| `signInAsAdmin(auth)` | Signs in as `admin@workforce.app` / `admin123` |
| `pumpUntilSettled(tester)` | Advances time past the 1 500 ms `signIn` delay and calls `pumpAndSettle()` |

---

### Key Architectural Notes for Test Authors

- **`AuthService` is a singleton** — use `SharedPreferences.setMockInitialValues({})` in
  `setUp` and call `auth.signOut()` in teardown to prevent state bleed between tests.
- **Animation delays** — `LoginScreen` uses `AnimationController` timers. Use
  `tester.pump(Duration(seconds: 2))` before asserting widget state, or use
  `fakeAsync`/`FakeAsync` if you need deterministic time control.
- **Backend calls** — screens that call `ApiClient` will fail in widget tests unless you
  mock `http.Client`. Use `mockito`'s `@GenerateMocks([http.Client])` and pass the mock
  via the `apiClient` constructor parameter where available.

---

## Backend API Reference

Server entry: `server/index.js` on port `3000` (configurable via `PORT` env var).

PostgreSQL schemas:
- `db/rbac_schema.sql` — roles and permissions
- `db/domain_schema.sql` — workers, timesheets, rosters, payroll
- `db/edit_locks_schema.sql` — optimistic concurrency locks

## Local Development

```bash
# Start full stack
docker compose up

# Flutter web (hot reload)
flutter run -d chrome

# Backend only
cd server && node index.js
```

## Demo Credentials

| Role | Email | Password |
|------|-------|---------|
| System Admin | admin@workforce.app | admin123 |
| Regional Coordinator | coordinator@workforce.app | test123 |
| HR | hr@workforce.app | test123 |
| Worker | worker@workforce.app | test123 |
| Sub-Accounts | accounts@workforce.app | test123 |
| Permanent Secretary | ps@workforce.app | test123 |
| Main Accounts | mainaccounts@workforce.app | test123 |
| Executive Dept | executive@workforce.app | test123 |
| DMCR | dmcr@workforce.app | test123 |
