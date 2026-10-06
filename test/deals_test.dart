import 'dart:convert';

import 'package:djassa_merchant/core/deals_api.dart';
import 'package:djassa_merchant/core/model/deal.dart';
import 'package:djassa_merchant/core/net/api_client.dart';
import 'package:djassa_merchant/core/providers.dart';
import 'package:djassa_merchant/features/deals_screen.dart';
import 'package:djassa_merchant/features/new_deal_screen.dart';
import 'package:djassa_merchant/l10n/strings.dart';
import 'package:djassa_merchant/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A tiny stand-in for the backend's /api/merchant/deals.
class _DealsServer {
  final deals = <Map<String, Object?>>[];
  final posted = <Map<String, Object?>>[];
  var nextId = 1;
  bool offline = false;

  http.Client client() => MockClient((request) async {
        if (offline) throw http.ClientException('offline');
        final path = request.url.path;
        if (request.method == 'GET' && path == '/api/merchant/deals') {
          return http.Response(jsonEncode(deals), 200, headers: {'content-type': 'application/json'});
        }
        if (request.method == 'POST' && path == '/api/merchant/deals') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          posted.add(body);
          final deal = {
            ...body,
            'id': nextId++,
            'is_featured': false,
            'ends_at': (body['ends_at']! as String).replaceAll('Z', ''),
          };
          deals.add(deal);
          return http.Response(jsonEncode(deal), 201, headers: {'content-type': 'application/json'});
        }
        final end = RegExp(r'^/api/merchant/deals/(\d+)$').firstMatch(path);
        if (request.method == 'DELETE' && end != null) {
          deals.removeWhere((d) => d['id'] == int.parse(end.group(1)!));
          return http.Response('', 204);
        }
        return http.Response('{"detail":"not found"}', 404);
      });
}

Future<void> _pump(WidgetTester tester, _DealsServer server, Widget home) async {
  final api = DealsApi(ApiClient(inner: server.client(), tokenProvider: () async => 't', baseUrl: 'https://api.test.invalid'));
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [dealsApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: djassaTheme(), home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('DealDraft', () {
    String? check(DealDraft d) => d.validate(
          titleTooShort: 'title',
          nothingOffered: 'nothing',
          percentRange: 'range',
          priceNotLower: 'price',
        );

    test('mirrors the server rules', () {
      const week = Duration(days: 7);
      expect(check(const DealDraft(title: 'ab', price: 500, duration: week)), 'title');
      expect(check(const DealDraft(title: 'Brochettes', duration: week)), 'nothing');
      expect(check(const DealDraft(title: 'Brochettes', discountPercent: 95, duration: week)), 'range');
      expect(check(const DealDraft(title: 'Brochettes', price: 900, originalPrice: 800, duration: week)), 'price');
      expect(check(const DealDraft(title: 'Brochettes', price: 500, originalPrice: 800, duration: week)), isNull);
    });

    test('sends an end date in UTC, duration from now, and drops empty fields', () {
      final now = DateTime.utc(2026, 10, 1, 12);
      final json = const DealDraft(title: '  Garba  ', description: ' ', discountPercent: 20, duration: Duration(days: 3)).toJson(now);
      expect(json, {'title': 'Garba', 'discount_percent': 20, 'ribbon': 'bon_plan', 'ends_at': '2026-10-04T12:00:00.000Z'});
    });

    test('the chosen corner banner is sent, and read back from the server', () {
      final json = const DealDraft(title: 'Flash', price: 500, duration: Duration(days: 1), ribbon: DealRibbon.flash)
          .toJson(DateTime.utc(2026, 10, 1));
      expect(json['ribbon'], 'flash');
      expect(Deal.fromJson({'id': 1, 'title': 'x', 'ends_at': '2026-10-02T00:00:00', 'ribbon': 'promo'}).ribbon, DealRibbon.promo);
      expect(Deal.fromJson({'id': 1, 'title': 'x', 'ends_at': '2026-10-02T00:00:00'}).ribbon, DealRibbon.bonPlan);
    });
  });

  testWidgets('publishing a deal sends it and lists it', (tester) async {
    final server = _DealsServer();
    await _pump(tester, server, const DealsScreen());
    expect(find.text(Strings.noDeals), findsOneWidget);

    await tester.tap(find.text(Strings.newDeal));
    await tester.pumpAndSettle();
    expect(find.byType(NewDealScreen), findsOneWidget);

    // Invalid first: nothing on offer.
    await tester.enterText(find.widgetWithText(TextField, Strings.dealTitle), 'Poulet braise');
    await tester.ensureVisible(find.text(Strings.publish));
    await tester.tap(find.text(Strings.publish));
    await tester.pump();
    expect(find.text(Strings.nothingOffered), findsOneWidget);
    expect(server.posted, isEmpty, reason: 'invalid drafts never reach the network');

    await tester.enterText(find.widgetWithText(TextField, Strings.promoPrice), '3500');
    await tester.enterText(find.widgetWithText(TextField, Strings.originalPrice), '5000');
    await tester.pump();
    expect(find.text('${francs(3500)} au lieu de ${francs(5000)}'), findsOneWidget, reason: 'preview');

    await tester.ensureVisible(find.text(Strings.publish));
    await tester.tap(find.text(Strings.publish));
    await tester.pumpAndSettle();

    expect(server.posted.single, containsPair('price', 3500));
    expect(server.posted.single, containsPair('original_price', 5000));
    expect(find.byType(DealsScreen), findsOneWidget);
    expect(find.text('Poulet braise'), findsOneWidget);
  });

  testWidgets('ending a deal asks first, then removes it', (tester) async {
    final server = _DealsServer()
      ..deals.add({'id': 7, 'title': 'Garba a 1000 F', 'price': 1000, 'ends_at': '2026-12-01T00:00:00', 'is_featured': true});
    await _pump(tester, server, const DealsScreen());
    expect(find.text(Strings.sponsored), findsOneWidget);

    await tester.tap(find.text(Strings.endDeal));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Strings.cancel));
    await tester.pumpAndSettle();
    expect(server.deals, hasLength(1), reason: 'cancel keeps it');

    await tester.tap(find.text(Strings.endDeal));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(Strings.endDeal)));
    await tester.pumpAndSettle();
    expect(server.deals, isEmpty);
    expect(find.text(Strings.noDeals), findsOneWidget);
  });

  testWidgets('a cashier sees the deals but cannot publish or end them', (tester) async {
    final server = _DealsServer()..deals.add({'id': 7, 'title': 'Garba a 1000 F', 'price': 1000, 'ends_at': '2026-12-01T00:00:00'});
    await _pump(tester, server, const DealsScreen(readOnly: true));
    expect(find.text('Garba a 1000 F'), findsOneWidget);
    expect(find.text(Strings.newDeal), findsNothing);
    expect(find.text(Strings.endDeal), findsNothing);
  });

  testWidgets('offline says so in plain words and offers a retry', (tester) async {
    final server = _DealsServer()..offline = true;
    await _pump(tester, server, const DealsScreen());
    expect(find.text(Strings.dealsNeedConnection), findsOneWidget);

    server.offline = false;
    await tester.tap(find.text(Strings.retry));
    await tester.pumpAndSettle();
    expect(find.text(Strings.noDeals), findsOneWidget);
  });
}
