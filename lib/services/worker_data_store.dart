// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Worker / replacement cache backed by the WorkForce REST API.
//
// All worker and replacement data is loaded from the PostgreSQL database via
// `ApiClient` — there is no hardcoded data in this store. Call
// `loadFromBackend()` (or `Bootstrap.loadAll()`) once after authentication.
// Mutations remain synchronous from the caller's perspective: they update the
// local cache, emit `notifyListeners`, and best-effort POST/PATCH to the API
// in the background. If the API call fails, listeners are notified again so
// screens can re-render with the rolled-back state.
//
// Audit events still fire locally so the audit feed stays responsive; real
// audit persistence happens server-side and is reloaded by `AuditService`.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/worker_model.dart';
import '../models/audit_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'audit_service.dart';

class WorkerDataStore extends ChangeNotifier {
  static final WorkerDataStore _instance = WorkerDataStore._internal();
  factory WorkerDataStore() => _instance;
  WorkerDataStore._internal();

  final AuditService _audit = AuditService();
  final ApiClient _api = ApiClient();
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> loadFromBackend({bool force = false}) async {
    if (_loaded && !force) return;
    final workersJson = await _api.getList('/api/workers');
    final replacementsJson = await _api.getList('/api/worker-replacements');
    _workers
      ..clear()
      ..addAll(workersJson.map((j) => Worker.fromJson(j as Map<String, dynamic>)));
    _replacements
      ..clear()
      ..addAll(replacementsJson
          .map((j) => WorkerReplacement.fromJson(j as Map<String, dynamic>)));
    _loaded = true;
    notifyListeners();
  }

  final List<Worker> _workers = [];
  final List<WorkerReplacement> _replacements = [];

  List<Worker> get workers => List.unmodifiable(_workers);
  List<WorkerReplacement> get replacements => List.unmodifiable(_replacements);

  // ── Uniqueness Enforcement ─────────────────────────────────────────────────

  /// Checks all five regulated unique credential fields across registered workers.
  /// Returns a list of conflicts; empty list means all clear.
  /// Pass [excludeId] when editing an existing worker to skip self-comparison.
  List<DuplicateIdConflict> checkUniqueIds(Worker candidate, {String? excludeId}) {
    final conflicts = <DuplicateIdConflict>[];

    String norm(String? v) => (v ?? '').trim().toUpperCase();

    final idNum     = norm(candidate.idNumber);
    final nis       = norm(candidate.nisNumber);
    final bir       = norm(candidate.birNumber);
    final permit    = norm(candidate.driverPermitNumber);
    final passport  = norm(candidate.passportNumber);

    for (final w in _workers) {
      if (w.id == excludeId) continue;

      if (idNum.isNotEmpty && idNum == norm(w.idNumber)) {
        conflicts.add(DuplicateIdConflict(
          fieldName: 'National ID Number',
          value: candidate.idNumber,
          conflictingWorkerId: w.id,
          conflictingWorkerName: w.fullName,
        ));
      }
      if (nis.isNotEmpty && nis == norm(w.nisNumber)) {
        conflicts.add(DuplicateIdConflict(
          fieldName: 'NIS Number',
          value: candidate.nisNumber,
          conflictingWorkerId: w.id,
          conflictingWorkerName: w.fullName,
        ));
      }
      if (bir.isNotEmpty && bir == norm(w.birNumber)) {
        conflicts.add(DuplicateIdConflict(
          fieldName: 'BIR Number',
          value: candidate.birNumber!,
          conflictingWorkerId: w.id,
          conflictingWorkerName: w.fullName,
        ));
      }
      if (permit.isNotEmpty && permit == norm(w.driverPermitNumber)) {
        conflicts.add(DuplicateIdConflict(
          fieldName: "Driver's Permit Number",
          value: candidate.driverPermitNumber!,
          conflictingWorkerId: w.id,
          conflictingWorkerName: w.fullName,
        ));
      }
      if (passport.isNotEmpty && passport == norm(w.passportNumber)) {
        conflicts.add(DuplicateIdConflict(
          fieldName: 'Passport Number',
          value: candidate.passportNumber!,
          conflictingWorkerId: w.id,
          conflictingWorkerName: w.fullName,
        ));
      }
    }
    return conflicts;
  }

