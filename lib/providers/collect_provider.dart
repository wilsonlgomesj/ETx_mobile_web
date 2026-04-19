import 'package:flutter/foundation.dart';
import '../models.dart';
import '../stabilization/stabilization_config.dart';
import '../stabilization/stabilization_models.dart';
import '../stabilization/stabilization_repository.dart';
import '../stabilization/stabilization_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLLECT PROVIDER
// Dedicated ChangeNotifier for the collection flow.
// Scoped to the lifecycle of a single CollectScreen.
//
// Responsibilities:
//   - Maintain per-parameter stabilization state
//   - Orchestrate add/remove reading operations (async, with DB persistence)
//   - Recalculate stabilization after every mutation
//   - Store technical justifications (exceptions)
//   - Expose the "can save" gate for the UI
//   - Persist the final stabilization summary to DB on save
// ─────────────────────────────────────────────────────────────────────────────

class CollectProvider extends ChangeNotifier {
  final FieldPoint point;
  final String collectionType; // nasc, dren, vert, inst, fq

  // Map<parameterName, ParameterStabilizationState>
  final Map<String, ParameterStabilizationState> _states = {};

  bool _loading = false;
  bool get loading => _loading;

  CollectProvider({required this.point, required this.collectionType}) {
    _initStates();
  }

  // ── READ ACCESSORS ──────────────────────────────────────────────────────────

  ParameterStabilizationState? stateFor(String paramName) =>
      _states[paramName];

  Map<String, ParameterStabilizationState> get stabStates =>
      Map.unmodifiable(_states);

  bool get hasStabilizationParams => _states.isNotEmpty;

  /// True when every required parameter is either stabilized or has an
  /// accepted technical justification.
  bool get allRequiredSatisfied {
    for (final s in _states.values) {
      if (s.rule.required && !s.canSave) return false;
    }
    return true;
  }

  /// List of required parameter names that still need stabilization/exception.
  List<String> get unsatisfiedRequired => _states.entries
      .where((e) => e.value.rule.required && !e.value.canSave)
      .map((e) => e.key)
      .toList();

  // ── INITIALIZATION ──────────────────────────────────────────────────────────

  void _initStates() {
    for (final rule in StabilizationConfig.rulesForType(collectionType)) {
      _states[rule.parameterName] =
          ParameterStabilizationState(rule: rule);
    }
  }

