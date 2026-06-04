import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce/services/auth_service.dart';
import 'package:workforce/models/user_model.dart';

// AuthService is a singleton; use resetRateLimitingForTest() + signOut() to
// restore clean state between tests so rate-limit counters don't bleed.
void main() {
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    auth = AuthService();
    auth.resetRateLimitingForTest();
    if (auth.isAuthenticated) await auth.signOut();
  });

  group('AuthService.signIn — success', () {
    test('returns AuthResult.ok for valid admin credentials', () async {
      final result = await auth.signIn('admin@workforce.app', 'admin123');
      expect(result.success, isTrue);
      expect(result.user, isNotNull);
      expect(result.user!.role, UserRole.systemAdmin);
      expect(result.errorMessage, isNull);
    });

    test('sets currentUser and isAuthenticated on success', () async {
      await auth.signIn('admin@workforce.app', 'admin123');
      expect(auth.currentUser, isNotNull);
      expect(auth.isAuthenticated, isTrue);
    });

    test('trims whitespace and lowercases the email', () async {
      final result = await auth.signIn('  ADMIN@WORKFORCE.APP  ', 'admin123');
      expect(result.success, isTrue);
    });

    test('succeeds for every configured demo account', () async {
      final cases = [
        ('coordinator@workforce.app', 'test123'),
        ('hr@workforce.app', 'test123'),
        ('worker@workforce.app', 'test123'),
        ('accounts@workforce.app', 'test123'),
        ('ps@workforce.app', 'test123'),
        ('mainaccounts@workforce.app', 'test123'),
        ('executive@workforce.app', 'test123'),
        ('dmcr@workforce.app', 'test123'),
      ];
      for (final (email, password) in cases) {
        auth.resetRateLimitingForTest();
        await auth.signOut();
        final result = await auth.signIn(email, password);
        expect(result.success, isTrue, reason: 'Expected success for $email');
      }
    });
  });

  group('AuthService.signIn — failure', () {
    test('returns error for an unknown email', () async {
      final result = await auth.signIn('nobody@unknown.com', 'abc');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('No account found'));
    });

    test('returns error for a wrong password', () async {
      final result = await auth.signIn('admin@workforce.app', 'wrongpass');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Incorrect password'));
    });

    test('does not set currentUser on failure', () async {
      await auth.signIn('admin@workforce.app', 'wrongpass');
      expect(auth.currentUser, isNull);
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('AuthService rate limiting', () {
    // setUp resets rate-limiting state, so each test starts from zero.

    test('resets failed-attempts counter after a successful login', () async {
      for (var i = 0; i < 3; i++) {
        await auth.signIn('admin@workforce.app', 'bad');
      }
      await auth.signIn('admin@workforce.app', 'admin123');
      expect(auth.isLockedOut, isFalse);
    });

    test('locks out after 5 consecutive failed attempts', () async {
      for (var i = 0; i < 5; i++) {
        await auth.signIn('admin@workforce.app', 'bad');
      }
      expect(auth.isLockedOut, isTrue);
    });

    test('blocked signIn returns lockout error message', () async {
      for (var i = 0; i < 5; i++) {
        await auth.signIn('admin@workforce.app', 'bad');
      }
      final result = await auth.signIn('admin@workforce.app', 'admin123');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Too many failed attempts'));
    });

    test('remainingLockoutSeconds is positive while locked out', () async {
      for (var i = 0; i < 5; i++) {
        await auth.signIn('admin@workforce.app', 'bad');
      }
      expect(auth.remainingLockoutSeconds, greaterThan(0));
    });
  });

  group('AuthService.signOut', () {
    test('clears currentUser and isAuthenticated', () async {
      await auth.signIn('admin@workforce.app', 'admin123');
      await auth.signOut();
      expect(auth.currentUser, isNull);
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('AuthService.switchRole', () {
    test('changes the current user role without re-login', () async {
      await auth.signIn('admin@workforce.app', 'admin123');
      auth.switchRole(UserRole.worker);
      expect(auth.currentUser!.role, UserRole.worker);
    });
  });

  group('AuthService.demoAccounts', () {
    test('returns at least one demo account entry', () {
      expect(AuthService.demoAccounts.isNotEmpty, isTrue);
    });

    test('every entry has non-empty email, password, role, and name', () {
      for (final account in AuthService.demoAccounts) {
        expect(account.email.isNotEmpty, isTrue);
        expect(account.password.isNotEmpty, isTrue);
        expect(account.role.isNotEmpty, isTrue);
        expect(account.name.isNotEmpty, isTrue);
      }
    });
  });

  group('AuthService.availableRoles', () {
    test('returns all distinct roles with no duplicates', () {
      final roles = AuthService.availableRoles;
      expect(roles.toSet().length, roles.length);
    });
  });
}