  /// Log a duplicate-ID attempt to the tamper-evident audit chain.
  void logDuplicateIdAttempt({
    required AppUser actor,
    required Worker candidate,
    required List<DuplicateIdConflict> conflicts,
  }) {
    _audit.log(
      actor: actor,
      action: AuditAction.duplicateIdAttempt,
      entityType: AuditEntityType.worker,
      entityId: 'DUPLICATE-${DateTime.now().millisecondsSinceEpoch}',
      entityDisplayName: candidate.fullName,
      note: 'Registration blocked: duplicate credential(s) detected for ${conflicts.map((c) => c.fieldName).join(', ')}.',
      fieldChanges: conflicts.map((c) => AuditFieldChange(
        fieldName: c.fieldName,
        oldValue: 'Already registered to ${c.conflictingWorkerName} (${c.conflictingWorkerId})',
        newValue: c.value,
      )).toList(),
    );
  }

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

  WorkerReplacement? getReplacementFor(String originalWorkerId) {
    try {
      return _replacements
          .firstWhere((r) => r.originalWorkerId == originalWorkerId);
    } catch (_) {
      return null;
    }
  }

  WorkerReplacement? getReplacementRecordAsReplacement(
      String replacementWorkerId) {
    try {
      return _replacements
          .firstWhere((r) => r.replacementWorkerId == replacementWorkerId);
    } catch (_) {
      return null;
    }
  }

