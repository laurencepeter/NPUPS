// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Banner displayed at the top of an editable record when another user holds
// the EditLockService lock for that record. Rebuilds live whenever the lock
// state changes (heartbeat refresh, lock release, force-release, etc.).
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../services/edit_lock_service.dart';
import '../theme/app_theme.dart';

class EditLockBanner extends StatelessWidget {
  final String entityType;
  final String entityId;
  final AppUser viewer;

  /// Called when a System Admin chooses "Force release" on a foreign lock.
  /// Receives the lock that was held by another user so the caller can write
  /// an audit-log entry describing the override.
  final void Function(EditLock overriddenLock)? onForceReleased;

  const EditLockBanner({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.viewer,
    this.onForceReleased,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EditLockService(),
      builder: (context, _) {
        final lock = EditLockService().lockFor(entityType, entityId);
        if (lock == null) return const SizedBox.shrink();
        if (lock.holderId == viewer.id) return const SizedBox.shrink();

        final isAdmin = viewer.role == UserRole.systemAdmin;
        final expires = DateFormat('HH:mm').format(lock.expiresAt);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lock.holderName} is currently editing this record',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lock.holderRole} • lock expires at $expires (auto-renews while their session is active)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.lock_open, size: 16),
                  label: const Text('Force release'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: () => _confirmForceRelease(context, lock),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmForceRelease(BuildContext context, EditLock lock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force release edit lock?'),
        content: Text(
          'This will discard ${lock.holderName}\'s in-progress changes. '
          'They will be notified that the lock was overridden. The override '
          'is recorded in the audit log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Force release'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await EditLockService().forceRelease(
      entityType: entityType,
      entityId: entityId,
      actingAdmin: viewer,
    );
    onForceReleased?.call(lock);
  }
}
