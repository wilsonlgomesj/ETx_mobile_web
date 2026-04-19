import 'dart:convert';

// ─────────────────────────────────────────────────────────────────────────────
// SYNC MAPPERS
// Pure functions that transform local models into the JSON payloads expected
// by the backend's /mobile/sync/batch endpoint.
//
// Each mapper returns a Map<String, dynamic> with the exact shape the backend
// validates against its Zod schema. If the backend schema changes, update here
// and bump ApiConfig.schemaVersion.
// ─────────────────────────────────────────────────────────────────────────────

class SyncMappers {
  SyncMappers._();

  // ── CAMPAIGN ──────────────────────────────────────────────────────────────

  /// Builds the payload for entity=mobile_campaign.
  ///
  /// [localRow] is the full sqflite row from the campaigns table — we read
  /// raw fields to avoid losing data that the Campaign domain model may drop.
  static Map<String, dynamic> campaignPayload({
    required Map<String, dynamic> localRow,
    required String? assignedUserExternalId,
  }) {
    final status = (localRow['status'] as String?) ?? 'nova';
    return {
      'name':        localRow['name'],
      'description': null,
      'code':        localRow['code'],
      'client':      localRow['client'],
      'responsible': localRow['responsible'],
      'deadline':    localRow['deadline'],
      'total_points': localRow['totalPoints'],
      'done_points':  localRow['donePoints'],
      'status':       _campaignStatusToWire(status),
      'assigned_user_external_id': assignedUserExternalId,
      'started_at':  null,
      'finished_at': status == 'concluida' ? DateTime.now().toUtc().toIso8601String() : null,
    };
  }

  // ── POINT ─────────────────────────────────────────────────────────────────

  /// Builds the payload for entity=collection_point.
  static Map<String, dynamic> pointPayload({
    required Map<String, dynamic> localRow,
    required String campaignExternalId,
  }) {
    return {
      'campaign_external_id': campaignExternalId,
      'code':        localRow['code'],
      'name':        localRow['name'],
      'point_type':  _pointTypeToWire(localRow['type'] as String?),
      'type_label':  localRow['typeLabel'],
      'latitude':    _parseCoord(localRow['gpsLat']),
      'longitude':   _parseCoord(localRow['gpsLng']),
      'coord_source': localRow['gpsLat'] != null ? 'gps' : null,
      'status':      _pointStatusToWire(localRow['status'] as String?, localRow),
      'order_index': localRow['pointOrder'],
    };
  }

  // ── RECORD ────────────────────────────────────────────────────────────────

  /// Builds the payload for entity=collection_record — the actual collection
  /// data with checklist, params, stabilization, QAQC, etc.
  ///
  /// This payload is the richest of all and represents what the backend
  /// stores mostly as JSONB (physchem_params, stabilization_readings, etc.).
  static Map<String, dynamic> recordPayload({
    required Map<String, dynamic> localRow,
    required String pointExternalId,
    required String campaignExternalId,
    required String? technicianExternalId,
    required String? technicianName,
  }) {
    final status = localRow['status'] as String? ?? 'pending';
    final ncReported = (localRow['ncReported'] as int? ?? 0) == 1;

    return {
      'point_external_id':    pointExternalId,
      'campaign_external_id': campaignExternalId,
      'collected_at':         localRow['stabilization_completed_at'] ??
                               DateTime.now().toUtc().toIso8601String(),
      'technician_external_id': technicianExternalId,
      'technician_name':        technicianName,
      'weather':              null, // TODO: enriquecer via ClimateOptions quando expostos
      'checklist_pop':        null, // idem — vem da UI do finish_screen
      'physchem_params':      _decodeOrNull(localRow['final_parameter_values_json']),
      'stabilization_readings':
          _decodeOrNull(localRow['stabilization_summary_json']),
      'justified_exception': _buildException(localRow),
      'nc': ncReported
          ? {
              'reported': true,
              'motive':   localRow['ncMotive'],
            }
          : null,
      'chain_of_custody': null, // evoluível
      'qaqc_summary': {
        'stabilization_status': localRow['stabilization_status'],
      },
      'observations':         null,
      'signature_image_url':  null,
      'closed_at':            localRow['stabilization_completed_at'],
      'point_status':         _pointStatusToWire(status, localRow),
    };
  }

