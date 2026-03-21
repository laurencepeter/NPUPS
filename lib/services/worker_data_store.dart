// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Simulated Data Store
// In-memory store with 10 dummy workers across multiple corporations.
// Mix of states: fully verified, partially complete, nothing submitted.
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
  List<Worker> get workers => List.unmodifiable(_workers);

  Worker? getById(String id) {
    try {
      return _workers.firstWhere((w) => w.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Worker> getByCorpId(String corpId) =>
      _workers.where((w) => w.corporationId == corpId).toList();

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
