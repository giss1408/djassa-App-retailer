import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fidelia_merchant/core/auth/auth_repository.dart';
import 'package:fidelia_merchant/core/auth/token_store.dart';
import 'package:fidelia_merchant/core/monitoring/error_reporter.dart';
import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:fidelia_merchant/core/net/api_exception.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_api.dart';

/// Phone + SMS code sign-in, session renewal, and error reporting, against a
/// stand-in for `app/api/auth.py` and `app/api/client_events.py`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> sent;
  late http.Response Function(http.Request) respond;
  late TokenStore store;
  late int unauthorizedCalls;
  late AuthRepository auth;
  late ApiClient client;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, Object?> pair(String access, String refresh) =>
      {'access_token': access, 'refresh_token': refresh, 'token_type': 'bearer', 'expires_in': 3600, 'role': AuthRepository.appRole, 'phone_masked': '07 •• •• 00 02'};

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sent = [];
    unauthorizedCalls = 0;
    store = TokenStore();
    client = ApiClient(
      inner: MockClient((request) async {
        sent.add(request);
        return respond(request);
      }),
      tokenProvider: store.readToken,
      onRefresh: () => auth.refresh(),
      onUnauthorized: () async {
        unauthorizedCalls++;
        await store.clear();
      },
      baseUrl: 'https://api.test.invalid',
    );
    auth = AuthRepository(client: client, tokenStore: store);
  });

  test('a code is requested for this app, then exchanged for both tokens', () async {
    respond = (r) => r.url.path == '/api/auth/otp/request'
        ? json({'phone_masked': '07 •• •• 00 02', 'expires_in': 300, 'resend_in': 60}, 202)
        : json(pair('access-1', 'refresh-1'));

    final sentCode = await auth.requestCode('07 00 00 00 02');
    expect(sentCode, isA<CodeSent>());
    expect(jsonDecode(sent.first.body), {'phone': '07 00 00 00 02', 'app': AuthRepository.appRole});

    final result = await auth.verifyCode(phone: '07 00 00 00 02', code: '123456');
    expect(result, isA<SignInSuccess>());
    expect((result as SignInSuccess).username, '07 •• •• 00 02');
    expect(await store.readToken(), 'access-1');
    expect(await store.readRefreshToken(), 'refresh-1');
  });

  test('a wrong code shows the server\'s words and does not end anything', () async {
    respond = (_) => json({'detail': 'Code incorrect ou expire. Demandez un nouveau code.'}, 401);
    final result = await auth.verifyCode(phone: '0700000002', code: '000000');
    expect(result, isA<SignInRejected>());
    expect((result as SignInRejected).message, startsWith('Code incorrect'));
    expect(unauthorizedCalls, 0);
  });

  test('too many codes is a refusal with the server\'s words', () async {
    respond = (_) => json({'detail': 'Patientez 42 s avant de redemander un code'}, 429);
    final result = await auth.requestCode('0700000002');
    expect((result as CodeRequestRefused).message, contains('42 s'));
  });

  test('a 401 renews the session once and replays the request', () async {
    await store.save(token: 'stale', refreshToken: 'refresh-1', username: 'x');
    respond = (r) {
      if (r.url.path == '/api/auth/refresh') return json(pair('fresh', 'refresh-2'));
      return r.headers['Authorization'] == 'Bearer fresh' ? json({'ok': true}) : json({'detail': 'expired'}, 401);
    };

    expect(await client.getJson('/api/merchant/deals'), {'ok': true});
    expect(sent.map((r) => r.url.path), ['/api/merchant/deals', '/api/auth/refresh', '/api/merchant/deals']);
    expect(await store.readRefreshToken(), 'refresh-2');
    expect(unauthorizedCalls, 0);
  });

  test('concurrent renewals share one refresh: a second use would be read as theft', () async {
    await store.save(token: 'stale', refreshToken: 'refresh-1', username: 'x');
    final gate = Completer<void>();
    var refreshes = 0;
    client = ApiClient(
      inner: MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshes++;
          await gate.future;
          return json(pair('fresh', 'refresh-2'));
        }
        return json({});
      }),
      tokenProvider: store.readToken,
      baseUrl: 'https://api.test.invalid',
    );
    auth = AuthRepository(client: client, tokenStore: store);

    final both = Future.wait([auth.refresh(), auth.refresh()]);
    gate.complete();
    expect(await both, [true, true]);
    expect(refreshes, 1);
  });

  test('a refused renewal ends the session', () async {
    await store.save(token: 'stale', refreshToken: 'revoked', username: 'x');
    respond = (r) => json({'detail': 'Session expiree. Reconnectez-vous.'}, 401);

    await expectLater(client.getJson('/api/merchant/deals'), throwsA(isA<UnauthorizedException>()));
    expect(unauthorizedCalls, 1);
    expect(await store.readRefreshToken(), isNull);
  });

  test('offline renewal keeps the session: a dead cell never signs anyone out', () async {
    await store.save(token: 'stale', refreshToken: 'refresh-1', username: 'x');
    respond = (r) {
      if (r.url.path == '/api/auth/refresh') throw const SocketException('no route');
      return json({'detail': 'expired'}, 401);
    };

    await expectLater(client.getJson('/api/merchant/deals'), throwsA(isA<NetworkException>()));
    expect(unauthorizedCalls, 0);
    expect(await store.readRefreshToken(), 'refresh-1');
  });

  test('sign-out revokes on the server and wipes the device', () async {
    await store.save(token: FakeFideliaServer.validJwt(), refreshToken: 'refresh-1', username: 'x');
    respond = (_) => http.Response('', 204);
    await auth.signOut();
    expect(sent.single.url.path, '/api/auth/logout');
    expect(jsonDecode(sent.single.body), {'refresh_token': 'refresh-1'});
    expect(await store.readToken(), isNull);
  });

  group('account recovery', () {
    test('signing out other phones keeps this one', () async {
      await store.save(token: 'access', refreshToken: 'mine', username: 'x');
      respond = (_) => json({'revoked': 2});
      expect(await auth.revokeOtherSessions(), 2);
      expect(sent.single.url.path, '/api/auth/sessions/revoke-others');
      expect(jsonDecode(sent.single.body), {'refresh_token': 'mine'});
    });

    test('a number change stores the new session', () async {
      await store.save(token: 'access', refreshToken: 'old-refresh', username: '07 •• •• 56 78');
      respond = (r) => r.url.path == '/api/auth/change-number/request'
          ? json({'old_phone_masked': '07 •• •• 56 78', 'new_phone_masked': '05 •• •• 33 44', 'expires_in': 300, 'resend_in': 60}, 202)
          : json({...pair('new-access', 'new-refresh'), 'phone_masked': '05 •• •• 33 44'});

      final codes = await auth.requestNumberChange('0511223344');
      expect(codes.newPhoneMasked, '05 •• •• 33 44');
      final username = await auth.confirmNumberChange(newPhone: '0511223344', oldCode: '111111', newCode: '222222');
      expect(username, '05 •• •• 33 44');
      expect(await store.readRefreshToken(), 'new-refresh');
      expect(jsonDecode(sent.last.body), {'new_phone': '0511223344', 'old_code': '111111', 'new_code': '222222'});
    });

    test('a refusal arrives in the server\'s words', () async {
      await store.save(token: 'access', refreshToken: 'r', username: 'x');
      respond = (_) => json({'detail': 'Ce numero a deja un compte Fidelia.'}, 409);
      await expectLater(
        auth.requestNumberChange('0511223344'),
        throwsA(isA<AccountActionException>().having((e) => e.message, 'message', startsWith('Ce numero'))),
      );
    });

    test('a lost-number request needs no session', () async {
      respond = (r) => r.url.path == '/api/auth/recovery/code'
          ? json({'phone_masked': '05 •• •• 33 44', 'expires_in': 300, 'resend_in': 60, 'dev_code': '123456'}, 202)
          : json({'status': 'pending', 'message': 'Demande recue.'}, 202);

      final code = await auth.requestRecoveryCode('0511223344');
      expect((code as CodeSent).devCode, '123456');
      final message = await auth.fileRecovery(newPhone: '0511223344', code: '123456', oldPhone: '0712345678', details: 'Chez Tantie Awa');
      expect(message, 'Demande recue.');
      expect(sent.every((r) => r.headers['Authorization'] == null), isTrue);
    });
  });

  test('a merchant asks to join without a session', () async {
    respond = (r) => r.url.path == '/api/partner-requests/code'
        ? json({'phone_masked': '07 •• •• 66 77', 'expires_in': 300, 'resend_in': 60, 'dev_code': '654321'}, 202)
        : json({'status': 'pending', 'message': 'Demande recue.'}, 202);
    final code = await auth.requestPartnerCode('0744556677');
    expect((code as CodeSent).devCode, '654321');
    final message = await auth.filePartnerRequest(
      phone: '0744556677', code: '654321', contactName: 'Awa', shopName: 'Chez Awa',
      category: 'maquis', commune: 'Abobo', walletProvider: 'wave',
    );
    expect(message, 'Demande recue.');
    expect(jsonDecode(sent.last.body), {
      'phone': '0744556677', 'code': '654321', 'contact_name': 'Awa', 'shop_name': 'Chez Awa',
      'category': 'maquis', 'commune': 'Abobo', 'wallet_provider': 'wave',
    });
    expect(sent.every((r) => r.headers['Authorization'] == null), isTrue);
  });

  group('ErrorReporter', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('fidelia-errors-'));
    tearDown(() => dir.delete(recursive: true));

    ErrorReporter reporter(http.Client inner) =>
        ErrorReporter(app: 'retailer', client: inner, directory: () async => dir, enabled: true, baseUrl: 'https://api.test.invalid');

    test('one bug hit many times is one report with a count, digits scrubbed', () async {
      final reports = <Map<String, Object?>>[];
      final r = reporter(MockClient((request) async {
        reports.add(jsonDecode(request.body) as Map<String, Object?>);
        return http.Response('{"accepted":1}', 202);
      }));
      final stack = StackTrace.fromString('#0      SyncService.flush (package:fidelia_merchant/core/data/sync_service.dart:88:5)\n');
      for (var i = 0; i < 3; i++) {
        r.record(StateError('sale for +2250700000002 of 150000 failed'), stack);
      }
      await r.flush();

      final body = reports.single;
      expect(body['app'], 'retailer');
      final events = body['events'] as List;
      expect(events, hasLength(1));
      final event = events.single as Map;
      expect(event['count'], 3);
      expect(event['message'], isNot(contains('0700000002')));
      expect(event['message'], isNot(contains('150000')));
      expect(event['stack'], contains('sync_service.dart:88:5'));

      // Delivered, so a second flush sends nothing.
      await r.flush();
      expect(reports, hasLength(1));
    });

    test('reports survive being offline, and a restart', () async {
      final offline = reporter(MockClient((_) async => throw const SocketException('offline')));
      offline.record(StateError('boom'), StackTrace.fromString('#0 main (file.dart:1:1)'));
      await offline.flush();
      await Future<void>.delayed(const Duration(milliseconds: 2100)); // the debounced save

      final received = <http.Request>[];
      final next = reporter(MockClient((request) async {
        received.add(request);
        return http.Response('{}', 202);
      }));
      await next.flush();
      expect(received, hasLength(1));
      expect(received.single.url.path, '/api/client-events');
    });
  });
}
