// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Worker Model
// Represents a registered worker with personal info, employment details,
// bank info, and document verification status.
// ──────────────────────────────────────────────────────────────────────────────

enum DocumentStatus { uploaded, missing, pending }

class WorkerDocument {
  final String name;
  DocumentStatus status;
  String? fileName;
  DateTime? uploadedAt;

  WorkerDocument({
    required this.name,
    this.status = DocumentStatus.missing,
    this.fileName,
    this.uploadedAt,
  });

  WorkerDocument copyWith({
    DocumentStatus? status,
    String? fileName,
    DateTime? uploadedAt,
  }) {
    return WorkerDocument(
      name: name,
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

class BankInfo {
  final String bankName;
  final String accountNumber;
  final String branchName;

  const BankInfo({
    required this.bankName,
    required this.accountNumber,
    required this.branchName,
  });
}

class Worker {
  final String id;
  final String fullName;
  final String nisNumber;
  final DateTime dateOfBirth;
  final String position;
  final String idNumber;
  final String corporationId;
  final String corporationName;
  final String electoralDistrict;
  final double wageRate;
  final double colaRate;
  final double allowanceRate;
  final BankInfo bankInfo;
  final Map<String, WorkerDocument> documents;
  final DateTime dateRegistered;
  bool isActive;

  // Extended fields for full worker profile
  final String? contact;        // Phone number
  final String? address;        // Home address
  final String? birNumber;      // Board of Inland Revenue number
  final DateTime? startDate;    // Employment start date
  final DateTime? endDate;      // Employment end date (if terminated/replaced)
  final String? referenceNumber; // EmployTT reference number

  Worker({
    required this.id,
    required this.fullName,
    required this.nisNumber,
    required this.dateOfBirth,
    required this.position,
    required this.idNumber,
    required this.corporationId,
    required this.corporationName,
    required this.electoralDistrict,
    required this.wageRate,
    required this.colaRate,
    required this.allowanceRate,
    required this.bankInfo,
    required this.documents,
    required this.dateRegistered,
    this.isActive = true,
    this.contact,
    this.address,
    this.birNumber,
    this.startDate,
    this.endDate,
    this.referenceNumber,
  });

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.substring(0, 2).toUpperCase();
  }

  int get documentsUploaded =>
      documents.values.where((d) => d.status == DocumentStatus.uploaded).length;

  int get totalDocuments => documents.length;

  bool get isFullyVerified => documentsUploaded == totalDocuments;

  double get verificationPercent =>
      totalDocuments > 0 ? documentsUploaded / totalDocuments : 0;

  String get verificationLabel {
    if (isFullyVerified) return 'Fully Verified';
    if (documentsUploaded == 0) return 'No Documents';
    return '$documentsUploaded/$totalDocuments Uploaded';
  }

  static const List<String> requiredDocumentNames = [
    'NIS Registration',
    'Birth Certificate',
    'Bank Verification Letter',
    'National ID Card',
    'Police Certificate of Good Character',
  ];
}

// ──────────────────────────────────────────────────────────────────────────────
// Worker Replacement
// Tracks when a worker is replaced due to absence, misconduct, or other reasons.
// Both the original and replacement worker are kept in the registry.
// ──────────────────────────────────────────────────────────────────────────────

class WorkerReplacement {
  final String id;
  final String originalWorkerId;
  final String replacementWorkerId;
  final int daysMissed;
  final String reason;
  final DateTime replacedAt;

  WorkerReplacement({
    required this.id,
    required this.originalWorkerId,
    required this.replacementWorkerId,
    required this.daysMissed,
    required this.reason,
    required this.replacedAt,
  });
}
