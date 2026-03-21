import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/npups_theme.dart';
import '../models/worker_model.dart';
import '../services/worker_data_store.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Worker Detail & Document Status Screen
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
          backgroundColor: NpupsColors.success,
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
            ? NpupsColors.success
            : worker.documentsUploaded > 0
                ? NpupsColors.warning
                : NpupsColors.error;

        return Scaffold(
          backgroundColor: NpupsColors.surface,
          body: CustomScrollView(
            slivers: [
              // Profile header
              SliverAppBar(
                expandedHeight: 180,
                pinned: true,
                backgroundColor: NpupsColors.primary,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(gradient: NpupsColors.primaryGradient),
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

                    // Personal info
                    _buildSectionCard('Personal Information', Icons.person, [
                      _infoRow('Full Name', worker.fullName),
                      _infoRow('Date of Birth', DateFormat('d MMMM yyyy').format(worker.dateOfBirth)),
                      _infoRow('NIS Number', worker.nisNumber),
                      _infoRow('ID Number', worker.idNumber),
                    ]),
                    const SizedBox(height: 12),

                    // Employment info
                    _buildSectionCard('Employment Details', Icons.work, [
                      _infoRow('Position', worker.position),
                      _infoRow('Corporation', worker.corporationName),
                      _infoRow('Electoral District', worker.electoralDistrict),
                      _infoRow('Wage Rate', '\$${worker.wageRate.toStringAsFixed(2)}/day'),
                      _infoRow('COLA Rate', '\$${worker.colaRate.toStringAsFixed(2)}/day'),
                      _infoRow('Allowance Rate', '\$${worker.allowanceRate.toStringAsFixed(2)}/day'),
                      _infoRow('Date Registered', DateFormat('d MMM yyyy').format(worker.dateRegistered)),
                    ]),
                    const SizedBox(height: 12),

                    // Bank info
                    _buildSectionCard('Bank Information', Icons.account_balance, [
                      _infoRow('Bank', worker.bankInfo.bankName),
                      _infoRow('Account Number', worker.bankInfo.accountNumber),
                      _infoRow('Branch', worker.bankInfo.branchName),
                    ]),
                    const SizedBox(height: 16),

                    // Documents section
                    const Text(
                      'Document Status',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NpupsColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${worker.documentsUploaded} of ${worker.totalDocuments} required documents uploaded',
                      style: const TextStyle(fontSize: 13, color: NpupsColors.textSecondary),
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
        color: Colors.white,
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
              backgroundColor: NpupsColors.border,
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
        color: Colors.white,
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
                Icon(icon, size: 18, color: NpupsColors.accent),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: NpupsColors.textPrimary)),
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
          Text(label, style: const TextStyle(fontSize: 13, color: NpupsColors.textSecondary)),
          Flexible(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textPrimary), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Worker worker, String docName, WorkerDocument doc) {
    final isUploaded = doc.status == DocumentStatus.uploaded;
    final color = isUploaded ? NpupsColors.success : NpupsColors.error;
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
                    style: TextStyle(fontSize: 12, color: isUploaded ? NpupsColors.textSecondary : NpupsColors.error),
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
                  backgroundColor: NpupsColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              )
            else
              Icon(Icons.verified, size: 22, color: NpupsColors.success),
          ],
        ),
      ),
    );
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
          const Icon(Icons.upload_file, color: NpupsColors.accent),
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
                  color: _fileSelected ? NpupsColors.success : NpupsColors.accent,
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
                color: (_fileSelected ? NpupsColors.success : NpupsColors.accent).withValues(alpha: 0.04),
              ),
              child: Column(
                children: [
                  Icon(
                    _fileSelected ? Icons.check_circle : Icons.cloud_upload_outlined,
                    size: 40,
                    color: _fileSelected ? NpupsColors.success : NpupsColors.accent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fileSelected ? _selectedFileName : 'Tap to select file',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _fileSelected ? NpupsColors.success : NpupsColors.textSecondary,
                    ),
                  ),
                  if (!_fileSelected) ...[
                    const SizedBox(height: 4),
                    const Text('PDF, JPG, PNG (max 5MB)', style: TextStyle(fontSize: 11, color: NpupsColors.textHint)),
                  ],
                ],
              ),
            ),
          ),
          if (_uploading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Uploading...', style: TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
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
