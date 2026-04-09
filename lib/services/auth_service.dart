import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'api_client.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Authentication Service
// Authenticates against the PostgREST /rpc/login endpoint.
// JWT is stored in SharedPreferences (via ApiClient) and sent on every request.
//
// Session timeout is enforced client-side (30 min inactivity).
// Token expiry is enforced server-side (8 hours, set in 002_auth.sql).
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
  final ApiClient _api = ApiClient();

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

  /// Restore session from stored JWT on app start.
  Future<void> restoreSession() async {
    await _api.init();
    // We have a token but no user object yet — we can't call /users without
    // round-tripping the server, so we rely on the JWT claims embedded in the
    // token. For simplicity we leave _currentUser null and require a fresh
    // login after app restart. The token is retained for API calls if the user
    // navigates directly to an authenticated screen via deep link.
  }

  /// Authenticate with email and password.
  Future<AuthResult> signIn(String email, String password) async {
    if (isLockedOut) {
      return AuthResult.error(
        'Too many failed attempts. Please wait $remainingLockoutSeconds seconds.',
      );
    }

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _api.rpc('login', {
        'p_email': email.trim().toLowerCase(),
        'p_password': password,
      });

      final token = data['token'] as String;
      final userJson = data['user'] as Map<String, dynamic>;

      await _api.setToken(token);

      _currentUser = NpupsUser(
        id:              userJson['id'] as String,
        email:           userJson['email'] as String,
        fullName:        userJson['fullName'] as String,
        role:            UserRole.values.firstWhere(
                           (r) => r.name == userJson['role'],
                           orElse: () => UserRole.worker,
                         ),
        corporationId:   userJson['corporationId'] as String?,
        corporationName: null, // fetched lazily if needed
        isActive:        userJson['isActive'] as bool? ?? true,
      );

      _failedAttempts = 0;
      _lockoutUntil = null;
      _lastActivity = DateTime.now();
      _isLoading = false;
      notifyListeners();
      return AuthResult.ok(_currentUser!);
    } on ApiException catch (e) {
      _isLoading = false;
      _recordFailedAttempt();
      notifyListeners();
      if (e.statusCode == 400 || e.statusCode == 403) {
        return AuthResult.error('Invalid email or password.');
      }
      return AuthResult.error('Login failed. Please try again.');
    } catch (_) {
      _isLoading = false;
      _recordFailedAttempt();
      notifyListeners();
      return AuthResult.error('Cannot reach the server. Check your connection.');
    }
  }

  void _recordFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxFailedAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
    }
  }

  /// Check if the session has expired and sign out if so.
  bool checkSessionExpiry() {
    if (_currentUser != null && _isSessionExpired) {
      _currentUser = null;
      _lastActivity = null;
      _api.clearToken();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    _currentUser = null;
    _lastActivity = null;
    await _api.clearToken();
    _isLoading = false;
    notifyListeners();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// DemoAccountInfo retained for the login help sheet UI (shows example emails)
// Passwords are no longer shown — direct users to the system admin.
// ──────────────────────────────────────────────────────────────────────────────

class DemoAccountInfo {
  final String email;
  final String role;
  final String name;

  const DemoAccountInfo({
    required this.email,
    required this.role,
    required this.name,
  });
}
