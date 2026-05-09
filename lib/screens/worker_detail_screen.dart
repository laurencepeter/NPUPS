import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';
import '../services/security_utils.dart';
import '../services/auth_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Shows full profile, bank info, and document verification status.
// Missing documents show an upload prompt.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerDetailScreen extends StatefulWidget {
  final String workerId;
  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  final WorkerDataStore _store = WorkerDataStore();

  void _simulateUpload(Worker worker, String docName) async {
    // Show upload dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _UploadDialog(documentName: docName),
    );

    if (result == true) {
      _store.updateDocumentStatus(
        worker.id,
        docName,
        DocumentStatus.uploaded,
        fileName: '${docName.toLowerCase().replaceAll(' ', '_')}_${worker.id}.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$docName uploaded successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final worker = _store.getById(widget.workerId);
        if (worker == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Worker Not Found')),
            body: const Center(child: Text('Worker not found.')),
          );
        }

        final statusColor = worker.isFullyVerified
            ? AppColors.success
            : worker.documentsUploaded > 0
                ? AppColors.warning
                : AppColors.error;

        return Scaffold(
          backgroundColor: AppColors.surface,
          body: CustomScrollView(
            slivers: [
              // Profile header
              SliverAppBar(
                expandedHeight: 180,
                pinned: true,
                backgroundColor: AppColors.primary,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              child: Text(
                                worker.initials,
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(worker.fullName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(worker.position, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      worker.verificationLabel,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Verification progress
                    _buildProgressCard(worker, statusColor),
                    const SizedBox(height: 16),

                    // Personal info — sensitive fields masked
                    _buildSectionCard('Personal Information', Icons.person, [
                      _infoRow('Full Name', worker.fullName),
                      _infoRow('Date of Birth', DateFormat('d MMMM yyyy').format(worker.dateOfBirth)),
                      _infoRow('NIS Number', SecurityUtils.maskNisNumber(worker.nisNumber)),
                      _infoRow('ID Number', SecurityUtils.maskIdNumber(worker.idNumber)),
                    ]),
                    const SizedBox(height: 12),

                    // Employment info
                    _buildSectionCard('Employment Details', Icons.work, [
                      _infoRow('Position', worker.position),
                      _infoRow('Corporation', worker.corporationName),
                      _infoRow('Electoral District', worker.electoralDistrict),
                      _infoRow('Wage Rate', '\$${worker.wageRate.toStringAsFixed(2)}/day'),
                      _infoRowAction(
                        'COLA Rate',
                        worker.hasCola
                            ? '\$${worker.colaRate.toStringAsFixed(2)}/day'
                            : 'Not set',
                        onEdit: () => _editColaDialog(worker),
                        secondary: !worker.hasCola,
                      ),
                      _infoRow('Allowance Rate', '\$${worker.allowanceRate.toStringAsFixed(2)}/day'),
                      _infoRow('Date Registered', DateFormat('d MMM yyyy').format(worker.dateRegistered)),
                    ]),
                    const SizedBox(height: 12),

                    // Custom allowances
                    _buildAllowancesCard(worker),
                    const SizedBox(height: 12),

                    // Bank info — account number masked
                    _buildSectionCard('Bank Information', Icons.account_balance, [
                      _infoRow('Bank', worker.bankInfo.bankName),
                      _infoRow('Account Number', SecurityUtils.maskBankAccount(worker.bankInfo.accountNumber)),
                      _infoRow('Branch', worker.bankInfo.branchName),
                    ]),
                    const SizedBox(height: 16),

                    // Documents section
                    Text(
                      'Document Status',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${worker.documentsUploaded} of ${worker.totalDocuments} required documents uploaded',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),

                    ...worker.documents.entries.map((entry) =>
                        _buildDocumentCard(worker, entry.key, entry.value)),

                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressCard(Worker worker, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Verification Progress', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                '${(worker.verificationPercent * 100).toInt()}%',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: worker.verificationPercent,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Flexible(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Worker worker, String docName, WorkerDocument doc) {
    final isUploaded = doc.status == DocumentStatus.uploaded;
    final color = isUploaded ? AppColors.success : AppColors.error;
    final icon = isUploaded ? Icons.check_circle : Icons.error_outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(docName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    isUploaded
                        ? 'Uploaded ${doc.uploadedAt != null ? DateFormat('d MMM yyyy').format(doc.uploadedAt!) : ""}'
                        : 'Required — Not yet uploaded',
                    style: TextStyle(fontSize: 12, color: isUploaded ? AppColors.textSecondary : AppColors.error),
                  ),
                ],
              ),
            ),
            if (!isUploaded)
              ElevatedButton.icon(
                onPressed: () => _simulateUpload(worker, docName),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Upload', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              )
            else
              Icon(Icons.verified, size: 22, color: AppColors.success),
          ],
        ),
      ),
    );
  }

  // ── Editable info row + COLA editor ──────────────────────────────────────

  Widget _infoRowAction(String label, String value,
      {required VoidCallback onEdit, bool secondary = false}) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: secondary
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                    fontStyle: secondary ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined,
                    size: 14, color: AppColors.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editColaDialog(Worker worker) async {
    final ctrl = TextEditingController(
        text: worker.colaRate > 0
            ? worker.colaRate.toStringAsFixed(2)
            : '');
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set COLA Rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cost-of-Living Allowance is paid per day worked. Leave empty '
              'or set to 0 to pause it for this worker.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'COLA per day (TT\$)',
                border: OutlineInputBorder(),
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          if (worker.hasCola)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(0.0),
              child: const Text('Pause'),
            ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              Navigator.of(ctx).pop(v ?? 0.0);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    _store.setColaRate(worker.id, result, actor: AuthService().currentUser);
  }

  // ── Custom allowances card ───────────────────────────────────────────────

  Widget _buildAllowancesCard(Worker worker) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.add_card_outlined,
                      size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Custom Allowances',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: () => _openAllowanceEditor(worker, null),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            if (worker.customAllowances.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'No custom allowances yet. Add Travel, Hazard, Acting Pay, '
                  'or any other recurring allowance.',
                  style: TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
              )
            else
              ...worker.customAllowances
                  .map((a) => _buildAllowanceTile(worker, a)),
          ],
        ),
      ),
    );
  }

  Widget _buildAllowanceTile(Worker worker, WorkerAllowance a) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (a.isActive ? AppColors.success : AppColors.textHint)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          a.isActive ? Icons.payments_outlined : Icons.pause_circle_outline,
          size: 16,
          color: a.isActive ? AppColors.success : AppColors.textHint,
        ),
      ),
      title: Text(
        a.name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: a.isActive ? AppColors.textPrimary : AppColors.textHint,
        ),
      ),
      subtitle: Text(
        '\$${a.rate.toStringAsFixed(2)} ${a.perDayWorked ? "per day worked" : "per fortnight"}'
        '${a.note != null && a.note!.isNotEmpty ? " • ${a.note}" : ""}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openAllowanceEditor(worker, a),
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.error),
            onPressed: () => _confirmRemoveAllowance(worker, a),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _openAllowanceEditor(
      Worker worker, WorkerAllowance? existing) async {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final rateCtrl = TextEditingController(
        text: existing != null ? existing.rate.toStringAsFixed(2) : '');
    final noteCtrl =
        TextEditingController(text: existing?.note ?? '');
    bool perDay = existing?.perDayWorked ?? true;
    bool active = existing?.isActive ?? true;

    final result = await showDialog<WorkerAllowance?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(existing == null ? 'Add Allowance' : 'Edit Allowance'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. Travel, Hazard, Acting Pay',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rate (TT\$)',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Paid per day worked',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      perDay
                          ? 'Multiplied by days worked each fortnight'
                          : 'Flat amount each fortnight',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: perDay,
                    onChanged: (v) => setSt(() => perDay = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      'When off the allowance is preserved but paused.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: active,
                    onChanged: (v) => setSt(() => active = v),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final rate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                  if (name.isEmpty || rate <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Please enter a name and positive rate.')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(
                    WorkerAllowance(
                      id: existing?.id ?? _store.generateAllowanceId(),
                      name: name,
                      rate: rate,
                      perDayWorked: perDay,
                      isActive: active,
                      createdAt: existing?.createdAt ?? DateTime.now(),
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    ),
                  );
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    final actor = AuthService().currentUser;
    if (existing == null) {
      _store.addAllowance(worker.id, result, actor: actor);
    } else {
      _store.updateAllowance(worker.id, result, actor: actor);
    }
  }

  Future<void> _confirmRemoveAllowance(
      Worker worker, WorkerAllowance a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Allowance?'),
        content: Text(
            'Remove "${a.name}" from ${worker.fullName}? This is logged in '
            'the audit trail.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _store.removeAllowance(worker.id, a.id,
          actor: AuthService().currentUser);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Upload Dialog — Simulates file selection with in-memory storage
// ──────────────────────────────────────────────────────────────────────────────

class _UploadDialog extends StatefulWidget {
  final String documentName;
  const _UploadDialog({required this.documentName});

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  bool _fileSelected = false;
  bool _uploading = false;
  String _selectedFileName = '';

  final List<String> _simulatedFiles = [
    'document_scan.pdf',
    'photo_copy.jpg',
    'certified_copy.pdf',
    'scanned_document.png',
  ];

  void _selectFile() {
    setState(() {
      _fileSelected = true;
      _selectedFileName = _simulatedFiles[DateTime.now().millisecond % _simulatedFiles.length];
    });
  }

  void _upload() async {
    setState(() => _uploading = true);
    // Simulate upload delay
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.upload_file, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text('Upload ${widget.documentName}', style: const TextStyle(fontSize: 16))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drop zone
          GestureDetector(
            onTap: _fileSelected ? null : _selectFile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _fileSelected ? AppColors.success : AppColors.accent,
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
                color: (_fileSelected ? AppColors.success : AppColors.accent).withValues(alpha: 0.04),
              ),
              child: Column(
                children: [
                  Icon(
                    _fileSelected ? Icons.check_circle : Icons.cloud_upload_outlined,
                    size: 40,
                    color: _fileSelected ? AppColors.success : AppColors.accent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fileSelected ? _selectedFileName : 'Tap to select file',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _fileSelected ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                  if (!_fileSelected) ...[
                    const SizedBox(height: 4),
                    Text('PDF, JPG, PNG (max 5MB)', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ],
                ],
              ),
            ),
          ),
          if (_uploading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('Uploading...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: !_fileSelected || _uploading ? null : _upload,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
