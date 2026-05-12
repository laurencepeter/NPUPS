// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Backend Status Banner
//
// Until this widget existed, an unconfigured / unreachable API_BASE_URL was
// silently swallowed by ApiClient (it returns null/empty on every call), so
// the dashboard rendered as if the database were empty without any clue why.
//
// This banner makes the failure mode visible:
//   - missing API_BASE_URL    → orange "Backend not configured" banner
//   - configured but failing  → red "Backend unreachable" banner
//   - configured + reachable  → no banner
//
// Pings /api/health on first build and every 30s thereafter.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

class BackendStatusBanner extends StatefulWidget {
  const BackendStatusBanner({super.key});

  @override
  State<BackendStatusBanner> createState() => _BackendStatusBannerState();
}

enum _Status { unknown, ok, unconfigured, unreachable }

class _BackendStatusBannerState extends State<BackendStatusBanner> {
  _Status _status = _Status.unknown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final api = ApiClient();
    if (!api.isConfigured) {
      if (mounted) setState(() => _status = _Status.unconfigured);
      return;
    }
    try {
      await api.getJson('/api/health');
      if (mounted) setState(() => _status = _Status.ok);
    } catch (_) {
      if (mounted) setState(() => _status = _Status.unreachable);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _Status.ok || _status == _Status.unknown) {
      return const SizedBox.shrink();
    }

    final isUnconfigured = _status == _Status.unconfigured;
    final color = isUnconfigured ? AppColors.warning : AppColors.error;
    final icon = isUnconfigured ? Icons.cloud_off : Icons.error_outline;
    final title = isUnconfigured
        ? 'Backend not configured'
        : 'Backend unreachable';
    final detail = isUnconfigured
        ? 'API_BASE_URL is empty — the app is showing only what is in '
            'memory. Run with --dart-define=API_BASE_URL=http://localhost:8080 '
            '(or your deployed API host) so changes persist to PostgreSQL.'
        : 'Could not reach ${ApiClient.baseUrl}/api/health. Workers, '
            'timesheets and audit history may be stale or incomplete until '
            'the API is back online.';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Re-check',
            icon: Icon(Icons.refresh, size: 18, color: color),
            onPressed: _check,
          ),
        ],
      ),
    );
  }
}
