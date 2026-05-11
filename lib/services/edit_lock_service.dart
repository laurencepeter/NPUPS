// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Edit-conflict prevention via short-lived collaborative locks.
//
// When a user opens a record for editing the client calls `acquire(...)`. If
// another user already holds the lock the call returns the existing holder so
// the UI can show "Anika is currently editing this — try again at 14:32".
//
// A heartbeat timer renews the lock every `_heartbeatInterval`. The lock
// expires `_lockTtl` after the last heartbeat, so a crashed tab releases the
// record automatically.
//
// Backend contract (REST + optional WebSocket):
//
//   POST   /api/edit-locks/acquire           { entity_type, entity_id }
//                                            -> 200 { lock... }  on success
//                                            -> 409 { lock... }  if held by other
//   POST   /api/edit-locks/{lock_id}/heartbeat
//                                            -> 204
//   DELETE /api/edit-locks/{lock_id}         -> 204
//   GET    /api/edit-locks?entity_type=X&entity_id=Y
//                                            -> { lock... } or null
//   DELETE /api/edit-locks/{lock_id}/force   (admin only) -> 204
//
//   WS event: { kind: "lock_acquired"|"lock_released"|"lock_heartbeat", lock }
//
// When ApiClient.isConfigured is false the service still works in-memory
// (single tab demo) so the UI behaviour is identical.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'api_client.dart';

/// One active lock on a specific record.
@immutable
class EditLock {
  final String id;
  final String entityType;
  final String entityId;
  final String holderId;
  final String holderName;
  final String holderRole;
  final DateTime acquiredAt;
  final DateTime expiresAt;

