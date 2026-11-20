import 'dart:convert';

import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:fidelia_merchant/core/providers.dart';
import 'package:fidelia_merchant/core/wallet_change_api.dart';
import 'package:fidelia_merchant/features/wallet_change_screen.dart';
import 'package:fidelia_merchant/l10n/strings.dart';
import 'package:fidelia_merchant/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A tiny stand-in for the backend's wallet-change routes (`app/api/wallet_change.py`).
class _Server {
  Map<String, Object?> state = {'provider': 'wave', 'account_masked': '••••1111', 'active_since': null, 'cap_xof': null, 'change': null};
  final calls = <String>[];
  final bodies = <Map<String, Object?>>[];
  String? failWith; // a `detail` to answer with 403

  Map<String, Object?> change(String status) => {
        'id': 1, 'status': status, 'provider': 'orange', 'account_masked': '••••2222', 'requested_at': '2026-11-20T10:00:00',
        'code_sent': status != 'pending_confirmation', 'confirmed_at': null, 'activates_at': status == 'confirmed_waiting' ? '2026-11-21T10:00:00' : null,
        'activated_at': null, 'activation_mode': null,
      };

  http.Client client() => MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.body.isNotEmpty) bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        http.Response ok(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
        if (failWith != null && request.method == 'POST') return ok({'detail': failWith}, 403);
        final path = request.url.path;
        if (path == '/api/merchant/wallet') return ok(state);
        if (path == '/api/merchant/wallet-change') {
          state = {...state, 'change': change('pending_confirmation')};
          return ok(change('pending_confirmation'), 201);
        }
        if (path == '/api/merchant/wallet-change/confirm') {
          final code = bodies.last['code'];
          if (code != '123456') return ok({'detail': 'wrong_code'}, 400);
          state = {...state, 'change': change('confirmed_waiting')};
          return ok(change('confirmed_waiting'));
        }
        if (path == '/api/merchant/wallet-change/not-me') {
          state = {...state, 'change': change('frozen')};
          return ok(change('frozen'));
        }
        if (path == '/api/merchant/wallet-change/cancel') {
          state = {...state, 'change': null};
          return ok(change('cancelled'));
        }
        return ok({'detail': 'not found'}, 404);
      });
}

Future<void> _pump(WidgetTester tester, _Server server, {StepUp? stepUp}) async {
  final api = WalletChangeApi(ApiClient(inner: server.client(), tokenProvider: () async => 't', baseUrl: 'https://api.test.invalid'));
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      walletChangeApiProvider.overrideWithValue(api),
      if (stepUp != null) stepUpProvider.overrideWithValue(stepUp),
    ],
    child: MaterialApp(theme: fideliaTheme(), home: const WalletChangeScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, {String account = '0702222222', String password = 'secret-pass-1'}) async {
  await tester.enterText(find.byKey(const Key('wallet-account')), account);
  await tester.tap(find.text(Strings.walletRequest));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, password);
  await tester.tap(find.widgetWithText(FilledButton, Strings.walletRequest).last);
  await tester.pumpAndSettle();
}

