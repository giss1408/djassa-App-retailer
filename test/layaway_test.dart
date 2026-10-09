import 'dart:convert';
import 'dart:math';

import 'package:fidelia_merchant/core/layaway_api.dart';
import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:fidelia_merchant/core/providers.dart';
import 'package:fidelia_merchant/features/layaway_screen.dart';
import 'package:fidelia_merchant/l10n/strings.dart';
import 'package:fidelia_merchant/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _settings = LayawaySettings(
  enabled: true,
  maxDays: 183,
  maxPrice: 1000000,
  termsVersion: 'tranches-2026-10',
  terms: 'Vous payez {item} au prix de {price} F, avant le {due_by}. L\'argent va au commerce, pas a Fidelia.',
);

Map<String, Object?> _plan({String status = 'open', int paid = 30000, List<int>? installments}) => {
      'id': 7,
      'venue_id': 1,
      'venue_name': 'Boutique',
      'customer': '07 •• •• 56 78',
      'item': 'Refrigerateur 90 L',
      'price': 90000,
      'currency': 'XOF',
      'paid': paid,
      'remaining': 90000 - paid,
      'status': status,
      'due_by': '2026-12-31T00:00:00',
      'created_at': '2026-10-06T10:00:00',
      'completed_at': null,
      'delivered_at': null,
      'cancelled_at': null,
      'cancel_reason': null,
      'refunded_amount': null,
      'installments': [
        for (final a in installments ?? [paid])
          {'id': 1, 'amount': a, 'source': 'cash_declared', 'paid_at': '2026-10-06T10:00:00'},
      ],
    };

/// A stand-in for /api/merchant/layaway. `dropFirst` loses the first answer
/// after the server applied it, the case the idempotency key exists for.
class _Server {
  _Server({this.dropFirst = false});

  final bool dropFirst;
  final posted = <(String, Map<String, Object?>)>[];
  var _dropped = false;

  http.Client client() => MockClient((request) async {
        final body = request.body.isEmpty ? <String, Object?>{} : jsonDecode(request.body) as Map<String, Object?>;
        if (request.method == 'POST') posted.add((request.url.path, body));
        if (dropFirst && !_dropped && request.method == 'POST') {
          _dropped = true;
          throw http.ClientException('connection reset');
        }
        final json = switch (request.url.path) {
          '/api/merchant/layaway' => _plan(),
          '/api/merchant/layaway/7/installments' => _plan(paid: 50000, installments: [30000, 20000]),
          _ => null,
        };
        if (json == null) return http.Response('{"detail":"not found"}', 404);
        return http.Response(jsonEncode(json), 201, headers: {'content-type': 'application/json'});
      });
}

Future<void> _pump(WidgetTester tester, _Server server, Widget screen) async {
  final api = LayawayApi(
      ApiClient(inner: server.client(), tokenProvider: () async => 't', baseUrl: 'https://api.test.invalid'));
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [layawayApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: fideliaTheme(), home: screen),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, Strings.phoneLabel), '07 12 34 56 78');
  await tester.enterText(find.widgetWithText(TextField, Strings.layawayItem), 'Refrigerateur 90 L');
  await tester.enterText(find.widgetWithText(TextField, Strings.layawayPrice), '90000');
  await tester.enterText(find.widgetWithText(TextField, Strings.layawayFirst), '30000');
  await tester.pump();
}

