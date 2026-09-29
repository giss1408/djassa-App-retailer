import 'dart:math';

import 'package:djassa_merchant/core/data/sale_dao.dart';
import 'package:djassa_merchant/core/data/sale_repository.dart';
import 'package:djassa_merchant/core/data/sync_service.dart';
import 'package:djassa_merchant/core/model/money.dart';
import 'package:djassa_merchant/core/model/sale.dart';
import 'package:djassa_merchant/core/net/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fake_api.dart';
import 'support/test_db.dart';

/// Polls until the queue has a row whose backoff has elapsed.
///
/// Backoff is real time, so a test that wants to observe a successful retry has
/// to wait for it. The base backoff is 1ms here, so this returns almost at once.
Future<void> _waitUntilDue(SaleDao dao) async {
  for (var i = 0; i < 200; i++) {
    if ((await dao.pendingBatch()).isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('no sale became due for retry');
}

void main() {
  late FakeDjassaServer server;
  late SaleDao dao;
  late SyncService sync;
  late SaleRepository repo;
  late Future<void> Function() closeDb;

  setUp(() async {
    server = FakeDjassaServer();
    final db = await openTestDatabase();
    closeDb = db.close;
    dao = SaleDao(db.db);

    final client = ApiClient(
      inner: server.client(),
      tokenProvider: () async => FakeDjassaServer.validJwt(),
      baseUrl: 'https://api.test.invalid',
    );
    sync = SyncService(
      client: client,
      dao: dao,
      // Deterministic backoff so tests never depend on wall-clock jitter.
      random: Random(1),
      baseBackoff: const Duration(milliseconds: 1),
    );
    repo = SaleRepository(
      dao: dao,
      syncService: sync,
      // Each test drives sync explicitly; a background attempt would race the
      // assertions about what the server saw and when.
      syncAfterRecording: false,
    );
  });

  tearDown(() async => closeDb());

  Future<Sale> record(int amount, {String currency = 'XOF'}) => repo.recordSale(
        amount: Money.fromMajor(amount, currency),
        type: 'sale',
      );

  group('recording a sale', () {
    test('is durable before the network is touched', () async {
      // The server is unreachable, yet the sale must still be recorded.
      server.failWith = http.ClientException('no route to host');

      final sale = await record(1500);

      expect(sale.localId, isNotNull);
      expect(sale.syncState, SaleSyncState.pending);
      expect(await dao.pendingCount(), 1);
    });

    test('generates a unique, unguessable key within the backend bounds',
        () async {
      final keys = <String>{};
      for (var i = 0; i < 200; i++) {
        keys.add(newIdempotencyKey(Random.secure()));
      }
      expect(keys.length, 200, reason: 'keys must not collide');
      for (final key in keys) {
        expect(key.length, greaterThanOrEqualTo(8));
        expect(key.length, lessThanOrEqualTo(128));
        // Must be safe in a JSON string and an HTTP header.
        expect(key, matches(r'^[A-Za-z0-9_\-]+$'));
      }
    });

    test('refuses a zero or negative amount before spending a round trip',
        () async {
      expect(
        () => repo.recordSale(
          amount: Money.fromMajor(0, 'XOF'),
          type: 'sale',
        ),
        throwsArgumentError,
      );
    });
  });

  group('sync', () {
    test('sends the whole queue in ONE request, not one per sale', () async {
      server.failWith = http.ClientException('offline');
      for (var i = 0; i < 12; i++) {
        await record(100 + i);
      }
      expect(await dao.pendingCount(), 12);

      server.failWith = null;
      final outcome = await sync.syncOnce();

      expect(outcome.sent, 12);
      expect(await dao.pendingCount(), 0);
      // The bandwidth guarantee: 12 sales cost one round trip.
      expect(server.receivedBatches.length, 1);
      expect(
        (server.receivedBatches.single['operations'] as List).length,
        12,
      );
    });

    test('never exceeds the backend 50-operation batch limit', () async {
      server.failWith = http.ClientException('offline');
      for (var i = 0; i < 120; i++) {
        await record(10 + i);
      }
      server.failWith = null;

      final outcome = await sync.drain();

      expect(outcome.sent, 120);
      expect(await dao.pendingCount(), 0);
      for (final batch in server.receivedBatches) {
        expect((batch['operations'] as List).length, lessThanOrEqualTo(50));
      }
      // 120 sales in 3 batches, not 120 requests.
      expect(server.receivedBatches.length, 3);
    });

    test('names neither the user nor the venue, so the server decides both',
        () async {
      await record(500);
      await sync.syncOnce();

      final op = (server.receivedBatches.single['operations'] as List).single
          as Map<String, Object?>;
      // The fix behind the merged stream: a client cannot assert which business
      // a sale belongs to (`app/api/sales.py`).
      expect(op.containsKey('user_id'), isFalse);
      expect(op.containsKey('merchant_id'), isFalse);
      expect(op.containsKey('venue_id'), isFalse);
      expect(op.keys.toSet(), {
        'amount',
        'currency',
        'type',
        'occurred_at',
        'idempotency_key',
      });
    });

    test('sends the day the merchant made the sale, not the day it synced',
        () async {
      // Queued while offline, sent later: the backend keeps both timestamps and
      // the merchant's daily total must use the earlier one.
      server.failWith = http.ClientException('offline');
      final sale = await record(700);
      server.failWith = null;
      await sync.drain();

      final op = (server.receivedBatches.last['operations'] as List).single
          as Map<String, Object?>;
      // Compared against the stored row, not the in-memory one: the ledger keeps
      // millisecond precision, so a microsecond difference here is storage
      // granularity rather than a wrong timestamp.
      final stored = (await dao.recent()).single;
      expect(
        DateTime.parse(op['occurred_at']! as String).toUtc(),
        stored.recordedAt.toUtc(),
      );
      expect(sale.idempotencyKey, stored.idempotencyKey);
    });

    test('a sale the server accepts carries back its server id', () async {
      await record(900);
      await sync.syncOnce();

      final stored = (await dao.recent()).single;
      expect(stored.syncState, SaleSyncState.synced);
      expect(stored.serverId, isNotNull);
    });

    test('sends XOF amounts without a bogus minor unit', () async {
      await record(1500, currency: 'XOF');
      await sync.syncOnce();

      final op = (server.receivedBatches.single['operations'] as List).single
          as Map<String, Object?>;
      expect(op['amount'], '1500');
      expect(op['currency'], 'XOF');
    });
  });

  group('the double-charge guarantee', () {
    test(
        'a dropped response does NOT create a second sale when the client '
        'retries', () async {
      // Worst case on a flaky cell: the server commits, then the connection
      // dies before the client sees the reply.
      server.dropResponseAfterCommit = true;
      final sale = await record(2000);
      final failed = await sync.syncOnce();

      expect(failed.didReachServer, isFalse);
      expect(server.transactionCount, 1, reason: 'the server did commit');
      expect(await dao.pendingCount(), 1, reason: 'the client does not know');

      // The network recovers and the client retries the same sale.
      server.dropResponseAfterCommit = false;
      final retry = await sync.drain();

      // The server recognised the key instead of creating a duplicate.
      expect(server.transactionCount, 1);
      expect(retry.alreadyOnServer, 1);
      expect(retry.sent, 0);
      expect(await dao.pendingCount(), 0);

      final stored = (await dao.recent()).single;
      expect(stored.idempotencyKey, sale.idempotencyKey);
      expect(stored.syncState, SaleSyncState.synced);
      expect(stored.serverId, isNotNull);
    });

    test('reuses the same key across many failed attempts', () async {
      server.failWith = http.ClientException('offline');
      final sale = await record(750);

      for (var attempt = 0; attempt < 5; attempt++) {
        await sync.syncOnce();
      }
      // Each failure pushed the row further into backoff, so it is not due yet.
      // That is the point of the backoff; wait it out rather than defeat it.
      server.failWith = null;
      await _waitUntilDue(dao);
      await sync.drain();

      expect(server.transactionCount, 1);
      // Every operation the server ever saw carried the original key.
      for (final batch in server.receivedBatches) {
        for (final op in batch['operations'] as List) {
          expect((op as Map)['idempotency_key'], sale.idempotencyKey);
        }
      }
    });
  });

  group('failure handling', () {
    test('an outage leaves every sale queued and reports the failure',
        () async {
      await record(300);
      await record(400);
      server.failWith = http.ClientException('network is unreachable');

      final outcome = await sync.syncOnce();

      expect(outcome.didReachServer, isFalse);
      expect(outcome.failure, isNotNull);
      expect(outcome.sent, 0);
      expect(await dao.pendingCount(), 2);
    });

    test('a permanent refusal is not retried forever, and is not deleted',
        () async {
      final bad = await record(900);
      server.rejectKeys.add(bad.idempotencyKey);

      final outcome = await sync.drain();

      expect(outcome.rejected, 1);
      expect(await dao.pendingCount(), 0);
      expect(await dao.rejectedCount(), 1);

      // The row survives: it is the merchant's record of money taken.
      final stored = (await dao.recent()).single;
      expect(stored.syncState, SaleSyncState.rejected);
      expect(stored.lastError, isNotNull);
      expect(stored.amount, Money.fromMajor(900, 'XOF'));
    });

    test('a rejected sale can be requeued and keeps its original key',
        () async {
      final bad = await record(900);
      server.rejectKeys.add(bad.idempotencyKey);
      await sync.drain();
      expect(await dao.rejectedCount(), 1);

      // The cause is fixed server-side and the merchant retries.
      server.rejectKeys.clear();
      await repo.retryRejected(bad.localId!);
      expect(await dao.pendingCount(), 1);

      await sync.drain();
      final stored = (await dao.recent()).single;
      expect(stored.syncState, SaleSyncState.synced);
      expect(stored.idempotencyKey, bad.idempotencyKey);
    });

    test('one bad sale does not block the good ones in the same batch',
        () async {
      server.failWith = http.ClientException('offline');
      final a = await record(100);
      final bad = await record(200);
      final c = await record(300);
      server.failWith = null;
      server.rejectKeys.add(bad.idempotencyKey);

      final outcome = await sync.drain();

      expect(outcome.sent, 2);
      expect(outcome.rejected, 1);
      expect(await dao.pendingCount(), 0);

      final byKey = {
        for (final s in await dao.recent()) s.idempotencyKey: s.syncState,
      };
      expect(byKey[a.idempotencyKey], SaleSyncState.synced);
      expect(byKey[c.idempotencyKey], SaleSyncState.synced);
      expect(byKey[bad.idempotencyKey], SaleSyncState.rejected);
    });

    test('an empty queue costs no request at all', () async {
      final outcome = await sync.syncOnce();
      expect(outcome.sent, 0);
      expect(server.receivedBatches, isEmpty);
    });
  });

  group("the merchant's own books", () {
    test('today total sums exactly, including unsynced sales', () async {
      server.failWith = http.ClientException('offline');
      for (var i = 0; i < 40; i++) {
        await record(125);
      }

      final total = await repo.totalToday();
      expect(total, Money.fromMajor(5000, 'XOF'));
      expect(total!.toWireString(), '5000');
      // The total must not wait on the server.
      expect(await dao.pendingCount(), 40);
    });

    test('no sales today yields null, not a zero in an unknown currency',
        () async {
      expect(await repo.totalToday(), isNull);
    });
  });
}
