// ──────────────────────────────────────────────────────────────────────────────
// WorkForce — Supabase data access
//
// Thin, central place for schema-qualified table accessors. NPUPS tables live
// in dedicated `npups_*` schemas (see db/supabase/), so every query must select
// the schema before the table:
//
//   final rows = await Db.workers().select().eq('corporation_id', corpId);
//   await Db.timesheets().insert({...});
//
// Accessors return `dynamic` so call sites can chain the PostgREST builder
// (.select / .insert / .update / .eq / ...) without coupling to a specific
// supabase_flutter type version. Only valid once Supabase is initialized
// (SupabaseConfig.isConfigured); guard at call sites during the migration.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:supabase_flutter/supabase_flutter.dart';

class Db {
  const Db._();

  static SupabaseClient get client => Supabase.instance.client;

  static dynamic table(String schema, String name) =>
      client.schema(schema).from(name);

  // npups_core
  static dynamic corporations() => table('npups_core', 'corporations');
  static dynamic appUsers() => table('npups_core', 'app_users');
  static dynamic userRoles() => table('npups_core', 'user_roles');

  // npups_hr
  static dynamic workers() => table('npups_hr', 'workers');
  static dynamic workerDocuments() => table('npups_hr', 'worker_documents');
  static dynamic workerAllowances() => table('npups_hr', 'worker_allowances');
  static dynamic workerReplacements() =>
      table('npups_hr', 'worker_replacements');

  // npups_time
  static dynamic rosters() => table('npups_time', 'rosters');
  static dynamic rosterDayEntries() =>
      table('npups_time', 'roster_day_entries');
  static dynamic timesheets() => table('npups_time', 'timesheets');
  static dynamic timesheetDailyEntries() =>
      table('npups_time', 'timesheet_daily_entries');
  static dynamic timesheetApprovals() =>
      table('npups_time', 'timesheet_approvals');
  static dynamic leaveRequests() => table('npups_time', 'leave_requests');
  static dynamic leaveBalances() => table('npups_time', 'leave_balances');

  // npups_pay
  static dynamic payslips() => table('npups_pay', 'payslips');
  static dynamic workerDeductions() => table('npups_pay', 'worker_deductions');
  static dynamic backpayRecords() => table('npups_pay', 'backpay_records');
  static dynamic taxCertificates() => table('npups_pay', 'tax_certificates');

  // npups_bank
  static dynamic paymentBatches() => table('npups_bank', 'payment_batches');
  static dynamic paymentInstructions() =>
      table('npups_bank', 'payment_instructions');
  static dynamic bankFiles() => table('npups_bank', 'bank_files');
}
