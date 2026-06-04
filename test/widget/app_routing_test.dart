import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce/main.dart' show WorkForceApp;
import 'package:workforce/screens/login_screen.dart';
import 'package:workforce/services/auth_service.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    if (auth.isAuthenticated) await auth.signOut();
  });

  group('WorkForceApp routing', () {
    testWidgets('unauthenticated user sees the LoginScreen', (tester) async {
      await tester.pumpWidget(const WorkForceApp());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
      'authenticated user sees the bottom navigation bar',
      (tester) async {
        // Sign in before building the app so it starts authenticated.
        await signInAsAdmin(AuthService());

        await tester.pumpWidget(const WorkForceApp());
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(find.byType(NavigationBar), findsOneWidget);
      },
    );
  });

  group('Role-based tab counts', () {
    Future<void> assertTabCount(
      WidgetTester tester,
      UserRole role,
      int expectedCount,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      if (auth.isAuthenticated) await auth.signOut();

      await auth.signIn(
        AuthService.demoAccounts
            .firstWhere((a) => a.role == role.displayName)
            .email,
        'test123',
      );

      await tester.pumpWidget(const WorkForceApp());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        navBar.destinations.length,
        expectedCount,
        reason:
            'Expected $expectedCount tabs for role ${role.displayName}',
      );
    }

    testWidgets('worker role shows 2 tabs', (tester) async {
      await assertTabCount(tester, UserRole.worker, 2);
    });
  });
}
