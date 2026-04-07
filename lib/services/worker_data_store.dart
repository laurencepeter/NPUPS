// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Simulated Data Store
// In-memory store with demo workers across multiple corporations.
// Supports full CRUD for worker registration plus replacement tracking.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/worker_model.dart';

class WorkerDataStore extends ChangeNotifier {
  static final WorkerDataStore _instance = WorkerDataStore._internal();
  factory WorkerDataStore() => _instance;
  WorkerDataStore._internal() {
    _initializeData();
  }

  final List<Worker> _workers = [];
  final List<WorkerReplacement> _replacements = [];

  List<Worker> get workers => List.unmodifiable(_workers);
  List<WorkerReplacement> get replacements => List.unmodifiable(_replacements);

  // ── Queries ────────────────────────────────────────────────────────────────

  Worker? getById(String id) {
    try {
      return _workers.firstWhere((w) => w.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Worker> getByCorpId(String corpId) =>
      _workers.where((w) => w.corporationId == corpId).toList();

  List<Worker> getActiveWorkers() =>
      _workers.where((w) => w.isActive).toList();

  List<Worker> getActiveByCorpId(String corpId) =>
      _workers.where((w) => w.corporationId == corpId && w.isActive).toList();

  /// Returns the replacement record for an original worker, if any.
  WorkerReplacement? getReplacementFor(String originalWorkerId) {
    try {
      return _replacements.firstWhere((r) => r.originalWorkerId == originalWorkerId);
    } catch (_) {
      return null;
    }
  }

  /// Returns the replacement record where this worker is the replacement, if any.
  WorkerReplacement? getReplacementRecordAsReplacement(String replacementWorkerId) {
    try {
      return _replacements.firstWhere((r) => r.replacementWorkerId == replacementWorkerId);
    } catch (_) {
      return null;
    }
  }

  /// Returns all workers that have been replaced.
  List<Worker> getReplacedWorkers() {
    final replacedIds = _replacements.map((r) => r.originalWorkerId).toSet();
    return _workers.where((w) => replacedIds.contains(w.id)).toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void addWorker(Worker worker) {
    _workers.add(worker);
    notifyListeners();
  }

  void updateWorker(Worker updated) {
    final index = _workers.indexWhere((w) => w.id == updated.id);
    if (index == -1) return;
    _workers[index] = updated;
    notifyListeners();
  }

  void deactivateWorker(String workerId) {
    final worker = getById(workerId);
    if (worker == null) return;
    worker.isActive = false;
    notifyListeners();
  }

  void updateDocumentStatus(String workerId, String docName, DocumentStatus status, {String? fileName}) {
    final worker = getById(workerId);
    if (worker == null) return;
    final doc = worker.documents[docName];
    if (doc == null) return;
    doc.status = status;
    doc.fileName = fileName;
    doc.uploadedAt = status == DocumentStatus.uploaded ? DateTime.now() : null;
    notifyListeners();
  }

  void addReplacement(WorkerReplacement replacement) {
    // Remove any existing replacement record for this original worker
    _replacements.removeWhere((r) => r.originalWorkerId == replacement.originalWorkerId);
    _replacements.add(replacement);
    // Deactivate the original worker
    deactivateWorker(replacement.originalWorkerId);
    notifyListeners();
  }

  String generateWorkerId() {
    final existing = _workers.map((w) => w.id).toList();
    int num = _workers.length + 1;
    String candidate = 'WRK-${num.toString().padLeft(3, '0')}';
    while (existing.contains(candidate)) {
      num++;
      candidate = 'WRK-${num.toString().padLeft(3, '0')}';
    }
    return candidate;
  }

  String generateReplacementId() {
    return 'REP-${(_replacements.length + 1).toString().padLeft(3, '0')}';
  }

  // ── Demo Data ──────────────────────────────────────────────────────────────

  void _initializeData() {
    _workers.addAll([
      // ── Fully Verified Workers ─────────────────────────────────────────────
      Worker(
        id: 'WRK-001',
        fullName: 'Kevin Rampersad',
        nisNumber: 'NIS-2024-00147',
        dateOfBirth: DateTime(1988, 3, 15),
        position: 'General Worker',
        idNumber: 'ID-TT-198803150',
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain South',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Republic Bank', accountNumber: '1102-4587-6321', branchName: 'Independence Square'),
        dateRegistered: DateTime(2024, 1, 10),
        documents: _allUploaded(),
        contact: '868-555-0101',
        address: '14 Cipero Street, Port of Spain',
        birNumber: 'BIR-2024-00147',
        startDate: DateTime(2024, 1, 15),
        referenceNumber: 'ETT-2024-00147',
      ),
      Worker(
        id: 'WRK-002',
        fullName: 'Sasha Mohammed',
        nisNumber: 'NIS-2024-00203',
        dateOfBirth: DateTime(1992, 7, 22),
        position: 'Drain Cleaner',
        idNumber: 'ID-TT-199207221',
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain East',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'First Citizens Bank', accountNumber: '2203-8765-1234', branchName: 'Park Street'),
        dateRegistered: DateTime(2024, 2, 5),
        documents: _allUploaded(),
        contact: '868-555-0202',
        address: '7 Belmont Circular Road, Belmont',
        birNumber: 'BIR-2024-00203',
        startDate: DateTime(2024, 2, 10),
        referenceNumber: 'ETT-2024-00203',
      ),
      Worker(
        id: 'WRK-003',
        fullName: 'Andre Williams',
        nisNumber: 'NIS-2023-01982',
        dateOfBirth: DateTime(1985, 11, 3),
        position: 'Road Maintenance',
        idNumber: 'ID-TT-198511030',
        corporationId: '2',
        corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas North',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Scotiabank', accountNumber: '3301-2244-5566', branchName: 'Chaguanas Main'),
        dateRegistered: DateTime(2023, 11, 20),
        documents: _allUploaded(),
        contact: '868-555-0303',
        address: '22 Montrose Road, Chaguanas',
        birNumber: 'BIR-2023-01982',
        startDate: DateTime(2023, 12, 1),
        referenceNumber: 'ETT-2023-01982',
      ),
      Worker(
        id: 'WRK-004',
        fullName: 'Lisa Doodnath',
        nisNumber: 'NIS-2024-00489',
        dateOfBirth: DateTime(1990, 5, 18),
        position: 'General Worker',
        idNumber: 'ID-TT-199005181',
        corporationId: '2',
        corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas South',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Republic Bank', accountNumber: '1104-9876-5432', branchName: 'Chaguanas'),
        dateRegistered: DateTime(2024, 3, 1),
        documents: _allUploaded(),
        contact: '868-555-0404',
        address: '5 Endeavour Road, Chaguanas',
        birNumber: 'BIR-2024-00489',
        startDate: DateTime(2024, 3, 10),
        referenceNumber: 'ETT-2024-00489',
      ),

      // ── Partially Verified Workers ─────────────────────────────────────────
      Worker(
        id: 'WRK-005',
        fullName: 'Ravi Doobay',
        nisNumber: 'NIS-2024-00621',
        dateOfBirth: DateTime(1995, 9, 7),
        position: 'Landscaper',
        idNumber: 'ID-TT-199509071',
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain West',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'JMMB Bank', accountNumber: '5501-3322-1144', branchName: 'Ariapita Avenue'),
        dateRegistered: DateTime(2024, 4, 12),
        documents: _partialDocs(['NIS Registration', 'National ID Card']),
        contact: '868-555-0505',
        address: '31 Ariapita Avenue, Woodbrook',
        birNumber: 'BIR-2024-00621',
        startDate: DateTime(2024, 4, 20),
        referenceNumber: 'ETT-2024-00621',
      ),
      Worker(
        id: 'WRK-006',
        fullName: 'Marcia Boodoo',
        nisNumber: 'NIS-2024-00788',
        dateOfBirth: DateTime(1987, 1, 25),
        position: 'Street Cleaner',
        idNumber: 'ID-TT-198701251',
        corporationId: '3',
        corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando East',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'First Citizens Bank', accountNumber: '2205-6677-8899', branchName: 'High Street'),
        dateRegistered: DateTime(2024, 5, 8),
        documents: _partialDocs(['NIS Registration', 'Birth Certificate', 'National ID Card']),
        contact: '868-555-0606',
        address: '9 Coffee Street, San Fernando',
        birNumber: 'BIR-2024-00788',
        startDate: DateTime(2024, 5, 15),
        referenceNumber: 'ETT-2024-00788',
        isActive: false, // Replaced by WRK-011
        endDate: DateTime(2025, 1, 15),
      ),
      Worker(
        id: 'WRK-007',
        fullName: 'Jason Baptiste',
        nisNumber: 'NIS-2024-00912',
        dateOfBirth: DateTime(1993, 4, 14),
        position: 'General Worker',
        idNumber: 'ID-TT-199304141',
        corporationId: '3',
        corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando West',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Republic Bank', accountNumber: '1106-1122-3344', branchName: 'San Fernando'),
        dateRegistered: DateTime(2024, 6, 1),
        documents: _partialDocs(['Birth Certificate']),
        contact: '868-555-0707',
        address: '17 Pointe-a-Pierre Road, San Fernando',
        birNumber: 'BIR-2024-00912',
        startDate: DateTime(2024, 6, 10),
        referenceNumber: 'ETT-2024-00912',
      ),

      // ── No Documents Submitted ─────────────────────────────────────────────
      Worker(
        id: 'WRK-008',
        fullName: 'Terrence Charles',
        nisNumber: 'NIS-2024-01055',
        dateOfBirth: DateTime(1998, 12, 30),
        position: 'Drain Cleaner',
        idNumber: 'ID-TT-199812301',
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain North',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Scotiabank', accountNumber: '3303-5544-6677', branchName: 'Frederick Street'),
        dateRegistered: DateTime(2024, 7, 15),
        documents: _noDocs(),
        contact: '868-555-0808',
        address: '3 Observatory Street, Port of Spain',
        startDate: DateTime(2024, 7, 22),
        referenceNumber: 'ETT-2024-01055',
        isActive: false, // Replaced by WRK-012
        endDate: DateTime(2025, 2, 1),
      ),
      Worker(
        id: 'WRK-009',
        fullName: 'Camille Hospedales',
        nisNumber: 'NIS-2024-01198',
        dateOfBirth: DateTime(1991, 8, 19),
        position: 'Road Maintenance',
        idNumber: 'ID-TT-199108191',
        corporationId: '2',
        corporationName: 'Chaguanas Borough Corporation',
        electoralDistrict: 'Chaguanas East',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'JMMB Bank', accountNumber: '5502-7788-9900', branchName: 'Endeavour Road'),
        dateRegistered: DateTime(2024, 8, 3),
        documents: _noDocs(),
        contact: '868-555-0909',
        address: '42 Caroni Arena Road, Chaguanas',
        startDate: DateTime(2024, 8, 12),
        referenceNumber: 'ETT-2024-01198',
      ),
      Worker(
        id: 'WRK-010',
        fullName: 'Denise La Fortune',
        nisNumber: 'NIS-2024-01342',
        dateOfBirth: DateTime(1989, 6, 11),
        position: 'Landscaper',
        idNumber: 'ID-TT-198906111',
        corporationId: '3',
        corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando East',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Republic Bank', accountNumber: '1108-2233-4455', branchName: 'Coffee Street'),
        dateRegistered: DateTime(2024, 9, 10),
        documents: _noDocs(),
        contact: '868-555-1010',
        address: '88 Navet Road, San Fernando',
        startDate: DateTime(2024, 9, 20),
        referenceNumber: 'ETT-2024-01342',
      ),

