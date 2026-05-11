// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Compact caption that surfaces the most recent audit entry for a record:
//   "Last edited by Anika Ramlogan (DMCR) — 12 min ago"
//
// Rebuilds live as new audit entries arrive via AuditService.notifyListeners.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit_model.dart';
import '../services/audit_service.dart';
import '../theme/app_theme.dart';

class LastEditedBy extends StatelessWidget {
  final String entityId;

  /// When set, only audit entries for these actions count. Useful for hiding
  /// mere view/login events on a worker detail screen.
  final Set<AuditAction>? actionFilter;

  /// Icon-only mode for tight spaces.
  final bool dense;

  const LastEditedBy({
    super.key,
    required this.entityId,
    this.actionFilter,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuditService(),
      builder: (context, _) {
        final entries = AuditService().getForEntity(entityId);
        final relevant = actionFilter == null
            ? entries
            : entries.where((e) => actionFilter!.contains(e.action)).toList();
        if (relevant.isEmpty) return const SizedBox.shrink();

        final latest = relevant.first; // getForEntity returns reverse-chrono
        final age = _humanizeAge(latest.timestamp);
        final exact = DateFormat('d MMM yyyy, HH:mm').format(latest.timestamp);

        final iconStyle = TextStyle(
          fontSize: dense ? 11 : 12,
          color: AppColors.textSecondary,
        );

        return Tooltip(
          message:
              '${latest.action.displayName} by ${latest.userName} (${latest.userRole}) on $exact',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history,
                  size: dense ? 13 : 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  dense
                      ? '${latest.userName} • $age'
                      : 'Last edited by ${latest.userName} (${latest.userRole}) — $age',
                  style: iconStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _humanizeAge(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return DateFormat('d MMM yyyy').format(t);
  }
}
