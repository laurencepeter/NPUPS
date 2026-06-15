// ──────────────────────────────────────────────────────────────────────────────
// WorkForce — Supabase connection config
//
// Values are injected at build time via --dart-define so no secrets are baked
// into source. For a self-hosted (Coolify) Supabase instance, point SUPABASE_URL
// at your Kong/API gateway URL and use the project's ANON (public) key.
//
//   flutter build web \
//     --dart-define=SUPABASE_URL=https://supabase.example.com \
//     --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
//
// When the URL/key are absent the app skips Supabase initialization and keeps
// working against the existing demo AuthService / REST ApiClient, so local and
// demo builds are unaffected.
// ──────────────────────────────────────────────────────────────────────────────

class SupabaseConfig {
  const SupabaseConfig._();

  static const String url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True only when both values are supplied at build time.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
