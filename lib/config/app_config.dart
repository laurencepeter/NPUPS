// ──────────────────────────────────────────────────────────────────────────────
// App Configuration
// API_BASE_URL is injected at Flutter build time via --dart-define.
//
// Local dev:
//   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
//
// Docker build (see Dockerfile ARG API_BASE_URL):
//   docker build --build-arg API_BASE_URL=http://YOUR_SERVER_IP:3000 .
// ──────────────────────────────────────────────────────────────────────────────

class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
}
