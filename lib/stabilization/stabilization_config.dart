import 'stabilization_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPTION REASON CATALOGUE
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kStabilizationExceptionReasons = [
  'Recuperação lenta do poço',
  'Baixa coluna d\'água',
  'Instabilidade da sonda',
  'Interferência externa',
  'Tempo máximo operacional excedido',
  'Condição climática adversa',
  'Outro',
];

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION CONFIG
// Centralizes all rule definitions. Add new parameters here without touching
// any business logic or UI code.
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationConfig {
  StabilizationConfig._();

  static const List<StabilizationRule> _rules = [
    // ── Parameters requiring absolute-delta stabilization ──────────────────
    StabilizationRule(
      parameterName:   'pH',
      unit:            'adm',
      criterionType:   StabCriterionType.absolute,
      limit:           0.1,
      minReadings:     3,
      required:        true,
      finalStrategy:   StabFinalStrategy.lastReading,
      applicableTypes: ['nasc', 'dren', 'vert', 'fq'],
    ),
    StabilizationRule(
      parameterName:   'Temperatura',
      unit:            '°C',
      criterionType:   StabCriterionType.absolute,
      limit:           0.2,
      minReadings:     3,
      required:        true,
      finalStrategy:   StabFinalStrategy.lastReading,
      applicableTypes: ['nasc', 'dren', 'vert', 'fq'],
    ),
    StabilizationRule(
      parameterName:   'OD',
      unit:            'mg/L',
      criterionType:   StabCriterionType.absolute,
      limit:           0.2,
      minReadings:     3,
      required:        true,
      finalStrategy:   StabFinalStrategy.lastReading,
      applicableTypes: ['nasc', 'dren', 'vert', 'fq'],
    ),

    // ── Parameters requiring percent-variation stabilization ───────────────
    StabilizationRule(
      parameterName:   'Condutividade',
      unit:            'µS/cm',
      criterionType:   StabCriterionType.percent,
      limit:           5.0,
      minReadings:     3,
      required:        true,
      finalStrategy:   StabFinalStrategy.lastReading,
      applicableTypes: ['nasc', 'dren', 'vert', 'fq'],
    ),
  ];

  /// Returns the rule for [parameterName] if applicable to [collectionType].
  /// Returns null when the parameter does not require stabilization.
  static StabilizationRule? ruleFor(String parameterName, String collectionType) {
    try {
      return _rules.firstWhere(
        (r) =>
            r.parameterName == parameterName &&
            r.applicableTypes.contains(collectionType),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns all rules applicable to a given collection type.
  static List<StabilizationRule> rulesForType(String collectionType) =>
      _rules.where((r) => r.applicableTypes.contains(collectionType)).toList();
}
