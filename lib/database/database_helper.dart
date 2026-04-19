import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models.dart';

class DatabaseHelper {
  static const _dbName    = 'ecoflow.db';
  static const _dbVersion = 4; // v4: collection metadata (weather, checklist, observations)

  static const tCampaigns      = 'campaigns';
  static const tFieldPoints    = 'field_points';
  static const tParamReadings  = 'parameter_readings';
  static const tSyncQueue      = 'sync_queue';
  static const tEvidences      = 'collection_evidences';
  static const tSyncLog        = 'sync_log';

  DatabaseHelper._();
  static final instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ─────────────────────────────────────────────
  // SCHEMA v1 + v2 + v3 (fresh install)
  // ─────────────────────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tCampaigns (
        id          TEXT PRIMARY KEY,
        code        TEXT NOT NULL,
        name        TEXT NOT NULL,
        client      TEXT NOT NULL,
        responsible TEXT NOT NULL,
        deadline    TEXT NOT NULL,
        totalPoints INTEGER NOT NULL DEFAULT 0,
        donePoints  INTEGER NOT NULL DEFAULT 0,
        status      TEXT NOT NULL DEFAULT 'nova',
        external_id TEXT,
        server_version INTEGER DEFAULT 0,
        last_synced_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $tFieldPoints (
        id                              INTEGER PRIMARY KEY AUTOINCREMENT,
        campaignId                      TEXT    NOT NULL,
        code                            TEXT    NOT NULL,
        name                            TEXT    NOT NULL,
        type                            TEXT    NOT NULL,
        typeLabel                       TEXT    NOT NULL,
        status                          TEXT    NOT NULL DEFAULT 'pending',
        hasPhoto                        INTEGER NOT NULL DEFAULT 0,
        gpsLat                          TEXT,
        gpsLng                          TEXT,
        ncReported                      INTEGER NOT NULL DEFAULT 0,
        ncMotive                        TEXT,
        pointOrder                      INTEGER NOT NULL DEFAULT 0,
        stabilization_status            TEXT,
        stabilization_summary_json      TEXT,
        stabilization_completed_at      TEXT,
        stabilization_exception_reason  TEXT,
        stabilization_exception_notes   TEXT,
        final_parameter_values_json     TEXT,
        external_id                     TEXT,
        record_external_id              TEXT,
        server_version                  INTEGER DEFAULT 0,
        last_synced_at                  TEXT,
        dirty                           INTEGER NOT NULL DEFAULT 0,
        weather_conditions_json         TEXT,
        checklist_pop_json              TEXT,
        obs_tags_json                   TEXT,
        observations_text               TEXT,
        FOREIGN KEY (campaignId) REFERENCES $tCampaigns(id),
        UNIQUE(campaignId, code)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tParamReadings (
        id                       INTEGER PRIMARY KEY AUTOINCREMENT,
        field_point_id           INTEGER NOT NULL,
        parameter_name           TEXT    NOT NULL,
        reading_order            INTEGER NOT NULL,
        value                    REAL    NOT NULL,
        unit                     TEXT    NOT NULL,
        measured_at              TEXT    NOT NULL,
        stabilization_rule_type  TEXT    NOT NULL,
        stabilization_limit      REAL    NOT NULL,
        is_within_limit          INTEGER,
        created_at               TEXT    NOT NULL,
        updated_at               TEXT    NOT NULL,
        FOREIGN KEY (field_point_id) REFERENCES $tFieldPoints(id)
      )
    ''');

    await _createSyncTables(db);
    await _seed(db);
  }

  // ─────────────────────────────────────────────
  // SYNC TABLES — shared between fresh install and upgrade
  // ─────────────────────────────────────────────
  Future<void> _createSyncTables(Database db) async {
    // Queue of pending operations to push to the backend.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tSyncQueue (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        entity              TEXT    NOT NULL,
        external_id         TEXT    NOT NULL,
        local_id            TEXT,
        operation           TEXT    NOT NULL,
        payload_json        TEXT    NOT NULL,
        payload_hash        TEXT    NOT NULL,
        client_version      INTEGER NOT NULL DEFAULT 1,
        client_updated_at   TEXT    NOT NULL,
        status              TEXT    NOT NULL DEFAULT 'pending',
        attempts            INTEGER NOT NULL DEFAULT 0,
        last_error          TEXT,
        created_at          TEXT    NOT NULL,
        updated_at          TEXT    NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_status
      ON $tSyncQueue(status, created_at)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_entity_ref
      ON $tSyncQueue(entity, external_id)
      WHERE status = 'pending'
    ''');

