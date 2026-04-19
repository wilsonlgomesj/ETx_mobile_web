import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SYNC QUEUE
// SQLite-backed queue of pending sync operations.
//
// v2 changes:
//   - Exponential backoff: failed items re-enter the pending batch only after
//     their back-off window elapses (2^attempts minutes, max 60 min).
//   - Max-attempts cap (kMaxAttempts = 5): items that have failed 5+ times are
//     quarantined and require an explicit retryFailed(reset: true) call.
//   - fetchPendingBatch also picks up retryable failed items so callers don't
//     need two separate calls.
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

  /// Seconds until this item is eligible for retry.
  /// Returns 0 if already eligible (or not failed).
  int secondsUntilRetry() {
    if (status != SyncItemStatus.failed) return 0;
    final backoffSecs = _backoffSecondsFor(attempts);
    final eligibleAt = updatedAt.add(Duration(seconds: backoffSecs));
    final remaining = eligibleAt.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  static int _backoffSecondsFor(int attempts) {
    // 2^attempts minutes, capped at 60 min (3600 s).
    final minutes = (1 << attempts.clamp(0, 6)); // 1,2,4,8,16,32,64 → cap 60
    return (minutes > 60 ? 60 : minutes) * 60;
  }
}

class SyncQueue {
  SyncQueue._();
  static final instance = SyncQueue._();

  /// Items that fail kMaxAttempts times are quarantined; call
  /// retryFailed(reset: true) to give them another chance.
  static const kMaxAttempts = 5;

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ── ENQUEUE ───────────────────────────────────────────────────────────────

  /// Enqueues an upsert. If a pending item for the same (entity, external_id)
  /// exists, it is replaced (coalescing) with the latest payload and the
  /// client_version is incremented.
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

    final existing = await db.query(
      DatabaseHelper.tSyncQueue,
      where: "entity = ? AND external_id = ? AND status = 'pending'",
      whereArgs: [entity.wire, externalId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final prev = SyncQueueItem.fromRow(existing.first);
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

  /// Returns up to [limit] items ready to ship, in dependency order:
  ///   campaigns → points → records → evidences
  ///
  /// Includes:
  ///   (a) pending items
  ///   (b) failed items whose back-off window has elapsed AND attempts < kMaxAttempts
  ///
  /// Failed items whose back-off is satisfied are promoted to pending in the
  /// same DB write so the caller sees a uniform status.
  Future<List<SyncQueueItem>> fetchPendingBatch({int limit = 50}) async {
    final db = await _db;

    // Promote retryable failed items → pending before the main query.
    await _promoteRetryableItems(db);

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

  /// Re-queues failed items whose back-off window has expired and that are
  /// below the max-attempts cap. Called automatically inside fetchPendingBatch.
  Future<int> _promoteRetryableItems(Database db) async {
    final now = DateTime.now();
    final rows = await db.rawQuery(
      '''
      SELECT id, attempts, updated_at
      FROM ${DatabaseHelper.tSyncQueue}
      WHERE status = 'failed' AND attempts < ?
      ''',
      [kMaxAttempts],
    );

    final idsToPromote = <int>[];
    for (final r in rows) {
      final attempts = r['attempts'] as int? ?? 0;
      final updatedAt = DateTime.parse(r['updated_at'] as String);
      final backoffSecs = SyncQueueItem._backoffSecondsFor(attempts);
      final eligibleAt = updatedAt.add(Duration(seconds: backoffSecs));
      if (now.isAfter(eligibleAt)) {
        idsToPromote.add(r['id'] as int);
      }
    }

    if (idsToPromote.isNotEmpty) {
      final placeholders = List.filled(idsToPromote.length, '?').join(',');
      await db.rawUpdate(
        '''
        UPDATE ${DatabaseHelper.tSyncQueue}
        SET status = 'pending', updated_at = ?
        WHERE id IN ($placeholders)
        ''',
        [now.toIso8601String(), ...idsToPromote],
      );
    }
    return idsToPromote.length;
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
    // Only count quarantined (max-attempts exceeded) items as "failed".
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM ${DatabaseHelper.tSyncQueue} WHERE status = 'failed' AND attempts >= ?",
      [kMaxAttempts],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Count of items still in failed state (including those in back-off).
  Future<int> totalFailedCount() async {
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

  /// Resets quarantined items so they'll be retried. Pass reset:true to also
  /// clear the attempts counter (giving them a fresh start).
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