void main() {
  test('the API talks to the right routes with the right bodies', () async {
    final s = _Server();
    final api = WalletChangeApi(ApiClient(inner: s.client(), tokenProvider: () async => 't', baseUrl: 'https://api.test.invalid'));
    final st = await api.mine();
    expect(st.hasWallet, isTrue);
    expect(st.accountMasked, '••••1111');
    final c = await api.request(provider: 'orange', account: '0702222222');
    expect(c.status, 'pending_confirmation');
    expect(s.bodies.last, {'provider': 'orange', 'account': '0702222222'});
    await api.confirm('123456');
    expect(s.bodies.last, {'code': '123456'});
    final w = (await api.mine()).change!;
    expect(w.status, 'confirmed_waiting');
    expect(w.activatesAt, isNotNull);
    await api.notMe();
    await api.cancel();
    expect(s.calls, [
      'GET /api/merchant/wallet', 'POST /api/merchant/wallet-change', 'POST /api/merchant/wallet-change/confirm', 'GET /api/merchant/wallet',
      'POST /api/merchant/wallet-change/not-me', 'POST /api/merchant/wallet-change/cancel',
    ]);
  });

  testWidgets('shows the current wallet masked and the request form', (tester) async {
    await _pump(tester, _Server());
    expect(find.text('Wave ••••1111'), findsOneWidget);
    expect(find.text(Strings.walletRequestTitle), findsOneWidget);
    expect(find.textContaining('0701111111'), findsNothing, reason: 'the full number never reaches the screen');
  });

  testWidgets('a shop without a wallet is invited to add one', (tester) async {
    final s = _Server()..state = {'provider': null, 'account_masked': null, 'active_since': null, 'cap_xof': null, 'change': null};
    await _pump(tester, s);
    expect(find.text(Strings.walletNone), findsOneWidget);
    expect(find.text(Strings.walletFirstTitle), findsOneWidget);
  });

  testWidgets('requesting a change re-proves the password first, then asks the server, then waits for the code', (tester) async {
    final s = _Server();
    final proved = <String>[];
    await _pump(tester, s, stepUp: (p) async => proved.add(p));
    await _ask(tester);
    expect(proved, ['secret-pass-1']);
    expect(s.calls, contains('POST /api/merchant/wallet-change'));
    expect(s.bodies.first, {'provider': 'wave', 'account': '0702222222'});
    expect(find.textContaining(Strings.walletPending), findsOneWidget);
    expect(find.text(Strings.walletNotMe), findsOneWidget);
  });

  testWidgets('without the auth sign-in the request stops at the password step and says why', (tester) async {
    final s = _Server();
    await _pump(tester, s); // default step-up: unavailable
    await _ask(tester);
    expect(find.text(Strings.walletPasswordNeeded), findsOneWidget);
    expect(s.calls.where((c) => c.contains('wallet-change')), isEmpty, reason: 'nothing is sent without the fresh proof');
  });

  testWidgets('the server refusing a legacy session is explained, not shown raw', (tester) async {
    final s = _Server()..failWith = 'auth_login_required';
    await _pump(tester, s, stepUp: (_) async {});
    await _ask(tester);
    expect(find.text(Strings.walletPasswordNeeded), findsOneWidget);
  });

  testWidgets('the code: wrong then right, and the 24 h wait is announced', (tester) async {
    final s = _Server()..state = {'provider': 'wave', 'account_masked': '••••1111', 'active_since': null, 'cap_xof': null, 'change': _Server().change('pending_confirmation')};
    await _pump(tester, s);
    await tester.enterText(find.widgetWithText(TextField, Strings.walletCodeLabel), '000000');
    await tester.tap(find.text(Strings.walletConfirm));
    await tester.pumpAndSettle();
    expect(find.text(Strings.walletWrongCode), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, Strings.walletCodeLabel), '123456');
    await tester.tap(find.text(Strings.walletConfirm));
    await tester.pumpAndSettle();
    expect(find.textContaining(Strings.walletWaiting), findsOneWidget);
    expect(find.text(Strings.walletStillOld), findsOneWidget);
    expect(find.textContaining(Strings.walletWaitingHint), findsOneWidget);
  });

  testWidgets('"ce n\'etait pas moi" asks first, then freezes and tells the merchant the team will call', (tester) async {
    final s = _Server()..state = {'provider': 'wave', 'account_masked': '••••1111', 'active_since': null, 'cap_xof': null, 'change': _Server().change('confirmed_waiting')};
    await _pump(tester, s);
    await tester.tap(find.text(Strings.walletNotMe));
    await tester.pumpAndSettle();
    expect(find.text(Strings.walletNotMeQuestion), findsOneWidget);
    expect(s.calls.where((c) => c.contains('not-me')), isEmpty, reason: 'a tap alone does not freeze anything');
    await tester.tap(find.widgetWithText(FilledButton, Strings.walletNotMe));
    await tester.pumpAndSettle();
    expect(s.calls, contains('POST /api/merchant/wallet-change/not-me'));
    expect(find.text(Strings.walletFrozen), findsOneWidget);
    expect(find.text(Strings.walletRequest), findsNothing, reason: 'no new request while the change is frozen');
  });

  testWidgets('the first-week cap is shown after a wallet became active', (tester) async {
    final s = _Server()..state = {'provider': 'wave', 'account_masked': '••••1111', 'active_since': '2026-11-20T09:00:00', 'cap_xof': 50000, 'change': null};
    await _pump(tester, s);
    expect(find.textContaining('50000 FCFA'), findsOneWidget);
  });

  testWidgets('cancelling a request that has no code yet clears it', (tester) async {
    final s = _Server()..state = {'provider': 'wave', 'account_masked': '••••1111', 'active_since': null, 'cap_xof': null, 'change': _Server().change('pending_confirmation')};
    await _pump(tester, s);
    await tester.tap(find.text(Strings.walletCancel));
    await tester.pumpAndSettle();
    expect(s.calls, contains('POST /api/merchant/wallet-change/cancel'));
    expect(find.text(Strings.walletRequestTitle), findsOneWidget);
  });
}