void main() {
  group('the plan from the server', () {
    test('reads paid, remaining and the next step', () {
      final plan = LayawayPlan.fromJson(_plan());
      expect((plan.paid, plan.remaining), (30000, 60000));
      expect(plan.progress, closeTo(0.333, 0.001));
      expect(plan.isOpen, isTrue);
      expect(LayawayPlan.fromJson(_plan(status: 'completed', paid: 90000)).readyToHandOver, isTrue);
    });

    test('terms are filled in for this good, price and date', () {
      final terms = _settings.termsFor(item: 'Frigo', price: '90 000', dueBy: '31 dec.');
      expect(terms, contains('Vous payez Frigo au prix de 90 000 F, avant le 31 dec.'));
    });
  });

  group('opening a plan', () {
    testWidgets('nothing can be sent until the customer agreed to the terms', (tester) async {
      final server = _Server();
      await _pump(tester, server, NewLayawayScreen(settings: _settings, random: Random(1), now: DateTime(2026, 10, 6)));
      await _fill(tester);
      expect(find.textContaining('Vous payez Refrigerateur 90 L au prix de 90'), findsOneWidget);

      final open = find.widgetWithText(FilledButton, Strings.layawayOpen);
      expect(tester.widget<FilledButton>(open).onPressed, isNull);

      await tester.tap(find.text(Strings.layawayAgree));
      await tester.pump();
      expect(tester.widget<FilledButton>(open).onPressed, isNotNull);

      // Changing the price after agreeing clears the agreement.
      await tester.enterText(find.widgetWithText(TextField, Strings.layawayPrice), '95000');
      await tester.pump();
      expect(tester.widget<FilledButton>(open).onPressed, isNull);
      expect(server.posted, isEmpty);
    });

    testWidgets('sends the plan with its terms version and first payment', (tester) async {
      final server = _Server();
      await _pump(tester, server, NewLayawayScreen(settings: _settings, random: Random(1), now: DateTime(2026, 10, 6)));
      await _fill(tester);
      await tester.tap(find.text(Strings.layawayAgree));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Strings.layawayOpen));
      await tester.pumpAndSettle();

      final (path, body) = server.posted.single;
      expect(path, '/api/merchant/layaway');
      expect(body['customer_phone'], '+2250712345678');
      expect((body['price'], body['terms_version'], body['terms_accepted']), (90000, 'tranches-2026-10', true));
      expect((body['first_installment']! as Map)['amount'], 30000);
      // The plan screen replaced the form.
      expect(find.text(Strings.layawayAddPayment), findsOneWidget);
    });

    testWidgets('the first payment is required', (tester) async {
      final server = _Server();
      await _pump(tester, server, NewLayawayScreen(settings: _settings, random: Random(1), now: DateTime(2026, 10, 6)));
      await _fill(tester);
      await tester.enterText(find.widgetWithText(TextField, Strings.layawayFirst), '');
      await tester.pump();
      await tester.tap(find.text(Strings.layawayAgree));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Strings.layawayOpen));
      await tester.pumpAndSettle();
      expect(find.text(Strings.layawayFirstMissing), findsOneWidget);
      expect(server.posted, isEmpty);
    });

    testWidgets('a price above the shop limit is refused before sending', (tester) async {
      final server = _Server();
      await _pump(tester, server, NewLayawayScreen(settings: _settings, random: Random(1), now: DateTime(2026, 10, 6)));
      await _fill(tester);
      await tester.enterText(find.widgetWithText(TextField, Strings.layawayPrice), '2000000');
      await tester.pump();
      await tester.tap(find.text(Strings.layawayAgree));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Strings.layawayOpen));
      await tester.pumpAndSettle();
      expect(find.textContaining(Strings.layawayPriceTooHigh), findsOneWidget);
      expect(server.posted, isEmpty);
    });
  });

  group('a payment', () {
    testWidgets('a retry after a lost answer reuses the key, so it counts once', (tester) async {
      final server = _Server(dropFirst: true);
      await _pump(tester, server, LayawayPlanScreen(plan: LayawayPlan.fromJson(_plan()), random: Random(2)));

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text(Strings.layawayAddPayment));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, Strings.layawayPaymentAmount), '20000');
        await tester.tap(find.text(Strings.ok));
        await tester.pumpAndSettle();
      }

      expect(server.posted, hasLength(2));
      final keys = {for (final (_, body) in server.posted) body['idempotency_key']};
      expect(keys, hasLength(1));
      expect(find.textContaining('50'), findsWidgets);
    });

    testWidgets('a paid plan offers the handover instead of another payment', (tester) async {
      await _pump(
          tester, _Server(), LayawayPlanScreen(plan: LayawayPlan.fromJson(_plan(status: 'completed', paid: 90000))));
      expect(find.text(Strings.layawayHandOver), findsOneWidget);
      expect(find.text(Strings.layawayAddPayment), findsNothing);
    });
  });
}