  /// Load previously persisted readings when reopening a point that was
  /// partially collected (e.g., after app restart or navigation).
  Future<void> loadExistingReadings() async {
    if (point.id == null) return;
    _loading = true;
    notifyListeners();

    try {
      final readings = await StabilizationRepository.instance
          .getReadingsForPoint(point.id!);

      // Group by parameterName
      final byParam = <String, List<ParameterReading>>{};
      for (final r in readings) {
        (byParam[r.parameterName] ??= []).add(r);
      }

      for (final entry in byParam.entries) {
        final state = _states[entry.key];
        if (state == null) continue;
        state.readings = entry.value;
        state.lastResult =
            StabilizationService.calculate(state.rule, state.readings);
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── MUTATIONS ───────────────────────────────────────────────────────────────

  /// Add a new reading for [paramName] with numeric [value].
  /// Persists to DB, annotates, recalculates, notifies.
  Future<void> addReading(String paramName, double value) async {
    final state = _states[paramName];
    if (state == null) return;
    if (point.id == null) return; // defensive — should never happen in practice

    final now = DateTime.now();
    final raw = ParameterReading(
      fieldPointId:        point.id!,
      parameterName:       paramName,
      readingOrder:        state.readings.length + 1,
      value:               value,
      unit:                state.rule.unit,
      measuredAt:          now,
      ruleType:            state.rule.criterionType,
      stabilizationLimit:  state.rule.limit,
      createdAt:           now,
    );

    // Persist first so we get the auto-generated id back
    final persisted = await StabilizationRepository.instance.insertReading(raw);

    state.readings.add(persisted);
    _recalculate(state);

    // Adding a reading after an exception clears the exception —
    // user is actively trying to stabilize again.
    state.exception = null;

    notifyListeners();
  }

  /// Remove the last reading for [paramName], deleting it from DB.
  Future<void> removeLastReading(String paramName) async {
    final state = _states[paramName];
    if (state == null || state.readings.isEmpty) return;

    final last = state.readings.last;
    if (last.id != null) {
      await StabilizationRepository.instance.deleteReading(last.id!);
    }
    state.readings.removeLast();

    if (state.readings.isEmpty) {
      state.lastResult = null;
    } else {
      _recalculate(state);
    }

    notifyListeners();
  }

  /// Record a technical justification for saving without achieving stabilization.
  void setException(String paramName, StabilizationException ex) {
    final state = _states[paramName];
    if (state == null) return;
    state.exception = ex;
    notifyListeners();
  }

  /// Remove the justification for [paramName], reverting to the calculated status.
  void clearException(String paramName) {
    final state = _states[paramName];
    if (state == null) return;
    state.exception = null;
    notifyListeners();
  }

  // ── PERSISTENCE ON SAVE ─────────────────────────────────────────────────────

  /// Write the stabilization summary to the field_points row.
  /// Called just before marking a point as done.
  Future<void> saveStabilizationSummary() async {
    if (point.id == null || _states.isEmpty) return;

    final summaryByParam = <String, dynamic>{};
    final finalValues    = <String, double?>{};
    StabilizationException? primaryException;

    for (final entry in _states.entries) {
      final s = entry.value;
      summaryByParam[entry.key] = {
        'status':             s.effectiveStatus.name,
        'readingCount':       s.readings.length,
        'finalValue':         s.lastResult?.finalValue,
        'consecutiveValid':   s.lastResult?.consecutiveValid ?? 0,
        'exception':          s.exception?.toJson(),
        'readings': s.readings.map((r) => {
          'order': r.readingOrder,
          'value': r.value,
          'isWithinLimit': r.isWithinLimit,
          'measuredAt': r.measuredAt.toIso8601String(),
        }).toList(),
      };

      finalValues[entry.key] = s.lastResult?.finalValue;
      primaryException ??= s.exception;
    }

    final hasException = _states.values.any((s) => s.exception != null);
    final overallStatus = allRequiredSatisfied
        ? (hasException ? 'justifiedException' : 'stabilized')
        : 'outOfRange';

    await StabilizationRepository.instance.saveStabilizationSummary(
      fieldPointId:    point.id!,
      overallStatus:   overallStatus,
      summaryByParam:  summaryByParam,
      finalParamValues: finalValues,
      exceptionReason: primaryException?.predefinedReason,
      exceptionNotes:  primaryException?.complementaryNotes,
    );
  }

  // ── REPORT EXPORT HELPERS ───────────────────────────────────────────────────

  /// Returns a JSON-serializable map of stabilization data for PDF/Excel export.
  /// Integration point: pass this to the report generation layer.
  Map<String, dynamic> toReportPayload() {
    return {
      'pointId':          point.id,
      'pointCode':        point.code,
      'collectionType':   collectionType,
      'parameters': Map.fromEntries(_states.entries.map((e) {
        final s = e.value;
        return MapEntry(e.key, {
          'criterion':    StabilizationService.criterionLabel(s.rule),
          'status':       s.effectiveStatus.name,
          'finalValue':   s.lastResult?.finalValue,
          'unit':         s.rule.unit,
          'readings':     s.readings.map((r) => {
            'order':       r.readingOrder,
            'value':       r.value,
            'delta':       r.isWithinLimit,
            'timestamp':   r.measuredAt.toIso8601String(),
          }).toList(),
          'exception':    s.exception?.toJson(),
        });
      })),
    };
  }

  // ── PRIVATE ─────────────────────────────────────────────────────────────────

  void _recalculate(ParameterStabilizationState state) {
    state.lastResult =
        StabilizationService.calculate(state.rule, state.readings);
  }
}
