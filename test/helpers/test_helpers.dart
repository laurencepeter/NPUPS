import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workforce/services/auth_service.dart';
import 'package:workforce/theme/app_theme.dart';

/// Wraps [child] in a minimal MaterialApp with WorkForce themes applied.
Widget buildTestApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    home: child,
  );
}

/// Resets the AuthService singleton and clears SharedPreferences.
Future<void> resetAuth() async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthService();
  if (auth.isAuthenticated) {
    await auth.signOut();
  }
}

/// Signs in the test harness as the system administrator.
Future<void> signInAsAdmin(AuthService auth) async {
  await auth.signIn('admin@workforce.app', 'admin123');
}

/// Returns a [WidgetTester] pump that advances time past the signIn delay.
Future<void> pumpUntilSettled(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pumpAndSettle();
}
