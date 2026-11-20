import 'dart:convert';

import 'package:fidelia_merchant/core/auth/auth_repository.dart';
import 'package:fidelia_merchant/core/auth/token_store.dart';
import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Sign-in through the platform auth service (FIDELIA_AUTH_BASE): the repository talks to `/v1/...` there instead of fidelia's own
/// `/api/auth/...`, and fidelia's API only ever receives the access token the service issued. Stand-ins for both servers, no network.
String _jwt(Map<String, Object?> claims) {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(claims)}.sig';
}

final _exp = DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
String _access({bool mcp = false, int authTime = 0}) => _jwt({'sub': 'u', 'role': 'merchant', 'exp': _exp, if (mcp) 'mcp': true, 'auth_time': authTime});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStore store;
  late List<http.Request> authSent;
  late List<http.Request> fideliaSent;
  late http.Response Function(http.Request) authReply;
  late AuthRepository repo;

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = TokenStore();
    authSent = [];
    fideliaSent = [];
    authReply = (_) => json({'access_token': _access(), 'refresh_token': 'refresh-1', 'must_change_password': false, 'role': 'merchant', 'user_id': 'u'});
    ApiClient client(List<http.Request> log, http.Response Function(http.Request) reply, String base) =>
        ApiClient(inner: MockClient((r) async {
          log.add(r);
          return reply(r);
        }), tokenProvider: () async => store.readToken(), baseUrl: base);
    repo = AuthRepository(
      client: client(fideliaSent, (_) => json({'detail': 'fidelia must not be called for auth'}, 500), 'https://api.test.invalid'),
      authClient: client(authSent, (r) => authReply(r), 'https://auth.test.invalid'),
      tokenStore: store,
    );
  });

  test('sign-in goes to the auth service with product and app, stores the tokens and shows the masked number', () async {
    final result = await repo.signIn(phone: '07 01 02 03 04', password: 'pw-secret-1');
    expect(result, isA<SignInSuccess>());
    expect((result as SignInSuccess).username, '07 •• •• 03 04');
    expect(authSent.single.url.path, '/v1/login');
    expect(jsonDecode(authSent.single.body), {'phone': '0701020304', 'password': 'pw-secret-1', 'product': 'fidelia', 'app': 'merchant'});
    expect(await store.readRefreshToken(), 'refresh-1');
    expect(jwtRole((await store.readToken())!), 'merchant');
    expect(fideliaSent, isEmpty, reason: 'fidelia is not part of signing in');
  });

  test('every refusal is said in words', () async {
    final cases = {
      'invalid_credentials': 'Numero ou mot de passe incorrect.',
      'not_activated': 'Ce compte n\'est pas encore active. Demandez le code a Fidelia.',
      'account_blocked': 'Ce compte est suspendu. Contactez Fidelia.',
      'login_locked': 'Trop d\'essais. Reessayez dans 15 minutes.',
    };
    for (final e in cases.entries) {
      authReply = (_) => json({'detail': e.key}, e.key == 'account_blocked' ? 403 : 401);
      final r = await repo.signIn(phone: '0701020304', password: 'x');
      expect(r, isA<SignInRejected>());
      expect((r as SignInRejected).message, e.value);
    }
    authReply = (_) => json({'detail': 'no_access_to_app'}, 403);
    expect(((await repo.signIn(phone: '0701020304', password: 'x')) as SignInRejected).message, contains('aucun commerce'));
    expect(await store.readToken(), isNull, reason: 'a refused sign-in stores nothing');
  });

  test('a temporary password: the token says so, and the forced change reuses what was just typed', () async {
    authReply = (r) => r.url.path == '/v1/login'
        ? json({'access_token': _access(mcp: true), 'refresh_token': 'refresh-1', 'must_change_password': true})
        : r.url.path == '/v1/password/change'
            ? http.Response('', 204)
            : json({'access_token': _access(), 'refresh_token': 'refresh-2', 'must_change_password': false});
    await repo.signIn(phone: '0701020304', password: 'temp-pass-1');
    expect(jwtMustChangePassword((await store.readToken())!), isTrue);
    await repo.changePassword(newPassword: 'brand-new-pass-1'); // no current password asked: the temporary one is remembered in memory
    expect(authSent.map((r) => r.url.path), ['/v1/login', '/v1/password/change', '/v1/refresh']);
    expect(jsonDecode(authSent[1].body), {'current_password': 'temp-pass-1', 'new_password': 'brand-new-pass-1'});
    expect(authSent[1].headers['Authorization'], startsWith('Bearer '));
    expect(jwtMustChangePassword((await store.readToken())!), isFalse, reason: 'renewed after the change: the mark is gone');
    expect(await store.readRefreshToken(), 'refresh-2');
    expect(await store.readUsername(), '07 •• •• 03 04', reason: 'the account name survives a renewal');
  });

  test('renewal and sign-out use the auth service; the refresh token is single-use', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    authReply = (_) => json({'access_token': _access(), 'refresh_token': 'refresh-2', 'must_change_password': false});
    expect(await repo.refresh(), isTrue);
    expect(jsonDecode(authSent.last.body), {'refresh_token': 'refresh-1'});
    expect(authSent.last.url.path, '/v1/refresh');
    authReply = (_) => http.Response('', 204);
    await repo.signOut();
    expect(authSent.last.url.path, '/v1/logout');
    expect(jsonDecode(authSent.last.body), {'refresh_token': 'refresh-2'});
    expect(await store.readToken(), isNull);
    expect(fideliaSent, isEmpty);
  });

  test('a refused renewal ends the session', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    authReply = (_) => json({'detail': 'session_expired'}, 401);
    expect(await repo.refresh(), isFalse);
  });

  test('forgotten password is requested at auth for the fidelia product', () async {
    authReply = (_) => json({'message': 'Si ce numero a un compte, un message WhatsApp va t\'etre envoye.'}, 202);
    final message = await repo.requestPassword('07 01 02 03 04');
    expect(authSent.single.url.path, '/v1/password/reset-request');
    expect(jsonDecode(authSent.single.body), {'phone': '0701020304', 'product': 'fidelia'});
    expect(message, contains('WhatsApp'));
  });

  test('step-up re-proves the password at auth and keeps the fresh token for the same session', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    final fresh = _access(authTime: 999);
    authReply = (_) => json({'access_token': fresh, 'amr': ['pwd'], 'expires_in': 600});
    await repo.stepUp('pw-secret-1');
    expect(authSent.last.url.path, '/v1/step-up');
    expect(jsonDecode(authSent.last.body), {'password': 'pw-secret-1'});
    expect(await store.readToken(), fresh);
    expect(await store.readRefreshToken(), 'refresh-1', reason: 'same session: the refresh token is unchanged');
    authReply = (_) => json({'detail': 'invalid_credentials'}, 401);
    await expectLater(repo.stepUp('wrong'), throwsA(isA<AccountActionException>()));
    expect(await store.readToken(), fresh, reason: 'a wrong password changes nothing');
  });

  test('number verification is not available here (the auth service activates accounts)', () async {
    await expectLater(repo.verifyNumber('123456'), throwsA(isA<AccountActionException>()));
    expect(authSent, isEmpty);
  });

  test('number change: password + new number at auth, the code from the new number confirms, the session renews with the new number', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    authReply = (r) => r.url.path == '/v1/me/phone/request'
        ? json({'new_phone_masked': '+225 07 •• •• 08', 'status': 'waiting_for_code'}, 202)
        : r.url.path == '/v1/me/phone/confirm'
            ? json({'phone_masked': '+225 07 •• •• 08'})
            : json({'access_token': _access(), 'refresh_token': 'refresh-2', 'must_change_password': false, 'role': 'merchant', 'user_id': 'u'});
    expect(await repo.requestNumberChange(newPhone: '07 05 06 07 08', password: 'pw-secret-1'), '+225 07 •• •• 08');
    expect(jsonDecode(authSent.last.body), {'new_phone': '0705060708', 'current_password': 'pw-secret-1'});
    await repo.confirmNumberChange('123 456');
    expect(authSent.map((x) => x.url.path).skip(1), ['/v1/me/phone/request', '/v1/me/phone/confirm', '/v1/refresh']);
    expect(jsonDecode(authSent[2].body), {'code': '123456'});
    expect(await store.readRefreshToken(), 'refresh-2');
    expect(fideliaSent, isEmpty);
  });

  test('with a security delay the change is only scheduled: nothing renewed, the date is kept for the screen', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    final before = authSent.length;
    authReply = (_) => json({'status': 'scheduled', 'effective_at': '2026-11-21T10:00:00Z', 'phone_masked': '+225 07 •• •• 08'});
    expect(await repo.confirmNumberChange('123456'), '+225 07 •• •• 08');
    expect(repo.numberChangeScheduledFor, DateTime.utc(2026, 11, 21, 10).toLocal());
    expect(authSent.length, before + 1); // no renewal
    expect(await repo.currentUsername(), '07 •• •• 03 04'); // still the old number
  });

  test('number change refusals are explained', () async {
    await repo.signIn(phone: '0701020304', password: 'pw-secret-1');
    authReply = (_) => json({'detail': 'phone_taken'}, 409);
    await expectLater(repo.requestNumberChange(newPhone: '0705060708', password: 'x'), throwsA(isA<AccountActionException>().having((x) => x.message, 'message', 'Ce numéro a déjà un compte Fidelia.')));
    authReply = (_) => json({'detail': 'wrong_activation_code'}, 400);
    await expectLater(repo.confirmNumberChange('000000'), throwsA(isA<AccountActionException>().having((x) => x.message, 'message', 'Code incorrect ou expiré.')));
  });

  test('without an auth client the repository is exactly the legacy one', () async {
    final legacy = AuthRepository(
      client: ApiClient(inner: MockClient((r) async {
        fideliaSent.add(r);
        return json({'access_token': _access(), 'refresh_token': 'r', 'phone_masked': '07 •• •• 66 77'});
      }), tokenProvider: () async => null, baseUrl: 'https://api.test.invalid'),
      tokenStore: store,
    );
    expect(legacy.authMode, isFalse);
    await legacy.signIn(phone: '0701020304', password: 'pw');
    expect(fideliaSent.single.url.path, '/api/auth/login');
  });
}
