import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SYNC QUEUE
// SQLite-backed queue of pending sync operations.
// Each entry carries:
//   - entity type (mobile_campaign | collection_point | collection_record |
//                  collection_evidence)
//   - external_id (stable id shared between app and backend)
//   - operation (upsert | soft_delete)
//   - canonical payload JSON
//   - payload_hash (SHA-256 for idempotency)
//   - client_version (incremented on every mutation of the same external_id)
//   - client_updated_at
//   - status (pending | in_flight | failed)
//
// The queue is the authoritative source of what still needs to go up.
// ─────────────────────────────────────────────────────────────────────────────

enum SyncEntity {
  mobileCampaign('mobile_campaign'),
  collectionPoint('collection_point'),
  collectionRecord('collection_record'),
  collectionEvidence('collection_evidence');

  final String wire;
  const SyncEntity(this.wire);
}

enum SyncOperation {
  upsert('upsert'),
  softDelete('soft_delete');

  final String wire;
  const SyncOperation(this.wire);
}

enum SyncItemStatus {
  pending('pending'),
  inFlight('in_flight'),
  failed('failed'),
  done('done');

  final String wire;
  const SyncItemStatus(this.wire);

  static SyncItemStatus fromWire(String s) =>
      SyncItemStatus.values.firstWhere((e) => e.wire == s,
          orElse: () => SyncItemStatus.pending);
}

class SyncQueueItem {
  final int? id;
  final SyncEntity entity;
  final String externalId;
  final String? localId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final String payloadHash;
  final int clientVersion;
  final DateTime clientUpdatedAt;
  final SyncItemStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SyncQueueItem({
    this.id,
    required this.entity,
    required this.externalId,
    this.localId,
    required this.operation,
    required this.payload,
    required this.payloadHash,
    required this.clientVersion,
    required this.clientUpdatedAt,
    this.status = SyncItemStatus.pending,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'entity':            entity.wire,
        'external_id':       externalId,
        'local_id':          localId,
        'operation':         operation.wire,
        'payload_json':      jsonEncode(payload),
        'payload_hash':      payloadHash,
        'client_version':    clientVersion,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
        'status':            status.wire,
        'attempts':          attempts,
        'last_error':        lastError,
        'created_at':        createdAt.toIso8601String(),
        'updated_at':        updatedAt.toIso8601String(),
      };

  static SyncQueueItem fromRow(Map<String, dynamic> r) => SyncQueueItem(
        id:             r['id'] as int?,
        entity:         SyncEntity.values.firstWhere(
                          (e) => e.wire == r['entity'],
                          orElse: () => SyncEntity.collectionRecord,
                        ),
        externalId:     r['external_id'] as String,
        localId:        r['local_id'] as String?,
        operation:      SyncOperation.values.firstWhere(
                          (e) => e.wire == r['operation'],
                          orElse: () => SyncOperation.upsert,
                        ),
        payload:        jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
        payloadHash:    r['payload_hash'] as String,
        clientVersion:  r['client_version'] as int,
        clientUpdatedAt:DateTime.parse(r['client_updated_at'] as String),
        status:         SyncItemStatus.fromWire(r['status'] as String),
        attempts:       r['attempts'] as int? ?? 0,
        lastError:      r['last_error'] as String?,
        createdAt:      DateTime.parse(r['created_at'] as String),
        updatedAt:      DateTime.parse(r['updated_at'] as String),
      );

  /// Wire format expected by POST /api/v1/mobile/sync/batch.
  Map<String, dynamic> toBatchItem(int itemIndex) => {
        'item_index':        itemIndex,
        'entity':            entity.wire,
        'external_id':       externalId,
        'operation':         operation.wire,
        'client_updated_at': clientUpdatedAt.toIso8601String(),
        'client_version':    clientVersion,
        'payload':           payload,
      };
}

class SyncQueue {
  SyncQueue._();
  static final instance = SyncQueue._();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ── ENQUEUE ───────────────────────────────────────────────────────────────

