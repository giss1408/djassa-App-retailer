import 'dart:io';
import 'dart:math';

import 'package:hossouko_merchant/core/data/database.dart';
import 'package:hossouko_merchant/core/data/sale_dao.dart';
import 'package:hossouko_merchant/core/data/sale_repository.dart';
import 'package:hossouko_merchant/core/data/sync_service.dart';
import 'package:hossouko_merchant/core/model/money.dart';
import 'package:hossouko_merchant/core/model/phone.dart';
import 'package:hossouko_merchant/core/model/sale.dart';
import 'package:hossouko_merchant/core/net/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_api.dart';
import 'support/test_db.dart';

/// A cash customer who gives their number earns points on the sale. The number
/// used to stay on the phone; these cover it reaching the server, the points
/// coming back, and the upgrade that makes room for them without touching a
/// merchant's unsynced sales.
void main() {
  group('normalizeIvorianPhone', () {
    for (final raw in ['07 12 34 56 78', '0712345678', '07.12.34.56.78', '+225 07 12 34 56 78', '00225 0712345678']) {
      test('"$raw" is one customer', () => expect(normalizeIvorianPhone(raw), '+2250712345678'));
    }
    for (final raw in ['', '12345', '7123456789', '+225712345678', '07 12 34 56 7x', '+33612345678']) {
      test('"$raw" is refused', () => expect(normalizeIvorianPhone(raw), isNull));
    }
  });

  group('the sale payload', () {
    Sale sale(String? ref, {bool consent = true}) => Sale(
          idempotencyKey: 'key-00000001',
          amount: Money.fromMajor(2500, 'XOF'),
          type: 'sale',
          recordedAt: DateTime.utc(2026, 10, 1, 12),
          customerRef: ref,
          customerConsent: consent,
        );

    test('carries the customer number and their consent when there is one', () {
      final json = sale('+2250712345678').toApiJson();
      expect(json['customer_phone'], '+2250712345678');
      expect(json['customer_consent'], isTrue);
    });

    test('a number without consent (queued before the app asked) goes without the number', () {
      final json = sale('+2250712345678', consent: false).toApiJson();
      expect(json.containsKey('customer_phone'), isFalse);
      expect(json.containsKey('customer_consent'), isFalse);
    });

    test('an anonymous sale sends no customer field', () {
      expect(sale(null).toApiJson().containsKey('customer_phone'), isFalse);
    });

    test('free text queued by an older version is dropped, not sent to get the sale rejected', () {
      expect(sale('Awa, la voisine').toApiJson().containsKey('customer_phone'), isFalse);
    });
  });

  group('syncing', () {
    late FakeHossoukoServer server;
    late SaleDao dao;
    late SyncService sync;
    late SaleRepository repo;
    late Future<void> Function() closeDb;

    setUp(() async {
      server = FakeHossoukoServer();
      final db = await openTestDatabase();
      closeDb = db.close;
      dao = SaleDao(db.db);
      sync = SyncService(
        client: ApiClient(
          inner: server.client(),
          tokenProvider: () async => FakeHossoukoServer.validJwt(),
          baseUrl: 'https://api.test.invalid',
        ),
        dao: dao,
        random: Random(1),
        baseBackoff: const Duration(milliseconds: 1),
      );
      repo = SaleRepository(dao: dao, syncService: sync, syncAfterRecording: false);
    });

    tearDown(() async => closeDb());

    test('stores the points the server granted, so the merchant can tell the customer', () async {
      await repo.recordSale(amount: Money.fromMajor(2500, 'XOF'), type: 'sale', customerRef: '+2250712345678', customerConsent: true);
      await repo.recordSale(amount: Money.fromMajor(1000, 'XOF'), type: 'sale');
      await sync.syncOnce();

      final ops = (server.receivedBatches.single['operations'] as List).cast<Map<String, Object?>>();
      expect(ops.first['customer_phone'], '+2250712345678');
      expect(ops.last.containsKey('customer_phone'), isFalse);

      final sales = await dao.recent(limit: 10);
      final withCustomer = sales.firstWhere((s) => s.customerRef != null);
      final anonymous = sales.firstWhere((s) => s.customerRef == null);
      expect(withCustomer.syncState, SaleSyncState.synced);
      expect(withCustomer.pointsAwarded, 25);
      expect(anonymous.pointsAwarded, 0);
    });
  });

  test('upgrading from v1 keeps an unsynced sale and adds the points column', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = '${Directory.systemTemp.createTempSync('hossouko_v1_').path}/hossouko.db';

    // The v1 schema, as shipped: no points column.
    final v1 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE sales (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT, idempotency_key TEXT NOT NULL UNIQUE,
              merchant_id INTEGER NOT NULL, amount_minor INTEGER NOT NULL, currency TEXT NOT NULL,
              type TEXT NOT NULL, recorded_at INTEGER NOT NULL, customer_ref TEXT, server_id INTEGER,
              sync_state TEXT NOT NULL DEFAULT 'pending', attempt_count INTEGER NOT NULL DEFAULT 0,
              next_attempt_at INTEGER, last_error TEXT)'''),
        ));
    await v1.insert('sales', {
      'idempotency_key': 'queued-before-upgrade',
      'merchant_id': 0,
      'amount_minor': 1500,
      'currency': 'XOF',
      'type': 'sale',
      'recorded_at': DateTime.utc(2026, 9, 30).millisecondsSinceEpoch,
      'customer_ref': 'Awa',
    });
    await v1.close();

    final upgraded = await AppDatabase.open(path: path);
    final pending = await SaleDao(upgraded.db).pendingBatch();
    expect(pending.single.idempotencyKey, 'queued-before-upgrade');
    expect(pending.single.pointsAwarded, isNull);
    expect(pending.single.customerConsent, isFalse, reason: 'v3 column defaults to no consent');
    // And the legacy free-text customer does not poison the send.
    expect(pending.single.toApiJson().containsKey('customer_phone'), isFalse);
    await upgraded.close();
  });
}
