import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ──────────────────────────────────────────────────────────────────────────────
// LockSync WebSocket Client — using web_socket_channel (works web + mobile)
//
// This is the production-ready version. Requires the web_socket_channel package.
// ──────────────────────────────────────────────────────────────────────────────

enum LockSyncState {
  disconnected,
  connecting,
  connected,
  waitingForPair,
  paired,
  reconnecting,
}

class SyncMessage {
  final String from;
  final dynamic payload;
  final int timestamp;
  SyncMessage({required this.from, required this.payload, required this.timestamp});
}

class LockSyncService extends ChangeNotifier {
  final String serverUrl;
  late final String deviceId;

  LockSyncState _state = LockSyncState.disconnected;
  LockSyncState get state => _state;

  String? _pairCode;
  String? get pairCode => _pairCode;

  String? _pairId;
  String? get pairId => _pairId;

  String? _partnerId;
  String? get partnerId => _partnerId;

  bool _partnerOnline = false;
  bool get partnerOnline => _partnerOnline;

  String? _accessToken;
  String? _refreshToken;

  String? _lastError;
  String? get lastError => _lastError;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  final StreamController<SyncMessage> _messageController = StreamController.broadcast();
  Stream<SyncMessage> get messages => _messageController.stream;

  final StreamController<String> _errorController = StreamController.broadcast();
  Stream<String> get errors => _errorController.stream;

  LockSyncService({required this.serverUrl}) {
    deviceId = _generateDeviceId();
  }

  // ─── Public API ──────────────────────────────────────────────────

  Future<void> connect() async {
    if (_state == LockSyncState.connecting || _state == LockSyncState.paired) return;

    _setState(LockSyncState.connecting);
    _lastError = null;

    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        (data) => _onMessage(data as String),
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      _setState(LockSyncState.connected);
      _reconnectAttempts = 0;
      _startPing();
    } catch (e) {
      _lastError = 'Connection failed: $e';
      _setState(LockSyncState.disconnected);
      _errorController.add(_lastError!);
    }
  }

  void requestPairCode() {
    _send({'type': 'request_code', 'deviceId': deviceId});
  }

  void joinPairCode(String code) {
    _send({'type': 'join_code', 'code': code, 'deviceId': deviceId});
  }

  void authenticate() {
    if (_accessToken == null) return;
    _send({'type': 'authenticate', 'token': _accessToken});
  }

  void sendSync(dynamic payload) {
    if (_state != LockSyncState.paired) return;
    _send({'type': 'sync', 'payload': payload});
  }

  void sendMessage(String text) {
    sendSync({'type': 'message', 'text': text});
  }

  void sendKeystroke(String delta, int cursorPosition) {
    sendSync({'type': 'keystroke', 'delta': delta, 'cursor': cursorPosition});
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(LockSyncState.disconnected);
  }

  void unpair() {
    _pairId = null;
    _partnerId = null;
    _accessToken = null;
    _refreshToken = null;
    _partnerOnline = false;
    _pairCode = null;
    disconnect();
  }

  bool get hasTokens => _accessToken != null && _refreshToken != null;

  Map<String, String>? getSavedTokens() {
    if (_accessToken == null || _refreshToken == null) return null;
    return {
      'accessToken': _accessToken!,
      'refreshToken': _refreshToken!,
      'deviceId': deviceId,
    };
  }

  void restoreTokens(String accessToken, String refreshToken) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  // ─── Internals ───────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void _onMessage(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final type = msg['type'] as String?;

    switch (type) {
      case 'code_created':
        _pairCode = msg['code'] as String;
        _setState(LockSyncState.waitingForPair);
        break;

      case 'code_expired':
        _pairCode = null;
        _lastError = 'Pairing code expired';
        _setState(LockSyncState.connected);
        _errorController.add(_lastError!);
        break;

      case 'paired':
        _pairId = msg['pairId'] as String;
        _partnerId = msg['partnerId'] as String;
        _accessToken = msg['accessToken'] as String;
        _refreshToken = msg['refreshToken'] as String;
        _partnerOnline = true;
        _pairCode = null;
        _setState(LockSyncState.paired);
        break;

      case 'authenticated':
        _pairId = msg['pairId'] as String;
        _partnerId = msg['partnerId'] as String;
        _partnerOnline = msg['partnerOnline'] as bool? ?? false;
        _setState(LockSyncState.paired);
        break;

      case 'token_refreshed':
        _accessToken = msg['accessToken'] as String;
        _refreshToken = msg['refreshToken'] as String;
        break;

      case 'sync':
        _messageController.add(SyncMessage(
          from: msg['from'] as String,
          payload: msg['payload'],
          timestamp: msg['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ));
        break;

      case 'partner_online':
        _partnerOnline = true;
        notifyListeners();
        break;

      case 'partner_offline':
        _partnerOnline = false;
        notifyListeners();
        break;

      case 'pong':
        break;

      case 'error':
        _lastError = msg['message'] as String? ?? 'Unknown error';
        _errorController.add(_lastError!);
        final code = msg['code'] as String?;
        if (code == 'PAIR_NOT_FOUND' || code == 'INVALID_TOKEN') {
          if (_refreshToken != null) {
            _send({'type': 'refresh_token', 'refreshToken': _refreshToken});
          } else {
            _setState(LockSyncState.connected);
          }
        }
        break;
    }
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    if (_state == LockSyncState.disconnected) return;
    _setState(LockSyncState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _lastError = 'Max reconnection attempts reached';
      _setState(LockSyncState.disconnected);
      _errorController.add(_lastError!);
      return;
    }

    final delay = Duration(seconds: min(pow(2, _reconnectAttempts).toInt(), 30));
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        final uri = Uri.parse(serverUrl);
        _channel = WebSocketChannel.connect(uri);
        await _channel!.ready;

        _subscription = _channel!.stream.listen(
          (data) => _onMessage(data as String),
          onDone: _onDisconnected,
          onError: (_) => _onDisconnected(),
        );

        _reconnectAttempts = 0;
        _startPing();

        if (_accessToken != null) {
          authenticate();
        } else {
          _setState(LockSyncState.connected);
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'type': 'ping'});
    });
  }

  void _setState(LockSyncState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  String _generateDeviceId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _errorController.close();
    super.dispose();
  }
}
