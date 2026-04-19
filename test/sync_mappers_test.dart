import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ecoflowapp/api/sync_mappers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SyncMappers unit tests — pure functions, no DB or platform deps needed.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('SyncMappers.campaignPayload', () {
    test('maps emCampo → in_progress', () {
      final p = SyncMappers.campaignPayload(
        localRow: {
          'name': 'Camp A', 'code': 'C-01', 'client': 'BASF',
          'responsible': 'Tech', 'deadline': '2025-12-01',
          'totalPoints': 5, 'donePoints': 2, 'status': 'emCampo',
        },
        assignedUserExternalId: 'user-ext-1',
      );
      expect(p['status'], 'in_progress');
      expect(p['assigned_user_external_id'], 'user-ext-1');
    });

    test('sets finished_at for concluida campaigns', () {
      final p = SyncMappers.campaignPayload(
        localRow: {
          'name': 'Camp B', 'code': 'C-02', 'client': 'Vale',
          'responsible': 'Tech', 'deadline': '2025-06-01',
          'totalPoints': 3, 'donePoints': 3, 'status': 'concluida',
        },
        assignedUserExternalId: null,
      );
      expect(p['status'], 'completed');
      expect(p['finished_at'], isNotNull);
    });
  });

  group('SyncMappers.pointPayload', () {
    test('maps nasc type → spring', () {
      final p = SyncMappers.pointPayload(
        localRow: {
          'code': 'NAS-001', 'name': 'Nascente', 'type': 'nasc',
          'typeLabel': 'Nascente', 'gpsLat': '-22.76', 'gpsLng': '-47.15',
          'status': 'done', 'ncReported': 0, 'pointOrder': 1,
        },
        campaignExternalId: 'camp-ext-1',
      );
      expect(p['point_type'], 'spring');
      expect(p['latitude'], closeTo(-22.76, 0.001));
      expect(p['coord_source'], 'gps');
    });

    test('nc point → justified_exception status', () {
      final p = SyncMappers.pointPayload(
        localRow: {
          'code': 'PZ-001', 'name': 'Piezo', 'type': 'inst',
          'typeLabel': 'Piezômetro', 'gpsLat': null, 'gpsLng': null,
          'status': 'nc', 'ncReported': 1, 'pointOrder': 2,
        },
        campaignExternalId: 'camp-ext-1',
      );
      expect(p['status'], 'justified_exception');
      expect(p['coord_source'], isNull);
    });
  });

  group('SyncMappers.recordPayload', () {
    test('includes weather and checklist when present', () {
      final weather = ['ensolarado', 'vento fraco'];
      final checklist = [
        {'label': 'EPI', 'checked': true},
        {'label': 'GPS', 'checked': false},
      ];

      final p = SyncMappers.recordPayload(
        localRow: {
          'status': 'done', 'ncReported': 0,
          'stabilization_completed_at': '2025-04-01T10:00:00.000Z',
          'stabilization_status': 'stabilized',
          'final_parameter_values_json': null,
          'stabilization_summary_json': null,
          'stabilization_exception_reason': null,
          'stabilization_exception_notes': null,
          'weather_conditions_json': jsonEncode(weather),
          'checklist_pop_json': jsonEncode(checklist),
          'obs_tags_json': jsonEncode(['odor']),
          'observations_text': 'Água turva',
        },
        pointExternalId: 'pt-ext-1',
        campaignExternalId: 'camp-ext-1',
        technicianExternalId: 'tech-ext-1',
        technicianName: 'Carlos',
      );

      expect(p['weather'], equals(weather));
      expect((p['checklist_pop'] as List).length, 2);
      expect(p['obs_tags'], contains('odor'));
      expect(p['observations'], 'Água turva');
    });

    test('emits null weather/checklist when columns are empty', () {
      final p = SyncMappers.recordPayload(
        localRow: {
          'status': 'done', 'ncReported': 0,
          'stabilization_completed_at': null,
          'stabilization_status': null,
          'final_parameter_values_json': null,
          'stabilization_summary_json': null,
          'stabilization_exception_reason': null,
          'stabilization_exception_notes': null,
          'weather_conditions_json': null,
          'checklist_pop_json': null,
          'obs_tags_json': null,
          'observations_text': null,
        },
        pointExternalId: 'pt-ext-1',
        campaignExternalId: 'camp-ext-1',
        technicianExternalId: null,
        technicianName: null,
      );

      expect(p['weather'], isNull);
      expect(p['checklist_pop'], isNull);
      expect(p['observations'], isNull);
    });

    test('builds nc block when ncReported == 1', () {
      final p = SyncMappers.recordPayload(
        localRow: {
          'status': 'nc', 'ncReported': 1,
          'ncMotive': 'Acesso negado',
          'stabilization_completed_at': null,
          'stabilization_status': null,
          'final_parameter_values_json': null,
          'stabilization_summary_json': null,
          'stabilization_exception_reason': null,
          'stabilization_exception_notes': null,
          'weather_conditions_json': null,
          'checklist_pop_json': null,
          'obs_tags_json': null,
          'observations_text': null,
        },
        pointExternalId: 'pt-ext-1',
        campaignExternalId: 'camp-ext-1',
        technicianExternalId: null,
        technicianName: null,
      );

      expect(p['nc'], isNotNull);
      expect(p['nc']['reported'], isTrue);
      expect(p['nc']['motive'], 'Acesso negado');
    });
  });

  group('SyncMappers.evidencePayload', () {
    test('sets file_uploaded:true and required fields', () {
      final at = DateTime.utc(2025, 4, 1, 9, 0);
      final p = SyncMappers.evidencePayload(
        externalId:       'ev-001',
        recordExternalId: 'rec-001',
        pointExternalId:  'pt-001',
        uploadKey:        's3/key/photo.jpg',
        mimeType:         'image/jpeg',
        sizeBytes:        204800,
        capturedAt:       at,
        gpsLat:           -22.76,
        gpsLng:           -47.15,
        caption:          'Panorâmica geral',
      );

      expect(p['file_uploaded'], isTrue);
      expect(p['file_key'], 's3/key/photo.jpg');
      expect(p['size_bytes'], 204800);
      expect(p['gps_lat'], closeTo(-22.76, 0.001));
      expect(p['caption'], 'Panorâmica geral');
    });
  });
}
