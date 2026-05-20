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
//   1. An explicit --dart-define=API_BASE_URL=... always wins (use this to
//      point at a backend on a different host/origin).
//   2. Otherwise, on web, it defaults to the origin the app was served from,
//      so the deployed nginx bundle reaches the API through its same-origin
//      /api proxy with no rebuild and no CORS preflight.
//   3. On non-web with nothing configured it stays empty: every call returns
//      an empty/null result so the frontend renders empty lists instead of
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
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceAll(RegExp(r'/+$'), '');
    }
    // No explicit URL: on web, talk to our own origin. nginx forwards
    // /api/* to the backend, so the app works without a per-deploy rebuild.
    if (kIsWeb) return Uri.base.origin;
    return '';
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
