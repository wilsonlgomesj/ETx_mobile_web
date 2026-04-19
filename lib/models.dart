enum PointStatus { pending, done, nc }
enum OperationalStatus { emCampo, nova, atrasada, concluida }
enum CollectionType { nasc, dren, vert, inst, fq }

OperationalStatus _opStatus(String s) => OperationalStatus.values
    .firstWhere((e) => e.name == s, orElse: () => OperationalStatus.nova);

PointStatus _ptStatus(String s) => PointStatus.values
    .firstWhere((e) => e.name == s, orElse: () => PointStatus.pending);

CollectionType _colType(String s) => CollectionType.values
    .firstWhere((e) => e.name == s, orElse: () => CollectionType.nasc);

class Campaign {
  final String id;
  final String code;
  final String name;
  final String client;
  final String responsible;
  final String deadline;
  final int totalPoints;
  final int donePoints;
  final OperationalStatus status;

  const Campaign({
    required this.id,
    required this.code,
    required this.name,
    required this.client,
    required this.responsible,
    required this.deadline,
    required this.totalPoints,
    required this.donePoints,
    required this.status,
  });

  double get progress => totalPoints > 0 ? donePoints / totalPoints : 0.0;

  factory Campaign.fromMap(Map<String, dynamic> m) => Campaign(
        id:          m['id'] as String,
        code:        m['code'] as String,
        name:        m['name'] as String,
        client:      m['client'] as String,
        responsible: m['responsible'] as String,
        deadline:    m['deadline'] as String,
        totalPoints: m['totalPoints'] as int,
        donePoints:  m['donePoints'] as int,
        status:      _opStatus(m['status'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id':          id,
        'code':        code,
        'name':        name,
        'client':      client,
        'responsible': responsible,
        'deadline':    deadline,
        'totalPoints': totalPoints,
        'donePoints':  donePoints,
        'status':      status.name,
      };
}

class FieldPoint {
  final int? id;
  final String? campaignId;
  final String code;
  final String name;
  final CollectionType type;
  final String typeLabel;
  PointStatus status;
  Map<String, String> params;
  bool hasPhoto;
  String? gpsLat;
  String? gpsLng;
  bool ncReported;
  String? ncMotive;

  // Stabilization fields (populated after save)
  String? stabilizationStatus;
  String? stabilizationSummaryJson;
  String? stabilizationCompletedAt;
  String? stabilizationExceptionReason;
  String? stabilizationExceptionNotes;
  String? finalParameterValuesJson;

  FieldPoint({
    this.id,
    this.campaignId,
    required this.code,
    required this.name,
    required this.type,
    required this.typeLabel,
    this.status = PointStatus.pending,
    Map<String, String>? params,
    this.hasPhoto = false,
    this.gpsLat,
    this.gpsLng,
    this.ncReported = false,
    this.ncMotive,
    this.stabilizationStatus,
    this.stabilizationSummaryJson,
    this.stabilizationCompletedAt,
    this.stabilizationExceptionReason,
    this.stabilizationExceptionNotes,
    this.finalParameterValuesJson,
  }) : params = params ?? {};

  factory FieldPoint.fromMap(Map<String, dynamic> m) => FieldPoint(
        id:                          m['id'] as int?,
        campaignId:                  m['campaignId'] as String?,
        code:                        m['code'] as String,
        name:                        m['name'] as String,
        type:                        _colType(m['type'] as String),
        typeLabel:                   m['typeLabel'] as String,
        status:                      _ptStatus(m['status'] as String),
        hasPhoto:                    (m['hasPhoto'] as int? ?? 0) == 1,
        gpsLat:                      m['gpsLat'] as String?,
        gpsLng:                      m['gpsLng'] as String?,
        ncReported:                  (m['ncReported'] as int? ?? 0) == 1,
        ncMotive:                    m['ncMotive'] as String?,
        stabilizationStatus:         m['stabilization_status'] as String?,
        stabilizationSummaryJson:    m['stabilization_summary_json'] as String?,
        stabilizationCompletedAt:    m['stabilization_completed_at'] as String?,
        stabilizationExceptionReason:m['stabilization_exception_reason'] as String?,
        stabilizationExceptionNotes: m['stabilization_exception_notes'] as String?,
        finalParameterValuesJson:    m['final_parameter_values_json'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (campaignId != null) 'campaignId': campaignId,
        'code':                         code,
        'name':                         name,
        'type':                         type.name,
        'typeLabel':                    typeLabel,
        'status':                       status.name,
        'hasPhoto':                     hasPhoto ? 1 : 0,
        'gpsLat':                       gpsLat,
        'gpsLng':                       gpsLng,
        'ncReported':                   ncReported ? 1 : 0,
        'ncMotive':                     ncMotive,
        'stabilization_status':         stabilizationStatus,
        'stabilization_summary_json':   stabilizationSummaryJson,
        'stabilization_completed_at':   stabilizationCompletedAt,
        'stabilization_exception_reason': stabilizationExceptionReason,
        'stabilization_exception_notes':  stabilizationExceptionNotes,
        'final_parameter_values_json':  finalParameterValuesJson,
      };
}

class Parameter {
  final String label;
  final String unit;
  final bool isPre;
  final String? previousValue;
  String value;

  Parameter({
    required this.label,
    required this.unit,
    this.isPre = false,
    this.previousValue,
    this.value = '',
  });
}

const List<Campaign> kCampaigns = [
  Campaign(
    id: 'cubatao',
    code: 'CAMP-2025-04 · #ENV-042',
    name: 'Monitoramento Paulínia',
    client: 'BASF S.A. · Campanha 04/2025',
    responsible: 'A. Ferreira',
    deadline: '10/04/2025',
    totalPoints: 6,
    donePoints: 2,
    status: OperationalStatus.emCampo,
  ),
  Campaign(
    id: 'vale',
    code: 'CAMP-2025-03 · #ENV-041',
    name: 'Monitoramento Vale Carajás',
    client: 'Vale S.A. · Campanha 1S/2025',
    responsible: 'C. Almeida',
    deadline: '25/04/2025',
    totalPoints: 6,
    donePoints: 0,
    status: OperationalStatus.nova,
  ),
  Campaign(
    id: 'paulinia',
    code: 'CAMP-2025-02 · #ENV-039',
    name: 'Monitoramento Cubatão',
    client: 'Petrobras · Campanha Q1/2025',
    responsible: 'C. Almeida',
    deadline: '01/04/2025',
    totalPoints: 4,
    donePoints: 0,
    status: OperationalStatus.atrasada,
  ),
];

List<FieldPoint> buildDefaultPoints() => [
  FieldPoint(code: 'NAS-001', name: 'Nascente Principal',       type: CollectionType.nasc, typeLabel: 'Nascente'),
  FieldPoint(code: 'NAS-002', name: 'Nascente Igarapé Sul',     type: CollectionType.nasc, typeLabel: 'Nascente'),
  FieldPoint(code: 'DRN-001', name: 'Drenagem Canal Norte',     type: CollectionType.dren, typeLabel: 'Drenagem'),
  FieldPoint(code: 'DRN-002', name: 'Saída Córrego Piçarrão',   type: CollectionType.dren, typeLabel: 'Drenagem'),
  FieldPoint(code: 'PZ-001',  name: 'Piezômetro P-01',          type: CollectionType.inst, typeLabel: 'Piezômetro'),
  FieldPoint(code: 'PZ-002',  name: 'Piezômetro P-02',          type: CollectionType.inst, typeLabel: 'Piezômetro'),
];

List<Parameter> buildDefaultParams() => [
  Parameter(label: 'pH',                   unit: 'adm',     isPre: false, previousValue: '6.82'),
  Parameter(label: 'Temperatura',          unit: '°C',      isPre: false, previousValue: '22.4'),
  Parameter(label: 'Condutividade',        unit: 'µS/cm',   isPre: false, previousValue: '148'),
  Parameter(label: 'OD',                   unit: 'mg/L',    isPre: false, previousValue: '7.1'),
  Parameter(label: 'ORP',                  unit: 'mV',      isPre: false, previousValue: '342'),
  Parameter(label: 'Turbidez',             unit: 'NTU',     isPre: false, previousValue: '4.2'),
  Parameter(label: 'Nível d\'água',        unit: 'm',       isPre: true,  previousValue: null),
  Parameter(label: 'Condut. estabilizada', unit: 'µS/cm',   isPre: true,  previousValue: null),
];

const List<String> kNcMotives = [
  'Acesso negado / área restrita',
  'Ponto seco ou ausência de água',
  'Condição climática adversa',
  'Equipamento com defeito',
  'Risco de segurança',
  'Coordenada ou marco incorreto',
  'Outro',
];

const List<String> kClimateOptions = [
  '☀️ Ensolarado',
  '⛅ Parcialmente nublado',
  '🌧️ Chuvoso',
  '🌫️ Neblina',
  '💨 Ventoso',
  '🌩️ Tempestade',
];

const List<String> kObsTags = [
  'Odor anômalo',
  'Coloração atípica',
  'Floração',
  'Lançamento',
  'Fauna aquática',
  'Vegetação alterada',
  'Resíduo presente',
];