  // ── EVIDENCE ──────────────────────────────────────────────────────────────

  /// Builds the payload for entity=collection_evidence.
  /// Note: file_uploaded must be true when enqueuing — the S3 upload happens
  /// BEFORE the record is sent in the batch.
  static Map<String, dynamic> evidencePayload({
    required String externalId,
    required String recordExternalId,
    required String pointExternalId,
    required String uploadKey,
    required String mimeType,
    required int sizeBytes,
    required DateTime capturedAt,
    double? gpsLat,
    double? gpsLng,
    String? caption,
  }) {
    return {
      'record_external_id': recordExternalId,
      'point_external_id':  pointExternalId,
      'file_uploaded': true,
      'file_key':      uploadKey,
      'mime_type':     mimeType,
      'size_bytes':    sizeBytes,
      'captured_at':   capturedAt.toUtc().toIso8601String(),
      'gps_lat':       gpsLat,
      'gps_lng':       gpsLng,
      'caption':       caption,
    };
  }

  // ── WIRE ENUMS ────────────────────────────────────────────────────────────

  static String _campaignStatusToWire(String localStatus) {
    switch (localStatus) {
      case 'emCampo':   return 'in_progress';
      case 'concluida': return 'completed';
      case 'atrasada':  return 'in_progress'; // backend não tem "overdue"
      case 'nova':
      default:          return 'planned';
    }
  }

  static String _pointTypeToWire(String? localType) {
    switch (localType) {
      case 'nasc': return 'spring';
      case 'dren': return 'drainage';
      case 'vert': return 'surface_water';
      case 'inst': return 'piezometer';
      case 'fq':   return 'surface_water';
      default:     return 'other';
    }
  }

  static String _pointStatusToWire(String? localStatus, Map<String, dynamic> row) {
    if ((row['ncReported'] as int? ?? 0) == 1) {
      return 'justified_exception';
    }
    switch (localStatus) {
      case 'done':    return 'collected';
      case 'nc':      return 'justified_exception';
      case 'pending':
      default:        return 'pending';
    }
  }

  // ── UTILITIES ─────────────────────────────────────────────────────────────

  static double? _parseCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static dynamic _decodeOrNull(dynamic v) {
    if (v == null) return null;
    if (v is Map || v is List) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _buildException(Map<String, dynamic> row) {
    final reason = row['stabilization_exception_reason'] as String?;
    final notes  = row['stabilization_exception_notes'] as String?;
    if ((reason == null || reason.isEmpty) && (notes == null || notes.isEmpty)) {
      return null;
    }
    return {
      'predefined_reason':    reason,
      'complementary_notes':  notes,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVER → LOCAL
// Used by the pull endpoint to hydrate local tables with campaigns/points
// pushed by the web (coordinator assigning a new campaign to a technician).
// ─────────────────────────────────────────────────────────────────────────────

class ServerMappers {
  ServerMappers._();

  static Map<String, dynamic> serverCampaignToLocalRow(
      Map<String, dynamic> server) {
    return {
      'id':           server['id'],
      'code':         server['code'] ?? '',
      'name':         server['name'],
      'client':       server['client'] ?? '',
      'responsible':  server['responsible'] ?? '',
      'deadline':     server['deadline'] ?? '',
      'totalPoints':  server['total_points'] ?? 0,
      'donePoints':   server['done_points'] ?? 0,
      'status':       _serverStatusToLocal(server['status'] as String?),
      'external_id':  server['external_id'],
      'server_version': server['server_version'] ?? 1,
    };
  }

  static String _serverStatusToLocal(String? s) {
    switch (s) {
      case 'in_progress': return 'emCampo';
      case 'completed':   return 'concluida';
      case 'planned':
      default:            return 'nova';
    }
  }
}