  /// Enqueues an upsert. If a pending item for the same (entity, external_id)
  /// exists, it is replaced (coalescing) with the latest payload and the
  /// client_version is incremented. This matches last-write-wins semantics
  /// while keeping the queue small.
  Future<void> enqueueUpsert({
    required SyncEntity entity,
    required String externalId,
    String? localId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final canonical = _canonicalize(payload);
    final hash = sha256.convert(utf8.encode(jsonEncode(canonical))).toString();

    // Is there an existing pending item?
    final existing = await db.query(
      DatabaseHelper.tSyncQueue,
      where: "entity = ? AND external_id = ? AND status = 'pending'",
      whereArgs: [entity.wire, externalId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final prev = SyncQueueItem.fromRow(existing.first);
      // Skip if payload didn't actually change (idempotent no-op).
      if (prev.payloadHash == hash) return;

      await db.update(
        DatabaseHelper.tSyncQueue,
        {
          'local_id':          localId ?? prev.localId,
          'payload_json':      jsonEncode(canonical),
          'payload_hash':      hash,
          'client_version':    prev.clientVersion + 1,
          'client_updated_at': now.toIso8601String(),
          'attempts':          0,
          'last_error':        null,
          'updated_at':        now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [prev.id],
      );
      return;
    }

    // No pending item — check latest known client_version for this external_id
    // (even from done items) so we keep monotonic version numbers.
    final lastVersionRow = await db.rawQuery(
      '''
      SELECT MAX(client_version) AS v
      FROM ${DatabaseHelper.tSyncQueue}
      WHERE entity = ? AND external_id = ?
      ''',
      [entity.wire, externalId],
    );
    final nextVersion = ((lastVersionRow.first['v'] as int?) ?? 0) + 1;

    await db.insert(DatabaseHelper.tSyncQueue, {
      'entity':            entity.wire,
      'external_id':       externalId,
      'local_id':          localId,
      'operation':         SyncOperation.upsert.wire,
      'payload_json':      jsonEncode(canonical),
      'payload_hash':      hash,
      'client_version':    nextVersion,
      'client_updated_at': now.toIso8601String(),
      'status':            SyncItemStatus.pending.wire,
      'attempts':          0,
      'created_at':        now.toIso8601String(),
      'updated_at':        now.toIso8601String(),
    });
  }

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Returns up to [limit] pending items ordered by created_at ASC (oldest first).
  /// Items are also ordered so dependencies ship first:
  ///   campaigns → points → records → evidences
  Future<List<SyncQueueItem>> fetchPendingBatch({int limit = 50}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT *,
        CASE entity
          WHEN 'mobile_campaign'     THEN 1
          WHEN 'collection_point'    THEN 2
          WHEN 'collection_record'   THEN 3
          WHEN 'collection_evidence' THEN 4
          ELSE 5
        END AS sort_order
      FROM ${DatabaseHelper.tSyncQueue}
      WHERE status = 'pending'
      ORDER BY sort_order ASC, created_at ASC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(SyncQueueItem.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM ${DatabaseHelper.tSyncQueue} WHERE status = 'pending'",
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> failedCount() async {
    final db = await _db;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM ${DatabaseHelper.tSyncQueue} WHERE status = 'failed'",
    );
    return (r.first['c'] as int?) ?? 0;
  }

  // ── TRANSITIONS ───────────────────────────────────────────────────────────

  Future<void> markInFlight(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE ${DatabaseHelper.tSyncQueue}
      SET status = ?, updated_at = ?
      WHERE id IN ($placeholders)
      ''',
      [SyncItemStatus.inFlight.wire, DateTime.now().toIso8601String(), ...ids],
    );
  }

  Future<void> markProcessed(int id) async {
    final db = await _db;
    await db.update(
      DatabaseHelper.tSyncQueue,
      {
        'status':     SyncItemStatus.done.wire,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(int id, String error) async {
    final db = await _db;
    await db.rawUpdate(
      '''
      UPDATE ${DatabaseHelper.tSyncQueue}
      SET status = ?, attempts = attempts + 1, last_error = ?, updated_at = ?
      WHERE id = ?
      ''',
      [SyncItemStatus.failed.wire, error, DateTime.now().toIso8601String(), id],
    );
  }

  /// Puts failed items back in pending state, resetting attempts if [reset] is true.
  Future<void> retryFailed({bool reset = false}) async {
    final db = await _db;
    await db.update(
      DatabaseHelper.tSyncQueue,
      {
        'status':     SyncItemStatus.pending.wire,
        if (reset) 'attempts': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'status = ?',
      whereArgs: [SyncItemStatus.failed.wire],
    );
  }

  /// Puts stale in-flight items back in pending (e.g., on app restart).
  Future<void> recoverStaleInFlight() async {
    final db = await _db;
    await db.update(
      DatabaseHelper.tSyncQueue,
      {
        'status':     SyncItemStatus.pending.wire,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'status = ?',
      whereArgs: [SyncItemStatus.inFlight.wire],
    );
  }

  /// Removes done items older than [keepDuration]. Keeps history short.
  Future<void> pruneDone({Duration keepDuration = const Duration(days: 7)}) async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(keepDuration).toIso8601String();
    await db.delete(
      DatabaseHelper.tSyncQueue,
      where: 'status = ? AND updated_at < ?',
      whereArgs: [SyncItemStatus.done.wire, cutoff],
    );
  }

  // ── INTERNAL ──────────────────────────────────────────────────────────────

  /// Canonicalize a map: sort keys recursively so the hash is stable
  /// regardless of insertion order.
  static dynamic _canonicalize(dynamic v) {
    if (v is Map) {
      final sorted = <String, dynamic>{};
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      for (final k in keys) {
        sorted[k] = _canonicalize(v[k]);
      }
      return sorted;
    }
    if (v is List) {
      return v.map(_canonicalize).toList();
    }
    return v;
  }
}
