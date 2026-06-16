// ──────────────────────────────────────────────────────────────────────────────
// WorkForce — Supabase-backed authentication
//
// Real auth provider that replaces the demo credential map in AuthService.
// Kept as a separate, parallel service so the migration can be done screen by
// screen: wire LoginScreen and main.dart to this once the Supabase instance is
// provisioned (see db/supabase/README.md), then retire the demo AuthService.
//
// On a successful sign-in the Supabase access token (JWT) is pushed into the
// existing ApiClient so REST calls — and PostgREST, if you point ApiClient at
// Supabase — carry the bearer token and satisfy the RLS policies.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

/// Profile row from npups_core.app_users joined to the auth user.
class WorkforceProfile {
  final String id;
  final String email;
  final String? fullName;
  final String? corporationId;
  final bool isGlobal;
  final List<String> roles;

  const WorkforceProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.corporationId,
    this.isGlobal = false,
    this.roles = const [],
  });
}

class SupabaseAuthService extends ChangeNotifier {
  static final SupabaseAuthService _instance = SupabaseAuthService._internal();
  factory SupabaseAuthService() => _instance;
  SupabaseAuthService._internal();

  final ApiClient _api = ApiClient();

  SupabaseClient get _sb => Supabase.instance.client;

  User? get currentUser => _sb.auth.currentUser;
  Session? get session => _sb.auth.currentSession;
  bool get isAuthenticated => currentUser != null;

  WorkforceProfile? _profile;
  WorkforceProfile? get profile => _profile;

  /// Subscribe to Supabase auth changes so the UI can react to token refresh
  /// and sign-out. Call once after Supabase.initialize.
  void start() {
    _sb.auth.onAuthStateChange.listen((state) {
      _api.authToken = state.session?.accessToken;
      if (state.session == null) _profile = null;
      notifyListeners();
    });
    // Pick up an already-restored session.
    _api.authToken = session?.accessToken;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await _sb.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _api.authToken = res.session?.accessToken;
    await _loadProfile();
    notifyListeners();
    return res;
  }

  Future<AuthResponse> signUp(String email, String password) {
    return _sb.auth.signUp(email: email.trim(), password: password);
  }

  Future<void> resetPassword(String email) {
    return _sb.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
    _api.authToken = null;
    _profile = null;
    notifyListeners();
  }

  /// Loads the caller's npups_core.app_users row + assigned role codes.
  Future<WorkforceProfile?> _loadProfile() async {
    final id = currentUser?.id;
    if (id == null) return null;
    try {
      final row = await _sb
          .schema('npups_core')
          .from('app_users')
          .select('id, email, full_name, corporation_id, is_global')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;

      final roleRows = await _sb
          .schema('npups_core')
          .from('user_roles')
          .select('role_code')
          .eq('user_id', id);

      _profile = WorkforceProfile(
        id: row['id'] as String,
        email: row['email'] as String,
        fullName: row['full_name'] as String?,
        corporationId: row['corporation_id'] as String?,
        isGlobal: (row['is_global'] as bool?) ?? false,
        roles: (roleRows as List)
            .map((r) => (r as Map)['role_code'] as String)
            .toList(),
      );
      return _profile;
    } catch (e) {
      debugPrint('SupabaseAuthService: failed to load profile: $e');
      return null;
    }
  }
}
