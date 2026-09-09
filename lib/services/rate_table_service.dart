// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Admin-managed statutory rate tables (PAYE, NIS, Health Surcharge).
//
// Every statutory figure the payroll engine uses is stored here as an
// effective-dated [DeductionRateTable] row, editable by a System Admin at
// runtime — so a Budget change to the NIS rate, the personal allowance, or a
// PAYE band needs a data edit, not a code change and redeploy.
//
// Resolution rule: for a fortnight starting on date D, the engine uses the row
// with the greatest [effectiveFrom] that is on or before D. Older fortnights
// therefore keep the rates that were in force when they were processed, which
// keeps historical payslips reproducible and auditable. When no row applies
// (empty backend, or D precedes every row), the built-in
// [DeductionRateTable.defaults] is used so the app never fails closed.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/payroll_deductions_model.dart';
import 'api_client.dart';

class RateTableService extends ChangeNotifier {
  static final RateTableService _instance = RateTableService._internal();
  factory RateTableService() => _instance;
  RateTableService._internal();

  final ApiClient _api = ApiClient();
  bool _loaded = false;
  bool get isLoaded => _loaded;

  // Sorted ascending by effectiveFrom.
  final List<DeductionRateTable> _tables = [];

  /// All rate tables, most-recent effective date first (for the admin editor).
  List<DeductionRateTable> get tables => _tables.reversed.toList(growable: false);

  Future<void> loadFromBackend({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final json = await _api.getList('/api/rate-tables');
      _tables
        ..clear()
        ..addAll(json.map((e) =>
            DeductionRateTable.fromJson(e as Map<String, dynamic>)));
      _sort();
    } catch (e) {
      // A missing/not-yet-migrated rate-tables endpoint must not take down the
      // whole app at bootstrap — the engine falls back to the built-in TT
      // defaults (see resolve) so payroll still computes.
      _tables.clear();
      debugPrint('RateTableService: rate tables unavailable, using defaults ($e)');
    }
    _loaded = true;
    notifyListeners();
  }

  void _sort() {
    _tables.sort((a, b) {
      final ad = a.effectiveFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.effectiveFrom ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });
  }

  /// Pure resolver — exposed as static so it can be unit-tested without a
  /// backend. Picks the latest table effective on or before [date]; falls back
  /// to [DeductionRateTable.defaults] when none qualifies.
  static DeductionRateTable resolve(
      List<DeductionRateTable> tables, DateTime date) {
    DeductionRateTable? best;
    for (final t in tables) {
      final eff = t.effectiveFrom;
      if (eff == null || !eff.isAfter(date)) {
        if (best == null ||
            (best.effectiveFrom ?? DateTime.fromMillisecondsSinceEpoch(0))
                .isBefore(eff ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          best = t;
        }
      }
    }
    return best ?? DeductionRateTable.defaults;
  }

  /// The statutory rates in force for a fortnight starting on [date].
  DeductionRateTable ratesFor(DateTime date) => resolve(_tables, date);

  // ── Mutations (System Admin) ──────────────────────────────────────────────
  // Optimistic local update, rolled back if the backend rejects the write —
  // the same pattern the other stores use.

  Future<void> upsert(DeductionRateTable table) async {
    final snapshot = List<DeductionRateTable>.from(_tables);
    _tables.removeWhere((t) => t.id == table.id);
    _tables.add(table);
    _sort();
    notifyListeners();
    try {
      await _api.putJson('/api/rate-tables/${table.id}', table.toJson());
    } catch (e) {
      _tables
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final snapshot = List<DeductionRateTable>.from(_tables);
    _tables.removeWhere((t) => t.id == id);
    notifyListeners();
    try {
      await _api.delete('/api/rate-tables/$id');
    } catch (e) {
      _tables
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
      rethrow;
    }
  }
}
