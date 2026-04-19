import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exceptions.dart';
import '../api/auth_service.dart';
import '../api/sync_mappers.dart';
import '../database/database_helper.dart';
import 'evidence_uploader.dart';
import 'sync_queue.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SYNC SERVICE
// Orchestrates batch push (POST /mobile/sync/batch) and pull (GET /mobile/sync/pull).
// Entry points:
//   - pushPending()  → drain the sync queue in batches
//   - pullUpdates()  → pull server-driven changes (new assigned campaigns, etc)
//   - syncNow()      → convenience: push then pull
//
// Also exposes a ValueNotifier so the UI can bind to sync state reactively.
// ─────────────────────────────────────────────────────────────────────────────

enum SyncPhase { idle, pushing, pulling, error }

class SyncState {
  final SyncPhase phase;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSuccessAt;
  final String? lastError;

  const SyncState({
    this.phase = SyncPhase.idle,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastSuccessAt,
    this.lastError,
  });

  SyncState copyWith({
    SyncPhase? phase,
    int? pendingCount,
    int? failedCount,
    DateTime? lastSuccessAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncState(
        phase:          phase ?? this.phase,
        pendingCount:   pendingCount ?? this.pendingCount,
        failedCount:    failedCount ?? this.failedCount,
        lastSuccessAt:  lastSuccessAt ?? this.lastSuccessAt,
        lastError:      clearError ? null : (lastError ?? this.lastError),
      );
}

class SyncService {
  SyncService._();
  static final instance = SyncService._();

  final ValueNotifier<SyncState> state = ValueNotifier(const SyncState());
  final ValueNotifier<bool> isOnline = ValueNotifier(false);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final _uuid = const Uuid();
  bool _draining = false;

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    await _refreshCounts();

    // Recover any in-flight items from a previous session.
    await SyncQueue.instance.recoverStaleInFlight();

    // Connectivity monitoring.
    final conn = Connectivity();
    final initial = await conn.checkConnectivity();
    isOnline.value = _isReallyOnline(initial);
    _connSub = conn.onConnectivityChanged.listen((results) {
      final nowOnline = _isReallyOnline(results);
      final was = isOnline.value;
      isOnline.value = nowOnline;
      if (!was && nowOnline) {
        // Transition offline → online: try immediately.
        unawaited(syncNow());
      }
    });

    // Periodic auto-sync.
    _timer = Timer.periodic(ApiConfig.autoSyncInterval, (_) {
      if (isOnline.value && AuthService.instance.isAuthenticated) {
        unawaited(syncNow());
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _connSub?.cancel();
  }

  bool _isReallyOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  // ── ENTRY POINTS ──────────────────────────────────────────────────────────

  /// Push then pull. Safe to call concurrently — internal guard prevents
  /// overlapping drains.
  Future<void> syncNow() async {
    if (!isOnline.value) return;
    if (!AuthService.instance.isAuthenticated) return;
    await pushPending();
    await pullUpdates();
    // Retry evidence photos that were queued while offline.
    unawaited(EvidenceUploader.instance.retryFailedUploads());
  }

  /// Drain the sync queue in batches of ApiConfig.maxBatchItems.
  Future<void> pushPending() async {
    if (_draining) return;
    _draining = true;

    state.value = state.value.copyWith(phase: SyncPhase.pushing, clearError: true);

    try {
      while (true) {
        final batch = await SyncQueue.instance
            .fetchPendingBatch(limit: ApiConfig.maxBatchItems);
        if (batch.isEmpty) break;

        await _sendBatch(batch);
        await _refreshCounts();
      }
      state.value = state.value.copyWith(
        phase: SyncPhase.idle,
        lastSuccessAt: DateTime.now(),
        clearError: true,
      );
    } on UpgradeRequiredException catch (e) {
      state.value = state.value.copyWith(
        phase: SyncPhase.error,
        lastError: e.message,
      );
    } on NetworkException catch (e) {
      state.value = state.value.copyWith(
        phase: SyncPhase.idle,
        lastError: e.message,
      );
    } catch (e) {
      state.value = state.value.copyWith(
        phase: SyncPhase.error,
        lastError: e.toString(),
      );
    } finally {
      _draining = false;
    }
  }

  /// Pulls server-driven changes using cursor-based pagination.
  /// Loops until the server returns fewer items than [ApiConfig.pullPageSize],
  /// signalling the last page.
  Future<void> pullUpdates({DateTime? since}) async {
    if (!isOnline.value) return;
    if (!AuthService.instance.isAuthenticated) return;

    state.value = state.value.copyWith(phase: SyncPhase.pulling, clearError: true);
    try {
      String? cursor;
      while (true) {
        final query = <String, String>{
          'limit': ApiConfig.pullPageSize.toString(),
        };
        if (since != null) query['since'] = since.toUtc().toIso8601String();
        if (cursor != null) query['cursor'] = cursor;

        final res = await ApiClient.instance.get(ApiConfig.syncPull, query: query);
        final items = (res['items'] as List?) ?? const [];

        for (final item in items) {
          await _applyServerItem(item as Map<String, dynamic>);
        }

        // Server signals last page either by returning fewer items than
        // requested, or by omitting / nulling the next_cursor field.
        final nextCursor = res['next_cursor'] as String?;
        if (nextCursor == null || items.length < ApiConfig.pullPageSize) break;
        cursor = nextCursor;
      }

      state.value = state.value.copyWith(
        phase: SyncPhase.idle,
        lastSuccessAt: DateTime.now(),
        clearError: true,
      );
    } on NetworkException {
      state.value = state.value.copyWith(phase: SyncPhase.idle);
    } catch (e) {
      state.value = state.value.copyWith(
        phase: SyncPhase.error,
        lastError: e.toString(),
      );
    }
  }

  // ── ENQUEUING FROM APP ACTIONS ────────────────────────────────────────────

  /// Call after a local campaign change (status, progress, finish).
  Future<void> enqueueCampaign(String campaignId) async {
    final row = await DatabaseHelper.instance.getCampaignRawById(campaignId);
    if (row == null) return;

    final externalId = await DatabaseHelper.instance
        .ensureCampaignExternalId(campaignId, () => _uuid.v4());

    final session = AuthService.instance.session;
    final payload = SyncMappers.campaignPayload(
      localRow: row,
      assignedUserExternalId: session?.technicianExternalId,
    );

    await SyncQueue.instance.enqueueUpsert(
      entity: SyncEntity.mobileCampaign,
      externalId: externalId,
      localId: campaignId,
      payload: payload,
    );
    await _refreshCounts();
  }

  /// Call after a local point change (status, GPS, NC).
  Future<void> enqueuePoint(String campaignId, String code) async {
    final row = await DatabaseHelper.instance.getPointRaw(campaignId, code);
    if (row == null) return;

    final campExternal = await DatabaseHelper.instance
        .ensureCampaignExternalId(campaignId, () => _uuid.v4());
    final ids = await DatabaseHelper.instance
        .ensurePointExternalIds(campaignId, code, () => _uuid.v4());

    final payload = SyncMappers.pointPayload(
      localRow: row,
      campaignExternalId: campExternal,
    );

    await SyncQueue.instance.enqueueUpsert(
      entity: SyncEntity.collectionPoint,
      externalId: ids.pointExternalId,
      localId: '$campaignId::$code',
      payload: payload,
    );
    await _refreshCounts();
  }

  /// Call after marking a point as done (stabilization complete + save).
  /// This enqueues the point AND the collection_record, because the record is
  /// what the backend uses to materialize the collection in the reports panel.
  Future<void> enqueuePointWithRecord(String campaignId, String code) async {
    await enqueuePoint(campaignId, code);

    final row = await DatabaseHelper.instance.getPointRaw(campaignId, code);
    if (row == null) return;

    // Only emit a record when the point is actually collected or NC — not while
    // still pending. Pending points have no meaningful record to ship yet.
    final status = row['status'] as String? ?? 'pending';
    if (status != 'done' && status != 'nc') return;

    final campExternal = await DatabaseHelper.instance
        .ensureCampaignExternalId(campaignId, () => _uuid.v4());
    final ids = await DatabaseHelper.instance
        .ensurePointExternalIds(campaignId, code, () => _uuid.v4());

    final session = AuthService.instance.session;
    final payload = SyncMappers.recordPayload(
      localRow:              row,
      pointExternalId:       ids.pointExternalId,
      campaignExternalId:    campExternal,
      technicianExternalId:  session?.technicianExternalId,
      technicianName:        session?.userName,
    );

    await SyncQueue.instance.enqueueUpsert(
      entity: SyncEntity.collectionRecord,
      externalId: ids.recordExternalId,
      localId: '$campaignId::$code::record',
      payload: payload,
    );
    await _refreshCounts();
  }

  // ── BATCH TRANSPORT ───────────────────────────────────────────────────────

  Future<void> _sendBatch(List<SyncQueueItem> batch) async {
    final ids = batch.where((e) => e.id != null).map((e) => e.id!).toList();
    await SyncQueue.instance.markInFlight(ids);

    final syncToken = _uuid.v4();
    final body = {
      'sync_token':          syncToken,
      'client_generated_at': DateTime.now().toUtc().toIso8601String(),
      'items': [
        for (var i = 0; i < batch.length; i++) batch[i].toBatchItem(i),
      ],
    };

    final logId = await _openSyncLog(syncToken, batch.length);

    try {
      final res = await ApiClient.instance.post(ApiConfig.syncBatch, body: body);

      final results = (res['results'] as List?) ?? const [];
      int processed = 0, failed = 0, conflict = 0, duplicated = 0;

      for (final raw in results) {
        final r = raw as Map<String, dynamic>;
        final idx = r['item_index'] as int? ?? -1;
        final status = r['status'] as String? ?? 'failed';
        if (idx < 0 || idx >= batch.length) continue;

        final item = batch[idx];
        switch (status) {
          case 'processed':
          case 'duplicated':
            if (status == 'duplicated') duplicated++; else processed++;
            await SyncQueue.instance.markProcessed(item.id!);
            await _onItemProcessed(item, r);
            break;
          case 'conflict':
            conflict++;
            // Server won the conflict. Apply server_payload to the local row
            // so the device reflects authoritative state, then drop the queue item.
            final serverPayload = r['server_payload'] as Map<String, dynamic>?;
            if (serverPayload != null) {
              await _applyConflictServerPayload(item, serverPayload,
                  serverVersion: r['server_version'] as int? ?? 1);
            }
            await SyncQueue.instance.markProcessed(item.id!);
            break;
          case 'failed':
          default:
            failed++;
            final reason = r['error_message'] as String? ?? 'unknown';
            await SyncQueue.instance.markFailed(item.id!, reason);
            break;
        }
      }

      await _closeSyncLog(logId,
          processed: processed,
          failed: failed,
          conflict: conflict,
          duplicated: duplicated,
          status: 'completed');
    } on ApiException catch (e) {
      // Whole-batch failure → put items back to pending (will retry next cycle).
      for (final item in batch) {
        if (item.id != null) {
          await SyncQueue.instance.markFailed(item.id!, 'http_${e.statusCode}: ${e.message}');
        }
      }
      await _closeSyncLog(logId,
          status: 'failed', errorMessage: e.toString());
      rethrow;
    } on NetworkException catch (e) {
      for (final item in batch) {
        if (item.id != null) {
          await SyncQueue.instance.markFailed(item.id!, e.message);
        }
      }
      await _closeSyncLog(logId, status: 'failed', errorMessage: e.message);
      rethrow;
    }
  }

  /// After a queue item is processed, update the local row's sync metadata.
  Future<void> _onItemProcessed(SyncQueueItem item, Map<String, dynamic> r) async {
    final serverVersion = r['server_version'] as int? ?? 1;

    switch (item.entity) {
      case SyncEntity.mobileCampaign:
        final localId = item.localId;
        if (localId != null) {
          await DatabaseHelper.instance.markEntitySynced(
            table: DatabaseHelper.tCampaigns,
            whereClause: 'id = ?',
            whereArgs: [localId],
            serverVersion: serverVersion,
          );
        }
        break;
      case SyncEntity.collectionPoint:
      case SyncEntity.collectionRecord:
        final localId = item.localId;
        if (localId != null) {
          final parts = localId.split('::');
          if (parts.length >= 2) {
            await DatabaseHelper.instance.markEntitySynced(
              table: DatabaseHelper.tFieldPoints,
              whereClause: 'campaignId = ? AND code = ?',
              whereArgs: [parts[0], parts[1]],
              serverVersion: serverVersion,
            );
          }
        }
        break;
      case SyncEntity.collectionEvidence:
        // evidence local bookkeeping is handled by EvidenceUploader.
        break;
    }
  }

  /// Applies the server's authoritative payload to the local SQLite row after
  /// a conflict. Server-version-wins is the policy; the queue item is dropped
  /// so the stale client change is not re-sent.
  Future<void> _applyConflictServerPayload(
    SyncQueueItem item,
    Map<String, dynamic> serverPayload, {
    required int serverVersion,
  }) async {
    switch (item.entity) {
      case SyncEntity.mobileCampaign:
        final localId = item.localId;
        if (localId == null) break;
        final db = await DatabaseHelper.instance.database;
        final patch = <String, dynamic>{
          'dirty': 0,
          'server_version': serverVersion,
          'last_synced_at': DateTime.now().toIso8601String(),
        };
        if (serverPayload['status']   != null) patch['status']   = serverPayload['status'];
        if (serverPayload['name']     != null) patch['name']     = serverPayload['name'];
        if (serverPayload['deadline'] != null) patch['deadline'] = serverPayload['deadline'];
        await db.update(DatabaseHelper.tCampaigns, patch,
            where: 'id = ?', whereArgs: [localId]);
        break;

      case SyncEntity.collectionPoint:
      case SyncEntity.collectionRecord:
        final localId = item.localId;
        if (localId == null) break;
        final parts = localId.split('::');
        if (parts.length < 2) break;
        final db = await DatabaseHelper.instance.database;
        final patch = <String, dynamic>{
          'dirty': 0,
          'server_version': serverVersion,
          'last_synced_at': DateTime.now().toIso8601String(),
        };
        if (serverPayload['status'] != null) patch['status'] = serverPayload['status'];
        await db.update(DatabaseHelper.tFieldPoints, patch,
            where: 'campaignId = ? AND code = ?',
            whereArgs: [parts[0], parts[1]]);
        break;

      case SyncEntity.collectionEvidence:
        break; // Evidence conflicts are rare; just drop and let server state stand.
    }
  }

  // ── PULL → LOCAL ──────────────────────────────────────────────────────────

  Future<void> _applyServerItem(Map<String, dynamic> item) async {
    final entity  = item['entity'] as String?;
    final payload = item['payload'] as Map<String, dynamic>? ?? {};
    final extId   = item['external_id'] as String?;
    final serverVersion = payload['server_version'] as int? ?? 1;

    switch (entity) {
      case 'mobile_campaign':
      case 'task_campaign_assignment':
        final row = <String, dynamic>{
          'code':           payload['code'] ?? '',
          'name':           payload['name'] ?? payload['project_name'] ?? '',
          'client':         payload['client_name'] ?? payload['client'] ?? '',
          'responsible':    payload['assigned_to_name'] ?? '',
          'deadline':       payload['deadline'] ?? '',
          'totalPoints':    (payload['expected_points'] as List?)?.length ?? 0,
          'donePoints':     0,
          'status':         'nova',
          'external_id':    extId,
          'server_version': serverVersion,
          'id':             extId,
        };
        await DatabaseHelper.instance.upsertCampaignFromServer(row);
        break;

      case 'campaign_cancelled':
        if (extId != null) {
          final db = await DatabaseHelper.instance.database;
          await db.update(
            DatabaseHelper.tCampaigns,
            {'status': 'cancelada', 'dirty': 0, 'server_version': serverVersion},
            where: 'external_id = ?',
            whereArgs: [extId],
          );
        }
        break;

      case 'collection_point':
        // Reconcile a server-side point into the local field_points table.
        // Only applies when the local row is NOT dirty (i.e., no unsent edits).
        if (extId == null) break;
        await _reconcilePoint(extId, payload, serverVersion);
        break;

      case 'collection_record':
        // Mark the associated point as done if the server says the record is
        // confirmed — useful after another device collected the same point.
        if (extId == null) break;
        await _reconcileRecord(extId, payload, serverVersion);
        break;

      default:
        debugPrint('[SyncService] Unknown pull entity: $entity');
    }
  }

  Future<void> _reconcilePoint(
    String pointExternalId,
    Map<String, dynamic> payload,
    int serverVersion,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseHelper.tFieldPoints,
      where: 'external_id = ?',
      whereArgs: [pointExternalId],
    );
    if (rows.isEmpty) return; // point not known locally — ignore

    final local = rows.first;
    final localDirty = (local['dirty'] as int? ?? 0) == 1;
    final localVer   = local['server_version'] as int? ?? 0;

    // Server-wins only when server has newer version and local has no unsent edits.
    if (localDirty || serverVersion <= localVer) return;

    final patch = <String, dynamic>{
      'server_version': serverVersion,
      'last_synced_at': DateTime.now().toIso8601String(),
      'dirty': 0,
    };
    if (payload['status']  != null) patch['status']  = payload['status'];
    if (payload['gps_lat'] != null) patch['gpsLat']  = payload['gps_lat'];
    if (payload['gps_lng'] != null) patch['gpsLng']  = payload['gps_lng'];

    await db.update(
      DatabaseHelper.tFieldPoints,
      patch,
      where: 'external_id = ?',
      whereArgs: [pointExternalId],
    );
  }

  Future<void> _reconcileRecord(
    String recordExternalId,
    Map<String, dynamic> payload,
    int serverVersion,
  ) async {
    // If the record is confirmed on server, mark the point as done locally.
    final recordStatus = payload['status'] as String?;
    if (recordStatus != 'confirmed' && recordStatus != 'done') return;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseHelper.tFieldPoints,
      where: 'record_external_id = ?',
      whereArgs: [recordExternalId],
    );
    if (rows.isEmpty) return;

    final local = rows.first;
    final localDirty = (local['dirty'] as int? ?? 0) == 1;
    if (localDirty) return; // preserve unsent local edits

    await db.update(
      DatabaseHelper.tFieldPoints,
      {
        'status':           'done',
        'server_version':   serverVersion,
        'last_synced_at':   DateTime.now().toIso8601String(),
        'dirty':            0,
      },
      where: 'record_external_id = ?',
      whereArgs: [recordExternalId],
    );
  }

  // ── COUNTS + LOG ──────────────────────────────────────────────────────────

  Future<void> _refreshCounts() async {
    final pending = await SyncQueue.instance.pendingCount();
    final failed  = await SyncQueue.instance.failedCount();
    state.value = state.value.copyWith(
      pendingCount: pending,
      failedCount: failed,
    );
  }

  Future<int> _openSyncLog(String token, int totalItems) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert(DatabaseHelper.tSyncLog, {
      'sync_token':       token,
      'started_at':       DateTime.now().toIso8601String(),
      'items_total':      totalItems,
      'items_processed':  0,
      'items_failed':     0,
      'items_conflict':   0,
      'items_duplicated': 0,
      'status':           'in_progress',
    });
  }

  Future<void> _closeSyncLog(
    int logId, {
    int processed = 0,
    int failed = 0,
    int conflict = 0,
    int duplicated = 0,
    required String status,
    String? errorMessage,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      DatabaseHelper.tSyncLog,
      {
        'finished_at':      DateTime.now().toIso8601String(),
        'items_processed':  processed,
        'items_failed':     failed,
        'items_conflict':   conflict,
        'items_duplicated': duplicated,
        'status':           status,
        'error_message':    errorMessage,
      },
      where: 'id = ?',
      whereArgs: [logId],
    );
  }
}