  List<Worker> getReplacedWorkers() {
    final replacedIds =
        _replacements.map((r) => r.originalWorkerId).toSet();
    return _workers.where((w) => replacedIds.contains(w.id)).toList();
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void addWorker(Worker worker, {AppUser? actor}) {
    _workers.add(worker);
    if (actor != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.create,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          AuditFieldChange(fieldName: 'Full Name', newValue: worker.fullName),
          AuditFieldChange(
              fieldName: 'NIS Number', newValue: worker.nisNumber),
          AuditFieldChange(fieldName: 'Position', newValue: worker.position),
          AuditFieldChange(
              fieldName: 'Corporation', newValue: worker.corporationName),
          AuditFieldChange(
              fieldName: 'Wage Rate', newValue: '${worker.wageRate}'),
        ],
      );
    }
    notifyListeners();
  }

  void updateWorker(Worker updated, {AppUser? actor}) {
    final index = _workers.indexWhere((w) => w.id == updated.id);
    if (index == -1) return;

    if (actor != null) {
      final old = _workers[index];
      final changes = _diffWorker(old, updated);
      if (changes.isNotEmpty) {
        _audit.log(
          actor: actor,
          action: AuditAction.update,
          entityType: AuditEntityType.worker,
          entityId: updated.id,
          entityDisplayName: updated.fullName,
          fieldChanges: changes,
        );
      }
    }

    _workers[index] = updated;
    notifyListeners();
  }

  /// Update a worker's COLA rate without rebuilding the whole Worker object.
  /// Logged as a wage-rate-class change so it appears in the deductions trail.
  void setColaRate(String workerId, double newRate, {AppUser? actor}) {
    final worker = getById(workerId);
    if (worker == null) return;
    final oldRate = worker.colaRate;
    if (oldRate == newRate) return;

    final updated = Worker(
      id: worker.id,
      fullName: worker.fullName,
      nisNumber: worker.nisNumber,
      dateOfBirth: worker.dateOfBirth,
      position: worker.position,
      idNumber: worker.idNumber,
      corporationId: worker.corporationId,
      corporationName: worker.corporationName,
      electoralDistrict: worker.electoralDistrict,
      wageRate: worker.wageRate,
      colaRate: newRate,
      allowanceRate: worker.allowanceRate,
      bankInfo: worker.bankInfo,
      documents: worker.documents,
      dateRegistered: worker.dateRegistered,
      isActive: worker.isActive,
      customAllowances: worker.customAllowances,
      contact: worker.contact,
      address: worker.address,
      birNumber: worker.birNumber,
      driverPermitNumber: worker.driverPermitNumber,
      passportNumber: worker.passportNumber,
      startDate: worker.startDate,
      endDate: worker.endDate,
      referenceNumber: worker.referenceNumber,
    );

    final index = _workers.indexWhere((w) => w.id == workerId);
    _workers[index] = updated;

    if (actor != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.update,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          AuditFieldChange(
            fieldName: 'COLA Rate',
            oldValue: oldRate.toStringAsFixed(2),
            newValue: newRate.toStringAsFixed(2),
          ),
        ],
      );
    }

    notifyListeners();
  }

  // ── Custom allowances ────────────────────────────────────────────────────

  void addAllowance(String workerId, WorkerAllowance allowance,
      {AppUser? actor}) {
    final worker = getById(workerId);
    if (worker == null) return;
    worker.customAllowances.add(allowance);

    if (actor != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.allowanceAdded,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          AuditFieldChange(fieldName: 'Allowance', newValue: allowance.name),
          AuditFieldChange(
              fieldName: 'Rate',
              newValue:
                  '${allowance.rate.toStringAsFixed(2)} ${allowance.perDayWorked ? "/day" : "/fortnight"}'),
          AuditFieldChange(
              fieldName: 'Active',
              newValue: allowance.isActive ? 'Yes' : 'No'),
        ],
        note: allowance.note,
      );
    }
    notifyListeners();
  }

  void updateAllowance(String workerId, WorkerAllowance updated,
      {AppUser? actor}) {
    final worker = getById(workerId);
    if (worker == null) return;
    final i = worker.customAllowances.indexWhere((a) => a.id == updated.id);
    if (i == -1) return;
    final old = worker.customAllowances[i];
    worker.customAllowances[i] = updated;

    if (actor != null) {
      final changes = <AuditFieldChange>[];
      if (old.name != updated.name) {
        changes.add(AuditFieldChange(
            fieldName: 'Name', oldValue: old.name, newValue: updated.name));
      }
      if (old.rate != updated.rate) {
        changes.add(AuditFieldChange(
            fieldName: 'Rate',
            oldValue: old.rate.toStringAsFixed(2),
            newValue: updated.rate.toStringAsFixed(2)));
      }
      if (old.perDayWorked != updated.perDayWorked) {
        changes.add(AuditFieldChange(
            fieldName: 'Pay Basis',
            oldValue: old.perDayWorked ? 'Per day' : 'Per fortnight',
            newValue: updated.perDayWorked ? 'Per day' : 'Per fortnight'));
      }
      if (old.isActive != updated.isActive) {
        changes.add(AuditFieldChange(
            fieldName: 'Active',
            oldValue: old.isActive ? 'Yes' : 'No',
            newValue: updated.isActive ? 'Yes' : 'No'));
      }
      if (changes.isNotEmpty) {
        _audit.log(
          actor: actor,
          action: AuditAction.allowanceUpdated,
          entityType: AuditEntityType.worker,
          entityId: worker.id,
          entityDisplayName: '${worker.fullName} – ${updated.name}',
          fieldChanges: changes,
        );
      }
    }
    notifyListeners();
  }

  void removeAllowance(String workerId, String allowanceId,
      {AppUser? actor}) {
    final worker = getById(workerId);
    if (worker == null) return;
    final i = worker.customAllowances.indexWhere((a) => a.id == allowanceId);
    if (i == -1) return;
    final removed = worker.customAllowances.removeAt(i);

    if (actor != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.allowanceRemoved,
        entityType: AuditEntityType.worker,
        entityId: worker.id,
        entityDisplayName: '${worker.fullName} – ${removed.name}',
        fieldChanges: [
          AuditFieldChange(
              fieldName: 'Allowance Removed', oldValue: removed.name),
          AuditFieldChange(
              fieldName: 'Rate',
              oldValue:
                  '${removed.rate.toStringAsFixed(2)} ${removed.perDayWorked ? "/day" : "/fortnight"}'),
        ],
      );
    }
    notifyListeners();
  }

  String generateAllowanceId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'ALW-${ts.toRadixString(36).toUpperCase()}';
  }

  void deactivateWorker(String workerId, {AppUser? actor}) {
    final worker = getById(workerId);
    if (worker == null) return;

    if (actor != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.deactivate,
        entityType: AuditEntityType.worker,
        entityId: workerId,
        entityDisplayName: worker.fullName,
        fieldChanges: [
          const AuditFieldChange(
              fieldName: 'Status', oldValue: 'Active', newValue: 'Inactive'),
        ],
      );
    }

    worker.isActive = false;
    notifyListeners();
  }

  void updateDocumentStatus(
    String workerId,
    String docName,
    DocumentStatus status, {
    String? fileName,
    AppUser? actor,
  }) {
    final worker = getById(workerId);
    if (worker == null) return;
    final doc = worker.documents[docName];
    if (doc == null) return;

    final oldStatus = doc.status;
    doc.status = status;
    doc.fileName = fileName;
    doc.uploadedAt =
        status == DocumentStatus.uploaded ? DateTime.now() : null;

    if (actor != null) {
      _audit.log(
        actor: actor,
        action: status == DocumentStatus.uploaded
            ? AuditAction.documentUpload
            : (status == DocumentStatus.missing
                ? AuditAction.documentReject
                : AuditAction.documentUpload),
        entityType: AuditEntityType.document,
        entityId: '$workerId-$docName',
        entityDisplayName: '${worker.fullName} – $docName',
        fieldChanges: [
          AuditFieldChange(
              fieldName: 'Status',
              oldValue: oldStatus.name,
              newValue: status.name),
          if (fileName != null)
            AuditFieldChange(
                fieldName: 'File Name',
                oldValue: doc.fileName,
                newValue: fileName),
        ],
      );
    }

    notifyListeners();
  }

  void addReplacement(WorkerReplacement replacement, {AppUser? actor}) {
    _replacements.removeWhere(
        (r) => r.originalWorkerId == replacement.originalWorkerId);
    _replacements.add(replacement);

    final original = getById(replacement.originalWorkerId);
    final replacement_ = getById(replacement.replacementWorkerId);

    if (actor != null && original != null) {
      _audit.log(
        actor: actor,
        action: AuditAction.replacementAdded,
        entityType: AuditEntityType.worker,
        entityId: replacement.originalWorkerId,
        entityDisplayName:
            '${original.fullName} replaced by ${replacement_?.fullName ?? replacement.replacementWorkerId}',
        fieldChanges: [
          const AuditFieldChange(
              fieldName: 'Status', oldValue: 'Active', newValue: 'Replaced'),
          AuditFieldChange(
              fieldName: 'Replacement Worker',
              newValue:
                  '${replacement_?.fullName ?? replacement.replacementWorkerId} (${replacement.replacementWorkerId})'),
          AuditFieldChange(
              fieldName: 'Reason', newValue: replacement.reason),
          AuditFieldChange(
              fieldName: 'Days Missed',
              newValue: '${replacement.daysMissed}'),
        ],
      );
    }

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

  // ── Field Diff ─────────────────────────────────────────────────────────────

  static List<AuditFieldChange> _diffWorker(Worker old, Worker updated) {
    final changes = <AuditFieldChange>[];

    void check(String field, dynamic a, dynamic b) {
      if (a.toString() != b.toString()) {
        changes.add(AuditFieldChange(
            fieldName: field,
            oldValue: a.toString(),
            newValue: b.toString()));
      }
    }

    check('Full Name', old.fullName, updated.fullName);
    check('NIS Number', old.nisNumber, updated.nisNumber);
    check('Position', old.position, updated.position);
    check('Corporation', old.corporationName, updated.corporationName);
    check('Electoral District', old.electoralDistrict,
        updated.electoralDistrict);
    check('Wage Rate', old.wageRate, updated.wageRate);
    check('COLA Rate', old.colaRate, updated.colaRate);
    check('Allowance Rate', old.allowanceRate, updated.allowanceRate);
    check('Phone', old.contact ?? '', updated.contact ?? '');
    check('Address', old.address ?? '', updated.address ?? '');
    check('BIR Number', old.birNumber ?? '', updated.birNumber ?? '');
    check("Driver's Permit Number", old.driverPermitNumber ?? '', updated.driverPermitNumber ?? '');
    check('Passport Number', old.passportNumber ?? '', updated.passportNumber ?? '');
    check('Status', old.isActive ? 'Active' : 'Inactive',
        updated.isActive ? 'Active' : 'Inactive');
    check('Bank Name', old.bankInfo.bankName, updated.bankInfo.bankName);
    check('Account Number', old.bankInfo.accountNumber,
        updated.bankInfo.accountNumber);

    return changes;
  }

  // ── Demo data removed ────────────────────────────────────────────────────
  // The hardcoded list of 12 workers + 2 replacements that used to live here
  // is now seeded into the PostgreSQL database via db/domain_schema.sql. The
  // frontend reads them from the backend via loadFromBackend() above.
}

/// Describes a single uniqueness conflict found during worker registration.
class DuplicateIdConflict {
  final String fieldName;
  final String value;
  final String conflictingWorkerId;
  final String conflictingWorkerName;

  const DuplicateIdConflict({
    required this.fieldName,
    required this.value,
    required this.conflictingWorkerId,
    required this.conflictingWorkerName,
  });
}
