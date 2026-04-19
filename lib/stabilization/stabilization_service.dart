import 'stabilization_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION SERVICE
// Pure calculation engine — no DB, no UI, no Flutter dependencies.
// All business logic for determining whether a parameter is stabilized lives
// exclusively here.
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationService {
  StabilizationService._();

  // ── PUBLIC API ──────────────────────────────────────────────────────────────

  /// Evaluate stabilization state given [rule] and current [readings].
  ///
  /// Returns a [StabilizationResult] that describes:
  ///   - current [StabStatus]
  ///   - annotated readings (each with [ParameterReading.isWithinLimit])
  ///   - [finalValue] when stabilized
  ///   - how many [consecutiveValid] comparisons exist at the end of the list
  ///   - a human-readable [message] for the UI
  static StabilizationResult calculate(
    StabilizationRule rule,
    List<ParameterReading> readings,
  ) {
    if (readings.isEmpty) {
      return const StabilizationResult(
        status:  StabStatus.waiting,
        readings: [],
        message: 'Aguardando leituras',
      );
    }

    // Annotate: compare each reading to the previous one
    final annotated = _annotate(rule, readings);
    final consecutiveValid = _countConsecutiveValid(annotated);
    final requiredComparisons = rule.minReadings - 1; // 3 readings → 2 checks

    if (readings.length < rule.minReadings) {
      final remaining = rule.minReadings - readings.length;
      return StabilizationResult(
        status:           StabStatus.collecting,
        readings:         annotated,
        consecutiveValid: consecutiveValid,
        message:          'Adicione mais $remaining leitura(s) — '
                          '$consecutiveValid comparação(ões) dentro do critério',
      );
    }

    // We have enough readings — check trailing consecutive valid comparisons
    if (consecutiveValid >= requiredComparisons) {
      final finalValue = _computeFinalValue(rule, annotated);
      return StabilizationResult(
        status:           StabStatus.stabilized,
        readings:         annotated,
        finalValue:       finalValue,
        consecutiveValid: consecutiveValid,
        message:          'Parâmetro estabilizado ✓',
      );
    }

    return StabilizationResult(
      status:           StabStatus.outOfRange,
      readings:         annotated,
      consecutiveValid: consecutiveValid,
      message:          'Fora do critério — adicione leituras ou justifique',
    );
  }

  /// Human-readable criterion label for UI display.
  static String criterionLabel(StabilizationRule rule) {
    switch (rule.criterionType) {
      case StabCriterionType.absolute:
        return 'Δ ≤ ${rule.limit} ${rule.unit} entre ${rule.minReadings} leituras';
      case StabCriterionType.percent:
        return 'Δ ≤ ${rule.limit.toStringAsFixed(0)}% entre ${rule.minReadings} leituras';
    }
  }

  // ── PRIVATE HELPERS ─────────────────────────────────────────────────────────

  /// Returns a new list with [ParameterReading.isWithinLimit] populated.
  /// First reading always gets null (no prior value to compare).
  static List<ParameterReading> _annotate(
    StabilizationRule rule,
    List<ParameterReading> readings,
  ) {
    final result = <ParameterReading>[];
    for (int i = 0; i < readings.length; i++) {
      if (i == 0) {
        result.add(readings[i].copyWith(isWithinLimit: null));
      } else {
        final within = _compare(rule, readings[i - 1].value, readings[i].value);
        result.add(readings[i].copyWith(isWithinLimit: within));
      }
    }
    return result;
  }

  /// Returns true when [curr] vs [prev] is within the rule's criterion.
  static bool _compare(StabilizationRule rule, double prev, double curr) {
    switch (rule.criterionType) {
      case StabCriterionType.absolute:
        return (curr - prev).abs() <= rule.limit;
      case StabCriterionType.percent:
        // Guard: if previous value is effectively zero, comparison is undefined.
        if (prev.abs() < 1e-9) return false;
        final pct = ((curr - prev).abs() / prev.abs()) * 100.0;
        return pct <= rule.limit;
    }
  }

  /// Count how many consecutive valid comparisons exist from the END of the list.
  /// Used to detect stabilization at the tail of the reading sequence.
  static int _countConsecutiveValid(List<ParameterReading> annotated) {
    int count = 0;
    for (int i = annotated.length - 1; i >= 1; i--) {
      if (annotated[i].isWithinLimit == true) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static double? _computeFinalValue(
    StabilizationRule rule,
    List<ParameterReading> readings,
  ) {
    if (readings.isEmpty) return null;
    switch (rule.finalStrategy) {
      case StabFinalStrategy.lastReading:
        return readings.last.value;
      case StabFinalStrategy.averageOfValidReadings:
        final valid =
            readings.where((r) => r.isWithinLimit == true).toList();
        if (valid.isEmpty) return readings.last.value;
        return valid.map((r) => r.value).reduce((a, b) => a + b) / valid.length;
    }
  }
}
