import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ecoflowapp/sync/sync_queue.dart';
import 'package:ecoflowapp/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SyncQueue unit tests
// Uses sqflite_common_ffi to run against an in-memory SQLite database.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Reset the singleton so each test gets a fresh in-memory DB.
    await DatabaseHelper.instance.resetDatabase();
  });

  group('SyncQueue — enqueueUpsert', () {
    test('inserts a new pending item', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'Test Campaign'},
      );

      final count = await SyncQueue.instance.pendingCount();
      expect(count, 1);
    });

    test('coalesces duplicate pending item and updates payload', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'v1'},
      );
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'v2'},
      );

      final count = await SyncQueue.instance.pendingCount();
      expect(count, 1, reason: 'Should coalesce into a single pending row');

      final batch = await SyncQueue.instance.fetchPendingBatch();
      expect(batch.first.payload['name'], 'v2');
      expect(batch.first.clientVersion, 2);
    });

    test('skips enqueue when payload is identical (idempotent no-op)', () async {
      const payload = {'name': 'Same'};
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: payload,
      );
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: payload,
      );

      final batch = await SyncQueue.instance.fetchPendingBatch();
      expect(batch.length, 1);
      expect(batch.first.clientVersion, 1,
          reason: 'Version should not increment on no-op');
    });
  });

  group('SyncQueue — dependency ordering', () {
    test('returns items in campaign → point → record → evidence order', () async {
      // Insert in reverse order to verify sorting.
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.collectionEvidence,
        externalId: 'ev-001',
        payload: {'caption': 'photo'},
      );
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.collectionRecord,
        externalId: 'rec-001',
        payload: {'value': 7.2},
      );
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.collectionPoint,
        externalId: 'pt-001',
        payload: {'code': 'NAS-001'},
      );
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'Campaign'},
      );

      final batch = await SyncQueue.instance.fetchPendingBatch();
      final entities = batch.map((e) => e.entity).toList();

      expect(entities[0], SyncEntity.mobileCampaign);
      expect(entities[1], SyncEntity.collectionPoint);
      expect(entities[2], SyncEntity.collectionRecord);
      expect(entities[3], SyncEntity.collectionEvidence);
    });
  });

  group('SyncQueue — backoff exponential', () {
    test('failed item with attempts=0 is NOT promoted immediately', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'X'},
      );
      final batch = await SyncQueue.instance.fetchPendingBatch();
      await SyncQueue.instance.markInFlight([batch.first.id!]);
      await SyncQueue.instance.markFailed(batch.first.id!, 'timeout');

      // Immediately after failure, item is in back-off (2^0 = 1 min).
      // fetchPendingBatch should not promote it yet.
      final afterFail = await SyncQueue.instance.fetchPendingBatch();
      expect(afterFail, isEmpty,
          reason: 'Item should be in back-off and not returned');
    });

    test('quarantined item (attempts >= kMaxAttempts) counts as failed', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'X'},
      );
      final batch = await SyncQueue.instance.fetchPendingBatch();
      final id = batch.first.id!;
      await SyncQueue.instance.markInFlight([id]);

      // Simulate kMaxAttempts failures.
      for (var i = 0; i < SyncQueue.kMaxAttempts; i++) {
        await SyncQueue.instance.markFailed(id, 'err $i');
      }

      final failedCount = await SyncQueue.instance.failedCount();
      expect(failedCount, 1,
          reason: 'Item with max attempts should appear in failedCount');
    });

    test('retryFailed(reset:true) puts quarantined item back to pending', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'X'},
      );
      final batch = await SyncQueue.instance.fetchPendingBatch();
      final id = batch.first.id!;
      await SyncQueue.instance.markInFlight([id]);
      for (var i = 0; i < SyncQueue.kMaxAttempts; i++) {
        await SyncQueue.instance.markFailed(id, 'err');
      }

      await SyncQueue.instance.retryFailed(reset: true);
      final pending = await SyncQueue.instance.pendingCount();
      expect(pending, 1);
    });
  });

  group('SyncQueue — lifecycle', () {
    test('markProcessed removes item from pending', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'X'},
      );
      final batch = await SyncQueue.instance.fetchPendingBatch();
      await SyncQueue.instance.markInFlight([batch.first.id!]);
      await SyncQueue.instance.markProcessed(batch.first.id!);

      expect(await SyncQueue.instance.pendingCount(), 0);
    });

    test('recoverStaleInFlight puts in-flight items back to pending', () async {
      await SyncQueue.instance.enqueueUpsert(
        entity: SyncEntity.mobileCampaign,
        externalId: 'camp-001',
        payload: {'name': 'X'},
      );
      final batch = await SyncQueue.instance.fetchPendingBatch();
      await SyncQueue.instance.markInFlight([batch.first.id!]);

      expect(await SyncQueue.instance.pendingCount(), 0);

      await SyncQueue.instance.recoverStaleInFlight();
      expect(await SyncQueue.instance.pendingCount(), 1);
    });
  });
}
