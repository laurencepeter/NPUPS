// ──────────────────────────────────────────────────────────────────────────────
// NPUPS API Client
// Thin wrapper around the http package for PostgREST calls.
//
// PostgREST conventions used here:
//   GET  /table_name               → list rows
//   GET  /table_name?id=eq.VALUE   → filter by column
//   POST /table_name               → insert a row
//   PATCH /table_name?id=eq.VALUE  → update a row
//   POST /rpc/function_name        → call a stored function
//
// Auth:
//   JWT from login() is stored in SharedPreferences and sent as
//   Authorization: Bearer <token> on every request.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient extends ChangeNotifier {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  static const _tokenKey = 'npups_jwt';

  String? _token;
  String? get token => _token;
  bool get isAuthenticated => _token != null;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    notifyListeners();
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }

  // ── Base URL ──────────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: {...uri.queryParameters, ...queryParams});
    }
    return uri;
  }

  // ── Headers ───────────────────────────────────────────────────────────────

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  // Return a single object instead of a list
  Map<String, String> get _headersOne => {
    ..._headers,
    'Accept': 'application/vnd.pgrst.object+json',
  };

  // Prefer to return the new row after insert/update
  Map<String, String> get _headersReturn => {
    ..._headers,
    'Prefer': 'return=representation',
  };

  // ── HTTP verbs ────────────────────────────────────────────────────────────

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _headers);
    return _handle(response);
  }

  Future<dynamic> getOne(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _headersOne);
    return _handle(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _uri(path),
      headers: _headersReturn,
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body,
      {Map<String, String>? query}) async {
    final response = await http.patch(
      _uri(path, query),
      headers: _headersReturn,
      body: jsonEncode(body),
    );
    return _handle(response);
  }

  Future<void> delete(String path, {Map<String, String>? query}) async {
    final response = await http.delete(_uri(path, query), headers: _headers);
    _handle(response);
  }

  /// Call a PostgREST RPC function (POST /rpc/<name>)
  Future<dynamic> rpc(String functionName, [Map<String, dynamic>? params]) async {
    final response = await http.post(
      _uri('/rpc/$functionName'),
      headers: _headers,
      body: jsonEncode(params ?? {}),
    );
    return _handle(response);
  }

  // ── Response handling ─────────────────────────────────────────────────────

  dynamic _handle(http.Response response) {
    if (response.statusCode == 401) {
      clearToken();
      throw const ApiException(401, 'Session expired. Please log in again.');
    }

    final body = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 400) {
      final msg = body is Map ? (body['message'] ?? body['hint'] ?? 'Request failed') : 'Request failed';
      throw ApiException(response.statusCode, msg.toString());
    }

    return body;
  }
}
