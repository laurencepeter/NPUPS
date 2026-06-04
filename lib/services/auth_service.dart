import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// 8 demo accounts covering all roles for the timesheet approval pipeline:
//   Worker, Regional Coordinator, HR, Sub-Accounts, Main Accounts, PS, Admin,
//   Executive Department
//
// Includes role switcher for demo purposes.
// Production: Replace with your authentication provider
// ──────────────────────────────────────────────────────────────────────────────

class AuthResult {
  final bool success;
  final String? errorMessage;
  final AppUser? user;

  const AuthResult({
    required this.success,
    this.errorMessage,
    this.user,
  });

  factory AuthResult.error(String message) =>
      AuthResult(success: false, errorMessage: message);

  factory AuthResult.ok(AppUser user) =>
      AuthResult(success: true, user: user);
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  AppUser? _currentUser;
  bool _isLoading = false;

  // Rate limiting: track failed login attempts
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 2);

  // Session timeout: auto-logout after inactivity
  DateTime? _lastActivity;
  static const Duration sessionTimeout = Duration(minutes: 30);

  static const _keyEmail = 'session_email';
  static const _keyLoginMs = 'session_login_ms';

  AppUser? get currentUser => _currentUser;
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

  /// Restore a previously authenticated session from persistent storage.
  /// Call once in main() before runApp(). Does nothing if no session is saved
  /// or if the stored session has already expired.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail);
    final loginMs = prefs.getInt(_keyLoginMs);
    if (email == null || loginMs == null) return;

    final loginAt = DateTime.fromMillisecondsSinceEpoch(loginMs);
    if (DateTime.now().difference(loginAt) >= sessionTimeout) {
      await _clearPersistedSession(prefs);
      return;
    }

    final credential = _demoAccounts[email];
    if (credential == null || !credential.user.isActive) {
      await _clearPersistedSession(prefs);
      return;
    }

    _currentUser = credential.user;
    _lastActivity = DateTime.now();
  }

  Future<void> _saveSession(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setInt(_keyLoginMs, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _clearPersistedSession([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyLoginMs);
  }

  // Demo credentials — all roles for pipeline demo
  static final Map<String, _DemoCredential> _demoAccounts = {
    'admin@workforce.app': _DemoCredential(
      password: 'admin123',
      user: const AppUser(
        id: 'USR-001',
        email: 'admin@workforce.app',
        fullName: 'System Administrator',
        role: UserRole.systemAdmin,
        corporationName: 'All Corporations',
      ),
    ),
    'coordinator@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-002',
        email: 'coordinator@workforce.app',
        fullName: 'Marcus Thompson',
        role: UserRole.regionalCoordinator,
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
      ),
    ),
    'hr@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-003',
        email: 'hr@workforce.app',
        fullName: 'Priya Maharaj',
        role: UserRole.hr,
        corporationId: '2',
        corporationName: 'Chaguanas Borough Corporation',
      ),
    ),
    'worker@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-004',
        email: 'worker@workforce.app',
        fullName: 'Kevin Rampersad',
        role: UserRole.worker,
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
      ),
    ),
    'accounts@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-005',
        email: 'accounts@workforce.app',
        fullName: 'James Roberts',
        role: UserRole.subAccounts,
        corporationName: 'All Corporations',
      ),
    ),
    'ps@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-006',
        email: 'ps@workforce.app',
        fullName: 'Dr. Sharon Rowley',
        role: UserRole.ps,
        corporationName: 'All Corporations',
      ),
    ),
    'mainaccounts@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-007',
        email: 'mainaccounts@workforce.app',
        fullName: 'Catherine Williams',
        role: UserRole.mainAccounts,
        corporationName: 'All Corporations',
      ),
    ),
    'executive@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-008',
        email: 'executive@workforce.app',
        fullName: 'Raymond Ali',
        role: UserRole.ministersDepartment,
        corporationName: 'All Corporations',
      ),
    ),
    'dmcr@workforce.app': _DemoCredential(
      password: 'test123',
      user: const AppUser(
        id: 'USR-009',
        email: 'dmcr@workforce.app',
        fullName: 'Anika Ramlogan',
        role: UserRole.dmcr,
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

    if (credential == null) {
      _isLoading = false;
      _recordFailedAttempt();
      notifyListeners();
      return AuthResult.error('No account found with this email address.');
    }

    if (credential.password != password) {
      _isLoading = false;
      _recordFailedAttempt();
      notifyListeners();
      return AuthResult.error('Incorrect password. Please try again.');
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
    _saveSession(email.toLowerCase().trim());
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
      _clearPersistedSession();
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

  /// Resets in-memory rate-limiting state. Test use only.
  @visibleForTesting
  void resetRateLimitingForTest() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }

  /// Sign out the current user and clear session.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = null;
    _lastActivity = null;
    _isLoading = false;
    await _clearPersistedSession();
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
  final AppUser user;

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
