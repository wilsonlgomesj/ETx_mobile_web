import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exceptions.dart';
import '../api/sync_mappers.dart';
import '../database/database_helper.dart';
import 'sync_queue.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EVIDENCE UPLOADER
// Handles the 3-step flow for uploading collection photos to S3-backed storage:
//   1) POST /mobile/evidences/upload-url  → server returns a presigned PUT URL
//   2) PUT file bytes directly to S3
//   3) POST /mobile/evidences/:id/confirm → server validates hash and records
//      the evidence as uploaded
//
// After confirmation, the evidence is also enqueued in the sync queue so the
// next batch includes it (linked to its collection_record).
// ─────────────────────────────────────────────────────────────────────────────

class EvidenceUploader {
  EvidenceUploader._();
  static final instance = EvidenceUploader._();

  /// Registers a local photo file, uploads it, and enqueues the evidence for
  /// eventual inclusion in the next sync batch.
  ///
  /// [localPath] must point to an existing file on disk (jpg/png).
  /// [recordExternalId] / [pointExternalId] come from ensurePointExternalIds()
  /// and identify which collection_record the photo belongs to.
  Future<EvidenceUploadResult> uploadAndRegister({
    required String localPath,
    required String recordExternalId,
    required String pointExternalId,
    required String externalId,
    int? fieldPointId,
    DateTime? capturedAt,
    double? gpsLat,
    double? gpsLng,
    String? caption,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw ArgumentError('Arquivo não encontrado: $localPath');
    }
    final bytes = await file.readAsBytes();
    final size = bytes.length;
    final mimeType = _mimeFor(localPath);
    final hash = sha256.convert(bytes).toString();
    final takenAt = capturedAt ?? DateTime.now();

    final db = await DatabaseHelper.instance.database;

    // 1) Register local row as pending.
    await db.insert(
      DatabaseHelper.tEvidences,
      {
        'external_id':        externalId,
        'field_point_id':     fieldPointId,
        'record_external_id': recordExternalId,
        'local_file_path':    localPath,
        'mime_type':          mimeType,
        'size_bytes':         size,
        'sha256':             hash,
        'captured_at':        takenAt.toIso8601String(),
        'gps_lat':            gpsLat?.toString(),
        'gps_lng':            gpsLng?.toString(),
        'caption':             caption,
        'upload_status':      'pending',
        'attempts':           0,
        'created_at':         DateTime.now().toIso8601String(),
        'updated_at':         DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 2) Request presigned URL.
    final urlRes = await ApiClient.instance.post(
      ApiConfig.evidenceUploadUrl,
      body: {
        'external_id': externalId,
        'mime_type':   mimeType,
        'size_bytes':  size,
        'sha256':      hash,
      },
    );
    final uploadUrl = urlRes['upload_url'] as String;
    final uploadKey = urlRes['upload_key'] as String;

    // 3) PUT bytes directly to S3.
    final putRes = await ApiClient.instance.rawPut(
      uploadUrl,
      bytes: bytes,
      contentType: mimeType,
    );
    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      await _markUploadFailed(externalId, 'S3 PUT ${putRes.statusCode}');
      throw ApiException(putRes.statusCode, 'Falha no upload do arquivo');
    }

    // 4) Confirm upload on backend.
    final confirmRes = await ApiClient.instance.post(
      ApiConfig.evidenceConfirm(externalId),
      body: {
        'upload_key':         uploadKey,
        'sha256':             hash,
        'actual_size_bytes':  size,
      },
    );
    final remoteUrl = confirmRes['file_url'] as String?;

    // 5) Update local row as confirmed.
    await db.update(
      DatabaseHelper.tEvidences,
      {
        'upload_status': 'confirmed',
        'upload_key':    uploadKey,
        'remote_url':    remoteUrl,
        'updated_at':    DateTime.now().toIso8601String(),
      },
      where: 'external_id = ?',
      whereArgs: [externalId],
    );

    // 6) Enqueue the evidence payload so it's linked to the record in the
    //    next sync batch.
    final payload = SyncMappers.evidencePayload(
      externalId:       externalId,
      recordExternalId: recordExternalId,
      pointExternalId:  pointExternalId,
      uploadKey:        uploadKey,
      mimeType:         mimeType,
      sizeBytes:        size,
      capturedAt:       takenAt,
      gpsLat:           gpsLat,
      gpsLng:           gpsLng,
      caption:          caption,
    );
    await SyncQueue.instance.enqueueUpsert(
      entity: SyncEntity.collectionEvidence,
      externalId: externalId,
      payload: payload,
    );

    return EvidenceUploadResult(
      externalId: externalId,
      uploadKey:  uploadKey,
      remoteUrl:  remoteUrl,
      sizeBytes:  size,
      sha256:     hash,
    );
  }

  /// Retries failed uploads (e.g., after connectivity recovery).
  Future<void> retryFailedUploads() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseHelper.tEvidences,
      where: "upload_status = ? AND attempts < ?",
      whereArgs: ['failed', 5],
    );
    for (final r in rows) {
      final path = r['local_file_path'] as String?;
      if (path == null || !File(path).existsSync()) continue;
      try {
        await uploadAndRegister(
          localPath:        path,
          externalId:       r['external_id'] as String,
          recordExternalId: r['record_external_id'] as String,
          pointExternalId:  r['record_external_id'] as String, // best-effort
          fieldPointId:     r['field_point_id'] as int?,
          capturedAt: r['captured_at'] != null
              ? DateTime.parse(r['captured_at'] as String)
              : null,
          caption: r['caption'] as String?,
        );
      } catch (e) {
        debugPrint('Evidence retry failed for ${r['external_id']}: $e');
      }
    }
  }

  Future<void> _markUploadFailed(String externalId, String error) async {
    final db = await DatabaseHelper.instance.database;
    await db.rawUpdate(
      '''
      UPDATE ${DatabaseHelper.tEvidences}
      SET upload_status = 'failed',
          attempts = attempts + 1,
          last_error = ?,
          updated_at = ?
      WHERE external_id = ?
      ''',
      [error, DateTime.now().toIso8601String(), externalId],
    );
  }

  String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}

class EvidenceUploadResult {
  final String externalId;
  final String uploadKey;
  final String? remoteUrl;
  final int sizeBytes;
  final String sha256;

  const EvidenceUploadResult({
    required this.externalId,
    required this.uploadKey,
    this.remoteUrl,
    required this.sizeBytes,
    required this.sha256,
  });
}