      // ── Replacement Workers ────────────────────────────────────────────────
      Worker(
        id: 'WRK-011',
        fullName: 'Patricia Hernandez',
        nisNumber: 'NIS-2025-00105',
        dateOfBirth: DateTime(1994, 3, 8),
        position: 'Street Cleaner',
        idNumber: 'ID-TT-199403081',
        corporationId: '3',
        corporationName: 'San Fernando City Corporation',
        electoralDistrict: 'San Fernando East',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Republic Bank', accountNumber: '1109-3344-5566', branchName: 'Coffee Street'),
        dateRegistered: DateTime(2025, 1, 20),
        documents: _allUploaded(),
        contact: '868-555-1101',
        address: '12 Harris Promenade, San Fernando',
        birNumber: 'BIR-2025-00105',
        startDate: DateTime(2025, 1, 20),
        referenceNumber: 'ETT-2025-00105',
      ),
      Worker(
        id: 'WRK-012',
        fullName: 'Marcus Phillip',
        nisNumber: 'NIS-2025-00218',
        dateOfBirth: DateTime(1997, 7, 14),
        position: 'Drain Cleaner',
        idNumber: 'ID-TT-199707141',
        corporationId: '8',
        corporationName: 'Port of Spain City Corporation',
        electoralDistrict: 'Port of Spain North',
        wageRate: 150.0,
        colaRate: 25.0,
        allowanceRate: 40.0,
        bankInfo: const BankInfo(bankName: 'Scotiabank', accountNumber: '3306-7788-9900', branchName: 'Frederick Street'),
        dateRegistered: DateTime(2025, 2, 5),
        documents: _partialDocs(['NIS Registration', 'National ID Card', 'Birth Certificate']),
        contact: '868-555-1202',
        address: '56 Laventille Road, Laventille',
        birNumber: 'BIR-2025-00218',
        startDate: DateTime(2025, 2, 5),
        referenceNumber: 'ETT-2025-00218',
      ),
    ]);

    // ── Demo Replacement Records ───────────────────────────────────────────────
    _replacements.addAll([
      WorkerReplacement(
        id: 'REP-001',
        originalWorkerId: 'WRK-006',
        replacementWorkerId: 'WRK-011',
        daysMissed: 18,
        reason: 'Repeated absenteeism and conduct issues',
        replacedAt: DateTime(2025, 1, 20),
      ),
      WorkerReplacement(
        id: 'REP-002',
        originalWorkerId: 'WRK-008',
        replacementWorkerId: 'WRK-012',
        daysMissed: 12,
        reason: 'Unauthorised absence from duty post',
        replacedAt: DateTime(2025, 2, 5),
      ),
    ]);
  }

  static Map<String, WorkerDocument> _allUploaded() {
    return {
      for (final name in Worker.requiredDocumentNames)
        name: WorkerDocument(
          name: name,
          status: DocumentStatus.uploaded,
          fileName: '${name.toLowerCase().replaceAll(' ', '_')}.pdf',
          uploadedAt: DateTime(2024, 2, 1),
        ),
    };
  }

  static Map<String, WorkerDocument> _partialDocs(List<String> uploadedNames) {
    return {
      for (final name in Worker.requiredDocumentNames)
        name: WorkerDocument(
          name: name,
          status: uploadedNames.contains(name) ? DocumentStatus.uploaded : DocumentStatus.missing,
          fileName: uploadedNames.contains(name) ? '${name.toLowerCase().replaceAll(' ', '_')}.pdf' : null,
          uploadedAt: uploadedNames.contains(name) ? DateTime(2024, 3, 15) : null,
        ),
    };
  }

  static Map<String, WorkerDocument> _noDocs() {
    return {
      for (final name in Worker.requiredDocumentNames)
        name: WorkerDocument(name: name),
    };
  }
}
