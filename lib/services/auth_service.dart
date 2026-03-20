import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Authentication Service — Demo Implementation
// Provides 3 demo accounts per §5.1 requirements:
//   1. Admin account (System Admin role)
//   2. Regional Coordinator test user
//   3. HR Department test user
//
// Production: Replace with Supabase GoTrue (§2.3, §3.2)
// ──────────────────────────────────────────────────────────────────────────────

class AuthResult {
  final bool success;
  final String? errorMessage;
  final NpupsUser? user;

  const AuthResult({
    required this.success,
    this.errorMessage,
    this.user,
  });

  factory AuthResult.error(String message) =>
      AuthResult(success: false, errorMessage: message);

  factory AuthResult.ok(NpupsUser user) =>
      AuthResult(success: true, user: user);
}

class AuthService extends ChangeNotifier {
  NpupsUser? _currentUser;
  bool _isLoading = false;

  NpupsUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  // Demo credentials — 1 admin + 2 test users
  static final Map<String, _DemoCredential> _demoAccounts = {
    'admin@npups.gov.tt': _DemoCredential(
      password: 'admin123',
      user: const NpupsUser(
        id: 'USR-001',
        email: 'admin@npups.gov.tt',
        fullName: 'System Administrator',
        role: UserRole.systemAdmin,
        corporationName: 'All Corporations',
      ),
    ),
    'coordinator@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-002',
        email: 'coordinator@npups.gov.tt',
        fullName: 'Marcus Thompson',
        role: UserRole.regionalCoordinator,
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
      ),
    ),
    'hr@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-003',
        email: 'hr@npups.gov.tt',
        fullName: 'Priya Maharaj',
        role: UserRole.hr,
        corporationId: '2',
        corporationName: 'Chaguanas Borough Corporation',
      ),
    ),
  };

  /// Authenticate with email and password.
  /// Simulates network latency for realistic UX.
  Future<AuthResult> signIn(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    // Simulate network call (JWT token exchange per §9.1)
    await Future.delayed(const Duration(milliseconds: 1500));

    final credential = _demoAccounts[email.toLowerCase().trim()];

    if (credential == null) {
      _isLoading = false;
      notifyListeners();
      return AuthResult.error('No account found with this email address.');
    }

    if (credential.password != password) {
      _isLoading = false;
      notifyListeners();
      return AuthResult.error('Incorrect password. Please try again.');
    }

    if (!credential.user.isActive) {
      _isLoading = false;
      notifyListeners();
      return AuthResult.error('This account has been deactivated.');
    }

    _currentUser = credential.user;
    _isLoading = false;
    notifyListeners();
    return AuthResult.ok(credential.user);
  }

  /// Sign out the current user and invalidate session.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Get list of demo accounts for the login help sheet.
  static List<DemoAccountInfo> get demoAccounts {
    return _demoAccounts.entries.map((e) {
      return DemoAccountInfo(
        email: e.key,
        password: e.value.password,
        role: e.value.user.role.displayName,
        name: e.value.user.fullName,
      );
    }).toList();
  }
}

class _DemoCredential {
  final String password;
  final NpupsUser user;

  const _DemoCredential({required this.password, required this.user});
}

class DemoAccountInfo {
  final String email;
  final String password;
  final String role;
  final String name;

  const DemoAccountInfo({
    required this.email,
    required this.password,
    required this.role,
    required this.name,
  });
}
