// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum StabCriterionType { absolute, percent }

enum StabFinalStrategy { lastReading, averageOfValidReadings }

/// Visual/logical state of a parameter's stabilization process.
enum StabStatus {
  waiting,           // no readings yet
  collecting,        // has readings but not yet stabilized
  stabilized,        // criteria met — ready to save
  outOfRange,        // enough readings but last comparisons fail criterion
  justifiedException // saved with technical justification instead of stabilization
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION RULE  (immutable config per parameter)
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationRule {
  final String parameterName;
  final String unit;
  final StabCriterionType criterionType;
  final double limit;
  final int minReadings;
  final bool required;
  final StabFinalStrategy finalStrategy;
  final List<String> applicableTypes; // nasc, dren, vert, inst, fq

  const StabilizationRule({
    required this.parameterName,
    required this.unit,
    required this.criterionType,
    required this.limit,
    this.minReadings = 3,
    this.required = true,
    this.finalStrategy = StabFinalStrategy.lastReading,
    this.applicableTypes = const ['nasc', 'dren', 'vert', 'inst', 'fq'],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PARAMETER READING  (one measurement entry, persisted to DB)
// ─────────────────────────────────────────────────────────────────────────────

class ParameterReading {
  final int? id;
  final int fieldPointId;
  final String parameterName;
  final int readingOrder;
  final double value;
  final String unit;
  final DateTime measuredAt;
  final StabCriterionType ruleType;
  final double stabilizationLimit;

  /// null for the first reading (no prior to compare against).
  final bool? isWithinLimit;
  final DateTime createdAt;

  const ParameterReading({
    this.id,
    required this.fieldPointId,
    required this.parameterName,
    required this.readingOrder,
    required this.value,
    required this.unit,
    required this.measuredAt,
    required this.ruleType,
    required this.stabilizationLimit,
    this.isWithinLimit,
    required this.createdAt,
  });

  factory ParameterReading.fromMap(Map<String, dynamic> m) => ParameterReading(
        id:                 m['id'] as int?,
        fieldPointId:       m['field_point_id'] as int,
        parameterName:      m['parameter_name'] as String,
        readingOrder:       m['reading_order'] as int,
        value:              (m['value'] as num).toDouble(),
        unit:               m['unit'] as String,
        measuredAt:         DateTime.parse(m['measured_at'] as String),
        ruleType:           m['stabilization_rule_type'] == 'percent'
                              ? StabCriterionType.percent
                              : StabCriterionType.absolute,
        stabilizationLimit: (m['stabilization_limit'] as num).toDouble(),
        isWithinLimit:      m['is_within_limit'] == null
                              ? null
                              : (m['is_within_limit'] as int) == 1,
        createdAt:          DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'field_point_id':           fieldPointId,
        'parameter_name':           parameterName,
        'reading_order':            readingOrder,
        'value':                    value,
        'unit':                     unit,
        'measured_at':              measuredAt.toIso8601String(),
        'stabilization_rule_type':  ruleType.name,
        'stabilization_limit':      stabilizationLimit,
        'is_within_limit':          isWithinLimit == null
                                      ? null
                                      : (isWithinLimit! ? 1 : 0),
        'created_at':               createdAt.toIso8601String(),
        'updated_at':               DateTime.now().toIso8601String(),
      };

  ParameterReading copyWith({int? id, bool? isWithinLimit}) => ParameterReading(
        id:                 id ?? this.id,
        fieldPointId:       fieldPointId,
        parameterName:      parameterName,
        readingOrder:       readingOrder,
        value:              value,
        unit:               unit,
        measuredAt:         measuredAt,
        ruleType:           ruleType,
        stabilizationLimit: stabilizationLimit,
        isWithinLimit:      isWithinLimit ?? this.isWithinLimit,
        createdAt:          createdAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION RESULT  (output of service calculation — pure value object)
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationResult {
  final StabStatus status;
  final List<ParameterReading> readings;
  final double? finalValue;
  final int consecutiveValid;
  final String message;

  const StabilizationResult({
    required this.status,
    required this.readings,
    this.finalValue,
    this.consecutiveValid = 0,
    required this.message,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION EXCEPTION  (technical justification for saving without stab)
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationException {
  final String parameterName;
  final String predefinedReason;
  final String? complementaryNotes;
  final DateTime createdAt;

  const StabilizationException({
    required this.parameterName,
    required this.predefinedReason,
    this.complementaryNotes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'parameterName':      parameterName,
        'predefinedReason':   predefinedReason,
        'complementaryNotes': complementaryNotes,
        'createdAt':          createdAt.toIso8601String(),
      };

  factory StabilizationException.fromJson(Map<String, dynamic> j) =>
      StabilizationException(
        parameterName:      j['parameterName'] as String,
        predefinedReason:   j['predefinedReason'] as String,
        complementaryNotes: j['complementaryNotes'] as String?,
        createdAt:          DateTime.parse(j['createdAt'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PARAMETER STABILIZATION STATE  (mutable per-param state during collection)
// ─────────────────────────────────────────────────────────────────────────────

class ParameterStabilizationState {
  final StabilizationRule rule;
  List<ParameterReading> readings;
  StabilizationResult? lastResult;
  StabilizationException? exception;

  ParameterStabilizationState({
    required this.rule,
    List<ParameterReading>? readings,
    this.lastResult,
    this.exception,
  }) : readings = readings ?? [];

  StabStatus get effectiveStatus {
    if (exception != null) return StabStatus.justifiedException;
    if (lastResult != null) return lastResult!.status;
    if (readings.isEmpty) return StabStatus.waiting;
    return StabStatus.collecting;
  }

  /// True when this parameter is acceptable for saving:
  /// either properly stabilized, covered by a justification, or not required.
  bool get canSave =>
      effectiveStatus == StabStatus.stabilized ||
      effectiveStatus == StabStatus.justifiedException ||
      !rule.required;
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION QAQC  (campaign-level aggregate for FinishScreen)
// ─────────────────────────────────────────────────────────────────────────────

class StabilizationQaqc {
  final int totalWithStabilization;
  final int stabilized;
  final int withException;
  final int outOfRange;
  final double conformanceRate;

  const StabilizationQaqc({
    required this.totalWithStabilization,
    required this.stabilized,
    required this.withException,
    required this.outOfRange,
    required this.conformanceRate,
  });

  static const empty = StabilizationQaqc(
    totalWithStabilization: 0,
    stabilized: 0,
    withException: 0,
    outOfRange: 0,
    conformanceRate: 100.0,
  );
}
