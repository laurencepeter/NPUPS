// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// HTTP client for the WorkForce backend.
//
// All hardcoded demo data has been removed from the Flutter frontend; the
// authoritative source is the PostgreSQL database populated by
// db/domain_schema.sql. This client is the only path through which data
// stores fetch and mutate that data.
//
// The base URL is resolved at runtime, not baked in at build time:
//   1. On web the bundle is served by nginx, which proxies /api/* to the
//      backend on the SAME origin (see nginx.conf). The app therefore talks
//      to its own origin. A build-time API_BASE_URL pointing at the SAME host
//      the app was served from is deliberately ignored on web: a stray build
//      arg baking in an internal-only port (e.g. https://host:8080) must not
//      be able to send the browser at a port that is not publicly reachable.
//      The lone exception is local `flutter run` against localhost, whose dev
//      server has no /api proxy, so a localhost API_BASE_URL is honored.
//   2. A web API_BASE_URL on a genuinely different host is still honored, for
//      the rare case of a backend deployed on a separate origin.
//   3. On non-web (mobile/desktop) there is no nginx proxy, so an explicit
//      --dart-define=API_BASE_URL=... is the only way to reach the backend;
//      with nothing configured it stays empty and every call returns an
//      empty/null result so the frontend renders empty lists instead of
//      throwing ("graceful degradation").
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String body;
  final String path;
  ApiException(this.statusCode, this.body, this.path);
  @override
  String toString() => 'ApiException($statusCode on $path): $body';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  /// Explicit build-time override. Empty unless --dart-define is passed.
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Base URL for the backend, e.g. `https://api.workforce.example.com`.
  /// Empty string disables network calls — every request returns null.
  static final String baseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    final configured = _configuredBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    if (kIsWeb) {
      // The web bundle is always served by nginx, which proxies /api/* to the
      // backend on the SAME origin. Same-origin is the correct, rebuild-free
      // default and cannot be broken by a stray build-time API_BASE_URL.
      final origin = Uri.base.origin;
      if (configured.isEmpty) return origin;

      final cfg = Uri.tryParse(configured);
      if (cfg == null || cfg.host.isEmpty) return origin;

      // An API_BASE_URL on the SAME host as the page is never legitimate in a
      // deployed build: it can only be a misconfiguration aimed at an
      // internal-only port — the cause of the
      // "Uri=https://host:8080/api/workers" failure. Ignore it and stay
      // same-origin. The lone exception is local `flutter run` on localhost,
      // whose dev server genuinely has no /api proxy.
      if (cfg.host == Uri.base.host) {
        final isLocalDev = cfg.host == 'localhost' || cfg.host == '127.0.0.1';
        return isLocalDev ? configured : origin;
      }

      // A genuinely different host (a backend on its own origin): honor it.
      return configured;
    }

    // Non-web (mobile/desktop): no nginx proxy, so an explicit API_BASE_URL is
    // the only way to reach the backend.
    return configured;
  }

  /// Optional API token used for the `Authorization: Bearer` header. The
  /// real auth flow can populate this on successful login.
  String? authToken;

  bool get isConfigured => baseUrl.isNotEmpty;

  Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (json) h['Content-Type'] = 'application/json';
    final t = authToken;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  Uri _uri(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$p');
  }

  /// GET that returns decoded JSON, or null when no backend is configured.
  Future<dynamic> getJson(String path) async {
    if (!isConfigured) return null;
    final res = await http.get(_uri(path), headers: _headers(json: false));
    if (res.statusCode == 204 || res.body.isEmpty) return null;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body, path);
    }
    return jsonDecode(res.body);
  }

  /// GET a JSON list (empty list when no backend).
  Future<List<dynamic>> getList(String path) async {
    final result = await getJson(path);
    if (result == null) return const [];
    if (result is List) return result;
    throw ApiException(200, 'expected JSON array, got ${result.runtimeType}', path);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    if (!isConfigured) return null;
    final res = await http.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body, path);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    if (!isConfigured) return null;
    final res = await http.patch(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body, path);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    if (!isConfigured) return null;
    final res = await http.put(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body, path);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  /// Like [putJson] but used for endpoints whose body shape doesn't translate
  /// cleanly to a Dart `toJson` — kept distinct so call-sites read clearly.
  Future<dynamic> putRaw(String path, Map<String, dynamic> body) =>
      putJson(path, body);

  Future<void> delete(String path) async {
    if (!isConfigured) return;
    final res = await http.delete(_uri(path), headers: _headers(json: false));
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body, path);
    }
  }
}
