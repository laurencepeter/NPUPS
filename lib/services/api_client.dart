// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// HTTP client for the WorkForce backend.
//
// All hardcoded demo data has been removed from the Flutter frontend; the
// authoritative source is the PostgreSQL database populated by
// db/domain_schema.sql. This client is the only path through which data
// stores fetch and mutate that data.
//
// The base URL is supplied at build time:
//   flutter build web --dart-define=API_BASE_URL=https://api.example.com
//   flutter run        --dart-define=API_BASE_URL=http://localhost:8080
//
// When a backend has not yet been stood up, leave API_BASE_URL unset; in that
// case every call returns an empty/null result so the frontend renders empty
// lists instead of throwing. This is the "graceful degradation" mode used for
// the initial deploy where the database has been seeded but the API service
// is not wired up yet.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
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

  /// Base URL for the backend, e.g. `https://api.workforce.example.com`.
  /// Empty string disables network calls — every request returns null.
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

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
