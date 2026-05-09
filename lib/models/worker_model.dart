// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
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

  factory WorkerDocument.fromJson(Map<String, dynamic> j) => WorkerDocument(
        name: j['name'] as String,
        status: DocumentStatus.values.byName(j['status'] as String? ?? 'missing'),
        fileName: j['file_name'] as String?,
        uploadedAt: j['uploaded_at'] != null
            ? DateTime.parse(j['uploaded_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        'file_name': fileName,
        'uploaded_at': uploadedAt?.toIso8601String(),
      };
}

/// User-defined allowance attached to a single worker (e.g. Travel, Hazard,
/// Acting Pay). Either paid per day worked (`perDayWorked = true`) or as a
/// flat amount per fortnight (`perDayWorked = false`).
class WorkerAllowance {
  final String id;
  final String name;
  final double rate;
  final bool perDayWorked;
  final bool isActive;
  final DateTime createdAt;
  final String? note;

  const WorkerAllowance({
    required this.id,
    required this.name,
    required this.rate,
    this.perDayWorked = true,
    this.isActive = true,
    required this.createdAt,
    this.note,
  });

  WorkerAllowance copyWith({
    String? name,
    double? rate,
    bool? perDayWorked,
    bool? isActive,
    String? note,
  }) {
    return WorkerAllowance(
      id: id,
      name: name ?? this.name,
      rate: rate ?? this.rate,
      perDayWorked: perDayWorked ?? this.perDayWorked,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      note: note ?? this.note,
    );
  }

  double amountFor(int daysWorked) {
    if (!isActive) return 0;
    return perDayWorked ? rate * daysWorked : rate;
  }

  factory WorkerAllowance.fromJson(Map<String, dynamic> j) => WorkerAllowance(
        id: j['id'] as String,
        name: j['name'] as String,
        rate: (j['rate'] as num).toDouble(),
        perDayWorked: j['per_day_worked'] as bool? ?? true,
        isActive: j['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(j['created_at'] as String),
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rate': rate,
        'per_day_worked': perDayWorked,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'note': note,
      };
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
  /// Cost-of-Living Allowance rate per day. Optional — defaults to 0 so
  /// workers can be registered without a COLA and have it set later from
  /// the worker detail screen if/when one is introduced.
  final double colaRate;
  final double allowanceRate;
  final BankInfo bankInfo;
  final Map<String, WorkerDocument> documents;
  final DateTime dateRegistered;
  bool isActive;

  /// User-defined allowances (Travel, Hazard, Acting, etc.) attached to this
  /// worker. Mutable — added/removed via WorkerDataStore.
  List<WorkerAllowance> customAllowances;

  // Extended fields for full worker profile
  final String? contact;             // Phone number
  final String? address;             // Home address
  final String? birNumber;           // Board of Inland Revenue number
  final String? driverPermitNumber;  // Driver's permit number
  final String? passportNumber;      // Passport number
  final DateTime? startDate;         // Employment start date
  final DateTime? endDate;           // Employment end date (if terminated/replaced)
  final String? referenceNumber;     // EmployTT reference number

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
    this.colaRate = 0.0,
    required this.allowanceRate,
    required this.bankInfo,
    required this.documents,
    required this.dateRegistered,
    this.isActive = true,
    List<WorkerAllowance>? customAllowances,
    this.contact,
    this.address,
    this.birNumber,
    this.driverPermitNumber,
    this.passportNumber,
    this.startDate,
    this.endDate,
    this.referenceNumber,
  }) : customAllowances = customAllowances ?? [];

  /// Sum of all active custom allowances for the given days-worked count.
  double customAllowanceTotal(int daysWorked) =>
      customAllowances.fold(0.0, (s, a) => s + a.amountFor(daysWorked));

  bool get hasCola => colaRate > 0;
  List<WorkerAllowance> get activeAllowances =>
      customAllowances.where((a) => a.isActive).toList();

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

  factory Worker.fromJson(Map<String, dynamic> j) {
    final docsList = (j['documents'] as List? ?? const [])
        .map((e) => WorkerDocument.fromJson(e as Map<String, dynamic>))
        .toList();
    final docsMap = {for (final d in docsList) d.name: d};
    for (final required in requiredDocumentNames) {
      docsMap.putIfAbsent(required, () => WorkerDocument(name: required));
    }
    return Worker(
      id: j['id'] as String,
      fullName: j['full_name'] as String,
      nisNumber: j['nis_number'] as String,
      dateOfBirth: DateTime.parse(j['date_of_birth'] as String),
      position: j['position'] as String,
      idNumber: j['id_number'] as String,
      corporationId: j['corporation_id'] as String,
      corporationName: j['corporation_name'] as String,
      electoralDistrict: j['electoral_district'] as String,
      wageRate: (j['wage_rate'] as num).toDouble(),
      colaRate: (j['cola_rate'] as num?)?.toDouble() ?? 0.0,
      allowanceRate: (j['allowance_rate'] as num).toDouble(),
      bankInfo: BankInfo(
        bankName: j['bank_name'] as String,
        accountNumber: j['account_number'] as String,
        branchName: j['branch_name'] as String,
      ),
      documents: docsMap,
      dateRegistered: DateTime.parse(j['date_registered'] as String),
      isActive: j['is_active'] as bool? ?? true,
      customAllowances: (j['custom_allowances'] as List? ?? const [])
          .map((e) => WorkerAllowance.fromJson(e as Map<String, dynamic>))
          .toList(),
      contact: j['contact'] as String?,
      address: j['address'] as String?,
      birNumber: j['bir_number'] as String?,
      driverPermitNumber: j['driver_permit_number'] as String?,
      passportNumber: j['passport_number'] as String?,
      startDate: j['start_date'] != null
          ? DateTime.parse(j['start_date'] as String)
          : null,
      endDate: j['end_date'] != null
          ? DateTime.parse(j['end_date'] as String)
          : null,
      referenceNumber: j['reference_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'nis_number': nisNumber,
        'date_of_birth': dateOfBirth.toIso8601String(),
        'position': position,
        'id_number': idNumber,
        'corporation_id': corporationId,
        'corporation_name': corporationName,
        'electoral_district': electoralDistrict,
        'wage_rate': wageRate,
        'cola_rate': colaRate,
        'allowance_rate': allowanceRate,
        'bank_name': bankInfo.bankName,
        'account_number': bankInfo.accountNumber,
        'branch_name': bankInfo.branchName,
        'documents': documents.values.map((d) => d.toJson()).toList(),
        'custom_allowances':
            customAllowances.map((a) => a.toJson()).toList(),
        'date_registered': dateRegistered.toIso8601String(),
        'is_active': isActive,
        'contact': contact,
        'address': address,
        'bir_number': birNumber,
        'driver_permit_number': driverPermitNumber,
        'passport_number': passportNumber,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'reference_number': referenceNumber,
      };
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

  factory WorkerReplacement.fromJson(Map<String, dynamic> j) =>
      WorkerReplacement(
        id: j['id'] as String,
        originalWorkerId: j['original_worker_id'] as String,
        replacementWorkerId: j['replacement_worker_id'] as String,
        daysMissed: j['days_missed'] as int,
        reason: j['reason'] as String,
        replacedAt: DateTime.parse(j['replaced_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'original_worker_id': originalWorkerId,
        'replacement_worker_id': replacementWorkerId,
        'days_missed': daysMissed,
        'reason': reason,
        'replaced_at': replacedAt.toIso8601String(),
      };
}