    // Local mirror of evidences (photos) — uploads handled via S3 presigned URLs.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tEvidences (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        external_id         TEXT    NOT NULL UNIQUE,
        field_point_id      INTEGER,
        record_external_id  TEXT,
        local_file_path     TEXT    NOT NULL,
        mime_type           TEXT    NOT NULL,
        size_bytes          INTEGER NOT NULL,
        sha256              TEXT,
        captured_at         TEXT,
        gps_lat             TEXT,
        gps_lng             TEXT,
        caption             TEXT,
        upload_status       TEXT    NOT NULL DEFAULT 'pending',
        upload_key          TEXT,
        remote_url          TEXT,
        attempts            INTEGER NOT NULL DEFAULT 0,
        last_error          TEXT,
        created_at          TEXT    NOT NULL,
        updated_at          TEXT    NOT NULL,
        FOREIGN KEY (field_point_id) REFERENCES $tFieldPoints(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_evidences_upload_status
      ON $tEvidences(upload_status)
    ''');

    // Audit log of sync attempts (for diagnostics in the profile screen).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tSyncLog (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_token        TEXT,
        started_at        TEXT    NOT NULL,
        finished_at       TEXT,
        items_total       INTEGER NOT NULL DEFAULT 0,
        items_processed   INTEGER NOT NULL DEFAULT 0,
        items_failed      INTEGER NOT NULL DEFAULT 0,
        items_conflict    INTEGER NOT NULL DEFAULT 0,
        items_duplicated  INTEGER NOT NULL DEFAULT 0,
        status            TEXT    NOT NULL,
        error_message     TEXT
      )
    ''');
  }

  // ─────────────────────────────────────────────
  // MIGRATIONS
  // SQLite only supports ADD COLUMN — one at a time.
  // ─────────────────────────────────────────────
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add stabilization columns to field_points
      const alter = 'ALTER TABLE $tFieldPoints ADD COLUMN';
      await db.execute("$alter stabilization_status           TEXT");
      await db.execute("$alter stabilization_summary_json     TEXT");
      await db.execute("$alter stabilization_completed_at     TEXT");
      await db.execute("$alter stabilization_exception_reason TEXT");
      await db.execute("$alter stabilization_exception_notes  TEXT");
      await db.execute("$alter final_parameter_values_json    TEXT");

      // Create parameter_readings table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tParamReadings (
          id                       INTEGER PRIMARY KEY AUTOINCREMENT,
          field_point_id           INTEGER NOT NULL,
          parameter_name           TEXT    NOT NULL,
          reading_order            INTEGER NOT NULL,
          value                    REAL    NOT NULL,
          unit                     TEXT    NOT NULL,
          measured_at              TEXT    NOT NULL,
          stabilization_rule_type  TEXT    NOT NULL,
          stabilization_limit      REAL    NOT NULL,
          is_within_limit          INTEGER,
          created_at               TEXT    NOT NULL,
          updated_at               TEXT    NOT NULL,
          FOREIGN KEY (field_point_id) REFERENCES $tFieldPoints(id)
        )
      ''');
    }

    if (oldVersion < 3) {
      // Add sync-related columns to campaigns
      await db.execute("ALTER TABLE $tCampaigns ADD COLUMN external_id TEXT");
      await db.execute("ALTER TABLE $tCampaigns ADD COLUMN server_version INTEGER DEFAULT 0");
      await db.execute("ALTER TABLE $tCampaigns ADD COLUMN last_synced_at TEXT");
      await db.execute("ALTER TABLE $tCampaigns ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0");

      // Add sync-related columns to field_points
      await db.execute("ALTER TABLE $tFieldPoints ADD COLUMN external_id TEXT");
      await db.execute("ALTER TABLE $tFieldPoints ADD COLUMN record_external_id TEXT");
      await db.execute("ALTER TABLE $tFieldPoints ADD COLUMN server_version INTEGER DEFAULT 0");
      await db.execute("ALTER TABLE $tFieldPoints ADD COLUMN last_synced_at TEXT");
      await db.execute("ALTER TABLE $tFieldPoints ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0");

      // Create new tables
      await _createSyncTables(db);
    }

    if (oldVersion < 4) {
      // Add collection metadata columns to field_points
      const alter = 'ALTER TABLE $tFieldPoints ADD COLUMN';
      await db.execute("$alter weather_conditions_json TEXT");
      await db.execute("$alter checklist_pop_json      TEXT");
      await db.execute("$alter obs_tags_json           TEXT");
      await db.execute("$alter observations_text       TEXT");
    }
  }

  // ─────────────────────────────────────────────
  // SEED — dados de teste realistas
  // ─────────────────────────────────────────────
  Future<void> _seed(Database db) async {
    final batch = db.batch();

    final campaigns = [
      {
        'id': 'basf_paulinia_04', 'code': 'CAMP-2025-04',
        'name': 'Monitoramento Paulínia',
        'client': 'BASF S.A. · Campanha 04/2025',
        'responsible': 'A. Ferreira', 'deadline': '10/04/2025',
        'totalPoints': 6, 'donePoints': 2, 'status': 'emCampo',
      },
      {
        'id': 'vale_carajas_1s', 'code': 'CAMP-2025-03',
        'name': 'Monitoramento Vale Carajás',
        'client': 'Vale S.A. · Campanha 1S/2025',
        'responsible': 'C. Almeida', 'deadline': '25/04/2025',
        'totalPoints': 8, 'donePoints': 0, 'status': 'nova',
      },
      {
        'id': 'petro_cubatao_q1', 'code': 'CAMP-2025-02',
        'name': 'Monitoramento Cubatão',
        'client': 'Petrobras · Campanha Q1/2025',
        'responsible': 'C. Almeida', 'deadline': '01/04/2025',
        'totalPoints': 4, 'donePoints': 0, 'status': 'atrasada',
      },
      {
        'id': 'vale_carajas_2s', 'code': 'CAMP-2024-18',
        'name': 'Vale Carajás — 2S/2024',
        'client': 'Vale S.A. · Campanha 2S/2024',
        'responsible': 'M. Santos', 'deadline': '15/12/2024',
        'totalPoints': 10, 'donePoints': 10, 'status': 'concluida',
      },
      {
        'id': 'sabesp_piracicaba', 'code': 'CAMP-2025-05',
        'name': 'ETDI Piracicaba',
        'client': 'SABESP · Monitoramento Q2/2025',
        'responsible': 'R. Costa', 'deadline': '30/06/2025',
        'totalPoints': 5, 'donePoints': 0, 'status': 'nova',
      },
      {
        'id': 'cpfl_paraiba', 'code': 'CAMP-2025-06',
        'name': 'Paraíba do Sul — Ciclo 1',
        'client': 'CPFL Energia · Campanha 2025',
        'responsible': 'A. Ferreira', 'deadline': '20/05/2025',
        'totalPoints': 6, 'donePoints': 1, 'status': 'emCampo',
      },
    ];
    for (final c in campaigns) { batch.insert(tCampaigns, c); }

    final points = [
      // BASF Paulínia — 6 pontos (2 done, 4 pending)
      _pt('basf_paulinia_04', 'NAS-001', 'Nascente Ribeirão Quilombo',    'nasc', 'Nascente',   'done',    1, lat: '-22.7632', lng: '-47.1534'),
      _pt('basf_paulinia_04', 'NAS-002', 'Nascente Córrego da Fazenda',   'nasc', 'Nascente',   'done',    2, lat: '-22.7701', lng: '-47.1489'),
      _pt('basf_paulinia_04', 'DRN-001', 'Drenagem Canal Industrial',     'dren', 'Drenagem',   'pending', 3),
      _pt('basf_paulinia_04', 'DRN-002', 'Saída Córrego Piçarrão',        'dren', 'Drenagem',   'pending', 4),
      _pt('basf_paulinia_04', 'PZ-001',  'Piezômetro P-01 Norte',         'inst', 'Piezômetro', 'pending', 5),
      _pt('basf_paulinia_04', 'PZ-002',  'Piezômetro P-02 Sul',           'inst', 'Piezômetro', 'pending', 6),
      // Vale Carajás — 8 pontos
      _pt('vale_carajas_1s', 'NAS-001', 'Afloramento N-01',               'nasc', 'Nascente',   'pending', 1),
      _pt('vale_carajas_1s', 'NAS-002', 'Afloramento N-02',               'nasc', 'Nascente',   'pending', 2),
      _pt('vale_carajas_1s', 'NAS-003', 'Cabeceira Igarapé Cristal',      'nasc', 'Nascente',   'pending', 3),
      _pt('vale_carajas_1s', 'NAS-004', 'Revegetação N-04',               'nasc', 'Nascente',   'pending', 4),
      _pt('vale_carajas_1s', 'DRN-001', 'Drenagem Margem Esquerda',       'dren', 'Drenagem',   'pending', 5),
      _pt('vale_carajas_1s', 'DRN-002', 'Saída Bacia de Sedimentação',    'dren', 'Drenagem',   'pending', 6),
      _pt('vale_carajas_1s', 'VERT-001','Vertedouro Barragem Leste',      'vert', 'Vertedouro', 'pending', 7),
      _pt('vale_carajas_1s', 'PZ-001',  'Piezômetro Serra Norte',         'inst', 'Piezômetro', 'pending', 8),
      // Petrobras Cubatão — 4 pontos
      _pt('petro_cubatao_q1', 'NAS-001', 'Nascente Área de Preservação',  'nasc', 'Nascente',   'pending', 1),
      _pt('petro_cubatao_q1', 'DRN-001', 'Drenagem Zona Portuária',       'dren', 'Drenagem',   'pending', 2),
      _pt('petro_cubatao_q1', 'DRN-002', 'Canal de Drenagem Pluvial',     'dren', 'Drenagem',   'pending', 3),
      _pt('petro_cubatao_q1', 'PZ-001',  'Piezômetro Talude Norte',       'inst', 'Piezômetro', 'nc',      4, ncReported: 1, ncMotive: 'Acesso negado / área restrita'),
      // Vale 2S/2024 — 10 pontos done
      _pt('vale_carajas_2s', 'NAS-001', 'Afloramento N-01',               'nasc', 'Nascente',   'done', 1,  lat: '-6.0521', lng: '-50.1643'),
      _pt('vale_carajas_2s', 'NAS-002', 'Afloramento N-02',               'nasc', 'Nascente',   'done', 2,  lat: '-6.0534', lng: '-50.1672'),
      _pt('vale_carajas_2s', 'NAS-003', 'Cabeceira Igarapé Cristal',      'nasc', 'Nascente',   'done', 3,  lat: '-6.0498', lng: '-50.1589'),
      _pt('vale_carajas_2s', 'NAS-004', 'Revegetação N-04',               'nasc', 'Nascente',   'done', 4,  lat: '-6.0567', lng: '-50.1701'),
      _pt('vale_carajas_2s', 'DRN-001', 'Drenagem Margem Esquerda',       'dren', 'Drenagem',   'done', 5,  lat: '-6.0612', lng: '-50.1745'),
      _pt('vale_carajas_2s', 'DRN-002', 'Saída Bacia de Sedimentação',    'dren', 'Drenagem',   'done', 6,  lat: '-6.0589', lng: '-50.1698'),
      _pt('vale_carajas_2s', 'DRN-003', 'Canal Norte Km 12',              'dren', 'Drenagem',   'done', 7,  lat: '-6.0478', lng: '-50.1534'),
      _pt('vale_carajas_2s', 'VERT-001','Vertedouro Barragem Leste',      'vert', 'Vertedouro', 'done', 8,  lat: '-6.0723', lng: '-50.1812'),
      _pt('vale_carajas_2s', 'PZ-001',  'Piezômetro Serra Norte P-01',    'inst', 'Piezômetro', 'done', 9,  lat: '-6.0445', lng: '-50.1456'),
      _pt('vale_carajas_2s', 'PZ-002',  'Piezômetro Serra Norte P-02',    'inst', 'Piezômetro', 'done', 10, lat: '-6.0467', lng: '-50.1478'),
      // SABESP Piracicaba
      _pt('sabesp_piracicaba', 'PM-01', 'Ponto de Monitoramento 01',      'fq',   'Fís.-Quím.', 'pending', 1),
      _pt('sabesp_piracicaba', 'PM-02', 'Ponto de Monitoramento 02',      'fq',   'Fís.-Quím.', 'pending', 2),
      _pt('sabesp_piracicaba', 'PM-03', 'Captação Rio Piracicaba',        'fq',   'Fís.-Quím.', 'pending', 3),
      _pt('sabesp_piracicaba', 'PM-04', 'Efluente ETDI — Saída',          'fq',   'Fís.-Quím.', 'pending', 4),
      _pt('sabesp_piracicaba', 'DRN-001','Drenagem Pluvial Adjacente',    'dren', 'Drenagem',   'pending', 5),
      // CPFL Paraíba
      _pt('cpfl_paraiba', 'NAS-001', 'Nascente Margem Direita',           'nasc', 'Nascente',   'done',    1, lat: '-22.1234', lng: '-43.7891'),
      _pt('cpfl_paraiba', 'NAS-002', 'Nascente Área de APP',              'nasc', 'Nascente',   'pending', 2),
      _pt('cpfl_paraiba', 'DRN-001', 'Drenagem Jusante PCH',              'dren', 'Drenagem',   'pending', 3),
      _pt('cpfl_paraiba', 'DRN-002', 'Canal de Fuga',                     'dren', 'Drenagem',   'pending', 4),
      _pt('cpfl_paraiba', 'VERT-001','Vertedouro PCH Paraíba',            'vert', 'Vertedouro', 'pending', 5),
      _pt('cpfl_paraiba', 'PZ-001',  'Piezômetro Barragem',               'inst', 'Piezômetro', 'pending', 6),
    ];
    for (final p in points) { batch.insert(tFieldPoints, p); }

    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _pt(
    String campaignId, String code, String name,
    String type, String typeLabel, String status, int order, {
    String? lat, String? lng,
    int hasPhoto = 0, int ncReported = 0, String? ncMotive,
  }) => {
    'campaignId': campaignId, 'code': code, 'name': name,
    'type': type, 'typeLabel': typeLabel, 'status': status,
    'hasPhoto': hasPhoto, 'gpsLat': lat, 'gpsLng': lng,
    'ncReported': ncReported, 'ncMotive': ncMotive, 'pointOrder': order,
  };

  // ─────────────────────────────────────────────
  // CAMPAIGNS — leitura
  // ─────────────────────────────────────────────
  Future<List<Campaign>> getCampaigns() async {
    final db = await database;
    final rows = await db.query(tCampaigns, orderBy: 'rowid ASC');
    return rows.map(Campaign.fromMap).toList();
  }

  Future<Campaign?> getCampaignById(String id) async {
    final db = await database;
    final rows = await db.query(tCampaigns, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Campaign.fromMap(rows.first);
  }

  // ─────────────────────────────────────────────
  // CAMPAIGNS — escrita
  // ─────────────────────────────────────────────
  Future<void> updateCampaignProgress(String id, int donePoints) async {
    final db = await database;
    await db.update(tCampaigns, {'donePoints': donePoints},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateCampaignStatus(String id, String status) async {
    final db = await database;
    await db.update(tCampaigns, {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────
  // FIELD POINTS — leitura
  // ─────────────────────────────────────────────
  Future<List<FieldPoint>> getPointsByCampaign(String campaignId) async {
    final db = await database;
    final rows = await db.query(
      tFieldPoints,
      where: 'campaignId = ?',
      whereArgs: [campaignId],
      orderBy: 'pointOrder ASC',
    );
    return rows.map(FieldPoint.fromMap).toList();
  }

  // ─────────────────────────────────────────────
  // FIELD POINTS — escrita
  // ─────────────────────────────────────────────
  Future<void> updatePointStatus(
    String campaignId, String code, String status, {
    String? gpsLat, String? gpsLng,
    String? ncMotive, int? ncReported,
  }) async {
    final db = await database;
    final values = <String, dynamic>{'status': status};
    if (gpsLat     != null) values['gpsLat']     = gpsLat;
    if (gpsLng     != null) values['gpsLng']     = gpsLng;
    if (ncMotive   != null) values['ncMotive']   = ncMotive;
    if (ncReported != null) values['ncReported'] = ncReported;
    await db.update(tFieldPoints, values,
        where: 'campaignId = ? AND code = ?', whereArgs: [campaignId, code]);
  }

  Future<void> markPointDone(String campaignId, String code,
      {String? gpsLat, String? gpsLng}) async {
    await updatePointStatus(campaignId, code, 'done',
        gpsLat: gpsLat, gpsLng: gpsLng);
  }

  Future<void> markPointNc(String campaignId, String code,
      String motive) async {
    await updatePointStatus(campaignId, code, 'nc',
        ncMotive: motive, ncReported: 1);
  }

  Future<void> setPointGps(String campaignId, String code,
      String lat, String lng) async {
    final db = await database;
    await db.update(
      tFieldPoints,
      {'gpsLat': lat, 'gpsLng': lng},
      where: 'campaignId = ? AND code = ?', whereArgs: [campaignId, code],
    );
  }

  // ─────────────────────────────────────────────
  // COLLECTION METADATA — clima, checklist POP, observações
  // ─────────────────────────────────────────────

  Future<void> saveCollectionMeta({
    required String campaignId,
    required String pointCode,
    required String weatherConditionsJson,
    required String checklistPopJson,
    required String obsTagsJson,
    required String observationsText,
  }) async {
    final db = await database;
    await db.update(
      tFieldPoints,
      {
        'weather_conditions_json': weatherConditionsJson,
        'checklist_pop_json':      checklistPopJson,
        'obs_tags_json':           obsTagsJson,
        'observations_text':       observationsText,
        'dirty':                   1,
      },
      where: 'campaignId = ? AND code = ?',
      whereArgs: [campaignId, pointCode],
    );
  }

  // ─────────────────────────────────────────────
  // SYNC HELPERS — reading external_ids and dirty flags
  // ─────────────────────────────────────────────

  /// Generates and persists an external_id for a campaign if missing.
  /// Returns the external_id (existing or newly generated).
  Future<String> ensureCampaignExternalId(String campaignId, String Function() generator) async {
    final db = await database;
    final rows = await db.query(
      tCampaigns,
      columns: ['external_id'],
      where: 'id = ?',
      whereArgs: [campaignId],
    );
    if (rows.isEmpty) throw StateError('Campaign $campaignId not found');
    final existing = rows.first['external_id'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    final newId = generator();
    await db.update(
      tCampaigns,
      {'external_id': newId, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [campaignId],
    );
    return newId;
  }

  /// Generates and persists external_id + record_external_id for a point.
  Future<({String pointExternalId, String recordExternalId})>
      ensurePointExternalIds(
    String campaignId,
    String code,
    String Function() generator,
  ) async {
    final db = await database;
    final rows = await db.query(
      tFieldPoints,
      columns: ['external_id', 'record_external_id'],
      where: 'campaignId = ? AND code = ?',
      whereArgs: [campaignId, code],
    );
    if (rows.isEmpty) throw StateError('Point $code not found in $campaignId');

    var pointExt = rows.first['external_id'] as String?;
    var recordExt = rows.first['record_external_id'] as String?;
    final patch = <String, dynamic>{};
    if (pointExt == null || pointExt.isEmpty) {
      pointExt = generator();
      patch['external_id'] = pointExt;
    }
    if (recordExt == null || recordExt.isEmpty) {
      recordExt = generator();
      patch['record_external_id'] = recordExt;
    }
    if (patch.isNotEmpty) {
      patch['dirty'] = 1;
      await db.update(tFieldPoints, patch,
          where: 'campaignId = ? AND code = ?',
          whereArgs: [campaignId, code]);
    }
    return (pointExternalId: pointExt, recordExternalId: recordExt);
  }

  /// Returns a campaign row with sync metadata (raw map).
  Future<Map<String, dynamic>?> getCampaignRawById(String campaignId) async {
    final db = await database;
    final rows = await db.query(tCampaigns, where: 'id = ?', whereArgs: [campaignId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns a point row with sync metadata (raw map).
  Future<Map<String, dynamic>?> getPointRaw(String campaignId, String code) async {
    final db = await database;
    final rows = await db.query(
      tFieldPoints,
      where: 'campaignId = ? AND code = ?',
      whereArgs: [campaignId, code],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Mark an entity as clean (synced) after a successful push.
  Future<void> markEntitySynced({
    required String table,
    required String whereClause,
    required List<Object?> whereArgs,
    required int serverVersion,
  }) async {
    final db = await database;
    await db.update(
      table,
      {
        'dirty': 0,
        'server_version': serverVersion,
        'last_synced_at': DateTime.now().toIso8601String(),
      },
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Mark an entity as dirty (needs push) — called by AppState on every mutation.
  Future<void> markDirty(String table, String whereClause, List<Object?> whereArgs) async {
    final db = await database;
    await db.update(table, {'dirty': 1}, where: whereClause, whereArgs: whereArgs);
  }

  /// Upsert a campaign received from the server (pull).
  /// Matches by external_id; creates locally if missing.
  Future<void> upsertCampaignFromServer(Map<String, dynamic> serverRow) async {
    final db = await database;
    final externalId = serverRow['external_id'] as String;

    final existing = await db.query(
      tCampaigns,
      where: 'external_id = ?',
      whereArgs: [externalId],
    );

    final row = <String, dynamic>{
      'code':           serverRow['code'],
      'name':           serverRow['name'],
      'client':         serverRow['client'],
      'responsible':    serverRow['responsible'],
      'deadline':       serverRow['deadline'],
      'totalPoints':    serverRow['totalPoints'] ?? 0,
      'donePoints':     serverRow['donePoints'] ?? 0,
      'status':         serverRow['status'] ?? 'nova',
      'external_id':    externalId,
      'server_version': serverRow['server_version'] ?? 1,
      'last_synced_at': DateTime.now().toIso8601String(),
      'dirty':          0,
    };

    if (existing.isEmpty) {
      row['id'] = serverRow['id'] ?? externalId;
      await db.insert(tCampaigns, row);
    } else {
      // Don't overwrite dirty local rows unless server_version is strictly greater
      final localDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      final localVer   = existing.first['server_version'] as int? ?? 0;
      final serverVer  = serverRow['server_version'] as int? ?? 0;
      if (localDirty && serverVer <= localVer) return;

      await db.update(
        tCampaigns,
        row,
        where: 'external_id = ?',
        whereArgs: [externalId],
      );
    }
  }

  // ─────────────────────────────────────────────
  // SYNC LOG — leitura para tela de diagnósticos
  // ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecentSyncLogs({int limit = 30}) async {
    final db = await database;
    return db.query(
      tSyncLog,
      orderBy: 'started_at DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getFailedQueueItems({int limit = 50}) async {
    final db = await database;
    return db.query(
      tSyncQueue,
      where: "status = 'failed'",
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  // ─────────────────────────────────────────────
  Future<void> resetDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    await deleteDatabase(path);
    _db = null;
  }
}
