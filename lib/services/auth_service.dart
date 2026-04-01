import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Authentication Service — Demo Implementation
// 7 demo accounts covering all roles for the timesheet approval pipeline:
//   Worker, Regional Coordinator, HR, Sub-Accounts, Main Accounts, PS, Admin
//
// Includes role switcher for demo purposes.
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

  // Rate limiting: track failed login attempts
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 2);

  // Session timeout: auto-logout after inactivity
  DateTime? _lastActivity;
  static const Duration sessionTimeout = Duration(minutes: 30);

  NpupsUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_isSessionExpired;
  bool get isLoading => _isLoading;
  bool get isLockedOut =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);
  int get remainingLockoutSeconds => isLockedOut
      ? _lockoutUntil!.difference(DateTime.now()).inSeconds
      : 0;

  bool get _isSessionExpired {
    if (_lastActivity == null || _currentUser == null) return false;
    return DateTime.now().difference(_lastActivity!) > sessionTimeout;
  }

  /// Call this on any user interaction to keep session alive.
  void touchSession() {
    if (_currentUser != null) {
      _lastActivity = DateTime.now();
    }
  }

  // Demo credentials — all roles for pipeline demo
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
    'worker@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-004',
        email: 'worker@npups.gov.tt',
        fullName: 'Kevin Rampersad',
        role: UserRole.worker,
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
      ),
    ),
    'accounts@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-005',
        email: 'accounts@npups.gov.tt',
        fullName: 'James Roberts',
        role: UserRole.subAccounts,
        corporationName: 'All Corporations',
      ),
    ),
    'ps@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-006',
        email: 'ps@npups.gov.tt',
        fullName: 'Dr. Sharon Rowley',
        role: UserRole.ps,
        corporationName: 'All Corporations',
      ),
    ),
    'mainaccounts@npups.gov.tt': _DemoCredential(
      password: 'test123',
      user: const NpupsUser(
        id: 'USR-007',
        email: 'mainaccounts@npups.gov.tt',
        fullName: 'Catherine Williams',
        role: UserRole.mainAccounts,
        corporationName: 'All Corporations',
      ),
    ),
  };

  /// Authenticate with email and password.
  /// Includes rate limiting: locks out after [_maxFailedAttempts] failed attempts.
  Future<AuthResult> signIn(String email, String password) async {
    // Check lockout
    if (isLockedOut) {
      return AuthResult.error(
        'Too many failed attempts. Please wait $remainingLockoutSeconds seconds before trying again.',
      );
    }

    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1500));

    final credential = _demoAccounts[email.toLowerCase().trim()];

    if (credential == null || credential.password != password) {
      _isLoading = false;
      _recordFailedAttempt();
      notifyListeners();
      return AuthResult.error('Invalid email or password.');
    }

    if (!credential.user.isActive) {
      _isLoading = false;
      notifyListeners();
      return AuthResult.error('This account has been deactivated.');
    }

    // Successful login — reset rate limiting and start session
    _failedAttempts = 0;
    _lockoutUntil = null;
    _lastActivity = DateTime.now();
    _currentUser = credential.user;
    _isLoading = false;
    notifyListeners();
    return AuthResult.ok(credential.user);
  }

  void _recordFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxFailedAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
    }
  }

  /// Check if the session has expired and sign out if so.
  /// Returns true if the session was expired and user was signed out.
  bool checkSessionExpiry() {
    if (_currentUser != null && _isSessionExpired) {
      _currentUser = null;
      _lastActivity = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Switch role instantly (demo only) — no re-login needed.
  void switchRole(UserRole role) {
    final account = _demoAccounts.values.firstWhere(
      (c) => c.user.role == role,
      orElse: () => _demoAccounts.values.first,
    );
    _currentUser = account.user;
    notifyListeners();
  }

  /// Sign out the current user and clear session.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = null;
    _lastActivity = null;
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

  /// Get all available roles for the switcher.
  static List<UserRole> get availableRoles =>
      _demoAccounts.values.map((c) => c.user.role).toSet().toList();
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
