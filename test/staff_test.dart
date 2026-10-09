import 'dart:convert';

import 'package:fidelia_merchant/core/auth/token_store.dart';
import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:fidelia_merchant/core/providers.dart';
import 'package:fidelia_merchant/core/staff_api.dart';
import 'package:fidelia_merchant/features/staff_screen.dart';
import 'package:fidelia_merchant/l10n/strings.dart';
import 'package:fidelia_merchant/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A tiny stand-in for the backend's /api/merchant/staff.
class _StaffServer {
  final team = <Map<String, Object?>>[];
  final posted = <Map<String, Object?>>[];
  var nextId = 1;

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/api/merchant/staff') {
          return http.Response(jsonEncode(team), 200, headers: {'content-type': 'application/json'});
        }
        if (request.method == 'POST' && path == '/api/merchant/staff') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          posted.add(body);
          if (body['phone'] == '0755555555') {
            return http.Response(jsonEncode({'detail': 'Ce numero gere deja un commerce : Maquis Autre'}), 409,
                headers: {'content-type': 'application/json'});
          }
          final member = {'id': nextId++, 'phone_masked': '07 •• •• 33 44', 'name': body['name'], 'role': 'cashier', 'last_login_at': null};
          team.add(member);
          return http.Response(jsonEncode(member), 201, headers: {'content-type': 'application/json'});
        }
        final remove = RegExp(r'^/api/merchant/staff/(\d+)$').firstMatch(path);
        if (request.method == 'DELETE' && remove != null) {
          team.removeWhere((m) => m['id'] == int.parse(remove.group(1)!));
          return http.Response('', 204);
        }
        return http.Response('{"detail":"not found"}', 404);
      });
}

Future<void> _pump(WidgetTester tester, _StaffServer server) async {
  final api = StaffApi(ApiClient(inner: server.client(), tokenProvider: () async => 't', baseUrl: 'https://api.test.invalid'));
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [staffApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: fideliaTheme(), home: const StaffScreen()),
  ));
  await tester.pumpAndSettle();
}

String _token(Map<String, Object?> claims) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

void main() {
  test('the session role comes from the token, owner by default', () {
    expect(jwtRole(_token({'sub': 'tel:+2250700000003', 'role': 'cashier'})), 'cashier');
    expect(jwtRole(_token({'sub': 'tel:+2250700000002', 'role': 'merchant'})), 'merchant');
    expect(jwtRole(_token({'sub': 'demo'})), 'merchant', reason: 'tokens from before roles were merchant tokens');
    expect(jwtRole('not a token'), 'merchant');
    expect(const SessionState(signedIn: true, role: 'cashier').isOwner, isFalse);
    expect(const SessionState(signedIn: true).isOwner, isTrue);
  });

  testWidgets('the owner adds a cashier, sees them invited, then removes them', (tester) async {
    final server = _StaffServer();
    await _pump(tester, server);
    expect(find.text(Strings.noCashiers), findsOneWidget);

    await tester.tap(find.text(Strings.addCashier));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, Strings.cashierPhone), '07 11 22 33 44');
    await tester.enterText(find.widgetWithText(TextField, Strings.cashierName), 'Koffi');
    await tester.tap(find.text(Strings.add));
    await tester.pumpAndSettle();

    expect(server.posted.single, {'phone': '07 11 22 33 44', 'name': 'Koffi'});
    expect(find.text('Koffi'), findsOneWidget);
    expect(find.text('07 •• •• 33 44 - ${Strings.cashierInvited}'), findsOneWidget);

    await tester.tap(find.text(Strings.removeCashier));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(Strings.removeCashier)));
    await tester.pumpAndSettle();
    expect(server.team, isEmpty);
    expect(find.text(Strings.noCashiers), findsOneWidget);
  });

  testWidgets('a refusal shows the server words in the dialog', (tester) async {
    final server = _StaffServer();
    await _pump(tester, server);
    await tester.tap(find.text(Strings.addCashier));
    await tester.pumpAndSettle();

    await tester.tap(find.text(Strings.add));
    await tester.pump();
    expect(find.text(Strings.cashierPhoneNeeded), findsOneWidget);
    expect(server.posted, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, Strings.cashierPhone), '0755555555');
    await tester.tap(find.text(Strings.add));
    await tester.pumpAndSettle();
    expect(find.text('Ce numero gere deja un commerce : Maquis Autre'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'the dialog stays open to fix the number');
  });
}
