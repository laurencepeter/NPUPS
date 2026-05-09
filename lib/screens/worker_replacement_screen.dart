import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/security_utils.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Shows the original and replacement worker side-by-side (or stacked on small
// screens) with full profile fields: Name, Position, Contact, Address,
// ID number, NIS, BIR, Starting date, End date, Reference number,
// Days missed, and the replacement reason.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerReplacementScreen extends StatelessWidget {
  final String originalWorkerId;

  const WorkerReplacementScreen({super.key, required this.originalWorkerId});

  @override
  Widget build(BuildContext context) {
    final store = WorkerDataStore();
    final original = store.getById(originalWorkerId);
    final replacement = store.getReplacementFor(originalWorkerId);
    final replacementWorker = replacement != null ? store.getById(replacement.replacementWorkerId) : null;

    if (original == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text('Worker Replacement'),
        ),
        body: const Center(child: Text('Worker not found.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Worker Replacement', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            color: AppColors.warning.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    replacement != null
                        ? 'Reason: ${replacement.reason}'
                        : 'No replacement on record for this worker.',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final content = isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _WorkerCard(worker: original, isOriginal: true, daysMissed: replacement?.daysMissed)),
                    const SizedBox(width: 12),
                    Expanded(child: replacementWorker != null
                        ? _WorkerCard(worker: replacementWorker, isOriginal: false)
                        : _NoReplacementCard()),
                  ],
                )
              : Column(
                  children: [
                    _WorkerCard(worker: original, isOriginal: true, daysMissed: replacement?.daysMissed),
                    const SizedBox(height: 12),
                    replacementWorker != null
                        ? _WorkerCard(worker: replacementWorker, isOriginal: false)
                        : _NoReplacementCard(),
                  ],
                );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replacement != null) ...[
                  _ReplacementSummaryBanner(replacement: replacement),
                  const SizedBox(height: 16),
                ],
                content,
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Replacement Summary Banner
// ──────────────────────────────────────────────────────────────────────────────

class _ReplacementSummaryBanner extends StatelessWidget {
  final WorkerReplacement replacement;

  const _ReplacementSummaryBanner({required this.replacement});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replacement Record', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Replacement ID: ${replacement.id}  •  Days missed: ${replacement.daysMissed}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Date: ${DateFormat('d MMM yyyy').format(replacement.replacedAt)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Worker Card
// ──────────────────────────────────────────────────────────────────────────────

class _WorkerCard extends StatelessWidget {
  final Worker worker;
  final bool isOriginal;
  final int? daysMissed;

  const _WorkerCard({required this.worker, required this.isOriginal, this.daysMissed});

  @override
  Widget build(BuildContext context) {
    final headerColor = isOriginal ? AppColors.error : AppColors.success;
    final headerLabel = isOriginal ? 'ORIGINAL WORKER' : 'REPLACEMENT WORKER';
    final headerIcon = isOriginal ? Icons.person_off : Icons.person_add;
    final fmt = DateFormat('d MMM yyyy');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: headerColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header band
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(headerIcon, size: 18, color: headerColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: headerColor, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        worker.fullName,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: worker.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    worker.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: worker.isActive ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info rows
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Position', worker.position),
                _row('Contact', worker.contact ?? '—'),
                _row('Address', worker.address ?? '—'),
                _row('ID Number', SecurityUtils.maskIdNumber(worker.idNumber)),
                _row('NIS Number', SecurityUtils.maskNisNumber(worker.nisNumber)),
                _row('BIR Number', worker.birNumber ?? '—'),
                _row('Starting Date', worker.startDate != null ? fmt.format(worker.startDate!) : '—'),
                _row('End Date', worker.endDate != null ? fmt.format(worker.endDate!) : '—'),
                _row('EmployTT Ref.', worker.referenceNumber ?? '—', isHighlighted: true),
                if (isOriginal && daysMissed != null) ...[
                  const Divider(height: 20),
                  _row('Days Missed', '$daysMissed days', isHighlighted: true, highlightColor: AppColors.error),
                ],
                const Divider(height: 20),
                _row('Corporation', worker.corporationName, wrap: true),
                _row('Electoral District', worker.electoralDistrict),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool isHighlighted = false, Color? highlightColor, bool wrap = false}) {
    final valueColor = isHighlighted ? (highlightColor ?? AppColors.accent) : AppColors.textPrimary;
    final valueFontWeight = isHighlighted ? FontWeight.w700 : FontWeight.w500;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: wrap
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 13, fontWeight: valueFontWeight, color: valueColor)),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 13, fontWeight: valueFontWeight, color: valueColor),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Placeholder shown when no replacement has been assigned yet
// ──────────────────────────────────────────────────────────────────────────────

class _NoReplacementCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'No Replacement Assigned',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            'A replacement worker has not been registered for this position yet.',
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
