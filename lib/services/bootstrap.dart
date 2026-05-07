// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// One-shot loader that pulls every domain dataset from the backend.
//
// Called once after a successful login so the role-specific screens that
// depend on `WorkerDataStore`, `TimesheetDataStore`, etc. find populated
// caches instead of empty lists. Each store is idempotent — calling
// `loadFromBackend()` a second time is a no-op unless `force: true`.
// ──────────────────────────────────────────────────────────────────────────────

import 'audit_service.dart';
import 'backpay_service.dart';
import 'roster_service.dart';
import 'timesheet_data_store.dart';
import 'worker_data_store.dart';

class Bootstrap {
  static Future<void> loadAll({bool force = false}) async {
    // Workers must come first because the roster service rebuilds worker
    // records by querying the worker store.
    await WorkerDataStore().loadFromBackend(force: force);
    await Future.wait([
      TimesheetDataStore().loadFromBackend(force: force),
      AuditService().loadFromBackend(force: force),
      RosterService().loadFromBackend(force: force),
      BackpayService().loadFromBackend(force: force),
    ]);
  }
}
