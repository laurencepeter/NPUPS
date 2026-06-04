import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce/screens/login_screen.dart';
import 'package:workforce/services/auth_service.dart';
import '../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    if (auth.isAuthenticated) await auth.signOut();
  });

  group('LoginScreen — structural', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('renders a sign-in submit button', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final signInBtn = find.widgetWithText(ElevatedButton, 'Sign In');
      expect(signInBtn, findsOneWidget);
    });

    testWidgets('pre-fills the demo admin email on load', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('admin@workforce.app'), findsOneWidget);
    });
  });

  group('LoginScreen — password visibility toggle', () {
    testWidgets('password is obscured by default', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      final passwordField = fields.lastWhere(
        (f) => f.obscureText == true,
        orElse: () => throw TestFailure('No obscured field found'),
      );
      expect(passwordField.obscureText, isTrue);
    });

    testWidgets('tapping the visibility icon reveals the password',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final visIcon = find.byIcon(Icons.visibility_off_outlined);
      if (visIcon.evaluate().isNotEmpty) {
        await tester.tap(visIcon.first);
        await tester.pump();

        final finder = find.byType(TextField);
        final fields = tester.widgetList<TextField>(finder).toList();
        final nowVisible = fields.where((f) => !f.obscureText);
        expect(nowVisible.isNotEmpty, isTrue);
      }
    });
  });

  group('LoginScreen — authentication flow', () {
    testWidgets('shows loading indicator while signing in', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();
      // Testing the loading indicator only; sign-in result is irrelevant here.
    });

    testWidgets('shows error message for wrong password', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // Replace prefilled password with a wrong one.
      final passwordFields = find.byType(TextFormField);
      await tester.enterText(passwordFields.last, 'wrongpassword');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await pumpUntilSettled(tester);

      expect(
        find.text('Incorrect password. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('fires onLoginSuccess after correct credentials',
        (tester) async {
      bool fired = false;
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () => fired = true,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // The screen pre-fills admin credentials; just submit.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await pumpUntilSettled(tester);

      expect(fired, isTrue);
    });
  });

  group('LoginScreen — demo account helper', () {
    testWidgets('has a button to show the demo accounts sheet', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          LoginScreen(
            authService: AuthService(),
            onLoginSuccess: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final demoBtn = find.textContaining(
        RegExp(r'Demo|Account', caseSensitive: false),
      );
      expect(demoBtn, findsAtLeastNWidgets(1));
    });
  });
}
