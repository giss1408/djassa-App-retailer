import 'dart:convert';

import 'package:hossouko_merchant/core/data/database.dart';
import 'package:hossouko_merchant/core/model/deal.dart';
import 'package:hossouko_merchant/core/monitoring/usage_tracker.dart';
import 'package:hossouko_merchant/core/net/api_client.dart';
import 'package:hossouko_merchant/core/providers.dart';
import 'package:hossouko_merchant/features/demo/demo_backend.dart';
import 'package:hossouko_merchant/features/home_screen.dart';
import 'package:hossouko_merchant/l10n/strings.dart';
import 'package:hossouko_merchant/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<(int, Object?)> _call(http.Client c, String method, String path, [Object? body]) async {
  final request = http.Request(method, Uri.parse('https://demo.hossouko.invalid$path'));
  if (body != null) request.body = jsonEncode(body);
  final response = await http.Response.fromStream(await c.send(request));
  return (response.statusCode, response.body.isEmpty ? null : jsonDecode(response.body));
}

void main() {
  group('the demo server', () {
    test('has an offer with each corner banner to look at', () async {
      final (status, deals) = await _call(DemoBackend(), 'GET', '/api/merchant/deals');
      expect(status, 200);
      final ribbons = [for (final d in deals! as List) Deal.fromJson(d as Map<String, Object?>).ribbon];
      expect(ribbons.toSet(), DealRibbon.values.toSet());
    });

    test('a sale with a consenting customer earns points, read back at the counter', () async {
      final demo = DemoBackend();
      final (_, sync) = await _call(demo, 'POST', '/api/merchant/sales/sync', {
        'operations': [
          {'idempotency_key': 'k1', 'amount': '3000', 'customer_phone': '+2250700000001', 'customer_consent': true},
          {'idempotency_key': 'k2', 'amount': '3000', 'customer_phone': '+2250700000002'},
        ]
      });
      final results = (sync! as Map)['results'] as List;
      expect([for (final r in results) (r as Map)['status']], ['accepted', 'accepted']);
      expect([for (final r in results) ((r as Map)['sale'] as Map)['points_awarded']], [30, 0]);
      final (_, balance) = await _call(demo, 'POST', '/api/merchant/customers/loyalty', {'phone': '07 00 00 00 01'});
      expect((balance! as Map)['points'], 30);
    });

    test('refuses, in French, what needs a real shop', () async {
      final demo = DemoBackend();
      for (final (method, path) in [
        ('GET', '/api/merchant/pay-code'),
        ('POST', '/api/merchant/payment-requests'),
        ('PUT', '/api/merchant/wave'),
        ('POST', '/api/merchant/staff'),
        ('PUT', '/api/merchant/venue/location'),
      ]) {
        final (status, body) = await _call(demo, method, path, {});
        expect(status, 403, reason: '$method $path');
        expect((body! as Map)['detail'], Strings.demoNeedsAccount);
      }
    });
  });

  testWidgets('the demo opens from the sign-in screen without touching the network or the real ledger', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final realCalls = <String>[];
    final real = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => AppDatabase.open(path: inMemoryDatabasePath)),
      apiClientProvider.overrideWithValue(ApiClient(
        inner: MockClient((r) async {
          realCalls.add('${r.method} ${r.url.path}');
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
        tokenProvider: () async => null,
        baseUrl: 'https://api.test.invalid',
      )),
    ]);
    addTearDown(real.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(AppHost(container: real, usage: UsageTracker(app: 'retailer', enabled: false)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text(Strings.tryDemo), findsOneWidget);

    await tester.ensureVisible(find.text(Strings.tryDemo));
    await tester.tap(find.text(Strings.tryDemo));
    // The demo's in-memory ledger opens on real async IO (sqflite ffi).
    for (var i = 0; i < 10 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(Strings.demoBar), findsOneWidget);
    expect(find.textContaining(Strings.demoShopName), findsWidgets);
    expect(realCalls, isEmpty, reason: 'the demo never reaches the real server');

    // "Se connecter" leaves the demo for the real sign-in screen.
    await tester.tap(find.text(Strings.demoSignIn));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(Strings.demoBar), findsNothing);
    expect(find.text(Strings.tryDemo), findsOneWidget);
  });
}