  const EditLock({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.holderId,
    required this.holderName,
    required this.holderRole,
    required this.acquiredAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  EditLock renew(Duration ttl) => EditLock(
        id: id,
        entityType: entityType,
        entityId: entityId,
        holderId: holderId,
        holderName: holderName,
        holderRole: holderRole,
        acquiredAt: acquiredAt,
        expiresAt: DateTime.now().add(ttl),
      );

  factory EditLock.fromJson(Map<String, dynamic> j) => EditLock(
        id: j['id'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        holderId: j['holder_id'] as String,
        holderName: j['holder_name'] as String,
        holderRole: (j['holder_role'] as String?) ?? '',
        acquiredAt: DateTime.parse(j['acquired_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'holder_id': holderId,
        'holder_name': holderName,
        'holder_role': holderRole,
        'acquired_at': acquiredAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };
}

/// Result of an acquire() call.
@immutable
class LockAcquisition {
  final bool granted;
  final EditLock lock;
  const LockAcquisition._(this.granted, this.lock);

  bool get conflict => !granted;
}

class EditLockService extends ChangeNotifier {
  static final EditLockService _instance = EditLockService._internal();
  factory EditLockService() => _instance;
  EditLockService._internal();

  final ApiClient _api = ApiClient();

  static const Duration _lockTtl = Duration(minutes: 2);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // Locks held by *anyone* (this user or another), keyed by "type|id".
  final Map<String, EditLock> _locks = {};

  // Heartbeat timers for locks held by *this* user.
  final Map<String, Timer> _heartbeats = {};

  static String _key(String type, String id) => '$type|$id';

  /// Currently active lock on this record, or null if free.
  EditLock? lockFor(String entityType, String entityId) {
    final k = _key(entityType, entityId);
    final lock = _locks[k];
    if (lock == null) return null;
    if (lock.isExpired) {
      _locks.remove(k);
      return null;
    }
    return lock;
  }

  /// True if the current user holds the lock on this record.
  bool heldByMe(String entityType, String entityId, AppUser user) {
    final l = lockFor(entityType, entityId);
    return l != null && l.holderId == user.id;
  }

  /// Attempt to take or renew the lock on a record.
  ///
  /// - Grants if free, or already held by [user] (renews TTL).
  /// - Otherwise returns the existing lock so the UI can show the holder.
  Future<LockAcquisition> acquire({
    required String entityType,
    required String entityId,
    required AppUser user,
  }) async {
    final k = _key(entityType, entityId);

    if (_api.isConfigured) {
      try {
        final body = await _api.postJson('/api/edit-locks/acquire', {
          'entity_type': entityType,
          'entity_id': entityId,
        });
        if (body is Map<String, dynamic>) {
          final lock = EditLock.fromJson(body);
          _locks[k] = lock;
          final granted = lock.holderId == user.id;
          if (granted) _startHeartbeat(lock);
          notifyListeners();
          return LockAcquisition._(granted, lock);
        }
      } on ApiException catch (e) {
        // 409 → conflict; the response body holds the existing lock.
        if (e.statusCode == 409) {
          try {
            final existing = EditLock.fromJson(
                jsonDecode(e.body) as Map<String, dynamic>);
            _locks[k] = existing;
            notifyListeners();
            return LockAcquisition._(false, existing);
          } catch (_) {
            // fall through to local fallback
          }
        }
      }
    }

    // Local fallback (no backend or transient failure).
    final existing = lockFor(entityType, entityId);
    if (existing != null && existing.holderId != user.id) {
      return LockAcquisition._(false, existing);
    }
    final renewed = (existing ?? _newLocalLock(entityType, entityId, user))
        .renew(_lockTtl);
    _locks[k] = renewed;
    _startHeartbeat(renewed);
    notifyListeners();
    return LockAcquisition._(true, renewed);
  }

  /// Release a lock held by the current user. No-op if not held by them.
  Future<void> release({
    required String entityType,
    required String entityId,
    required AppUser user,
  }) async {
    final k = _key(entityType, entityId);
    final lock = _locks[k];
    if (lock == null) return;
    if (lock.holderId != user.id) return;

    _stopHeartbeat(k);
    _locks.remove(k);

    if (_api.isConfigured) {
      try {
        await _api.delete('/api/edit-locks/${lock.id}');
      } on ApiException {
        // Server will expire the lock on its own.
      }
    }
    notifyListeners();
  }

  /// Admin override — force-clear a lock held by someone else.
  Future<void> forceRelease({
    required String entityType,
    required String entityId,
    required AppUser actingAdmin,
  }) async {
    if (actingAdmin.role != UserRole.systemAdmin) {
      throw StateError('Only System Admin may force-release an edit lock');
    }
    final k = _key(entityType, entityId);
    final lock = _locks[k];
    _stopHeartbeat(k);
    _locks.remove(k);

    if (_api.isConfigured && lock != null) {
      try {
        await _api.delete('/api/edit-locks/${lock.id}/force');
      } on ApiException {
        // No-op; remote will reconcile on next poll.
      }
    }
    notifyListeners();
  }

  /// Apply a lock event pushed by the backend over WebSocket / SSE.
  /// Wire this into the WebSocket consumer when one is added.
  void applyRemoteEvent(Map<String, dynamic> event) {
    final kind = event['kind'] as String?;
    final lockJson = event['lock'];
    if (lockJson is! Map<String, dynamic>) return;
    final lock = EditLock.fromJson(lockJson);
    final k = _key(lock.entityType, lock.entityId);
    switch (kind) {
      case 'lock_acquired':
      case 'lock_heartbeat':
        _locks[k] = lock;
        break;
      case 'lock_released':
        _locks.remove(k);
        break;
    }
    notifyListeners();
  }

  // ── Heartbeats ─────────────────────────────────────────────────────────────

  void _startHeartbeat(EditLock lock) {
    final k = _key(lock.entityType, lock.entityId);
    _heartbeats[k]?.cancel();
    _heartbeats[k] = Timer.periodic(_heartbeatInterval, (_) async {
      final current = _locks[k];
      if (current == null) {
        _stopHeartbeat(k);
        return;
      }
      _locks[k] = current.renew(_lockTtl);
      notifyListeners();
      if (_api.isConfigured) {
        try {
          await _api.postJson('/api/edit-locks/${current.id}/heartbeat', {});
        } on ApiException {
          // Server treats missed heartbeats as expiry.
        }
      }
    });
  }

  void _stopHeartbeat(String k) {
    _heartbeats.remove(k)?.cancel();
  }

  EditLock _newLocalLock(String entityType, String entityId, AppUser user) {
    final now = DateTime.now();
    return EditLock(
      id: 'LOCAL-LOCK-${now.microsecondsSinceEpoch}',
      entityType: entityType,
      entityId: entityId,
      holderId: user.id,
      holderName: user.fullName,
      holderRole: user.role.displayName,
      acquiredAt: now,
      expiresAt: now.add(_lockTtl),
    );
  }
}
