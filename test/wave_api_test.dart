import 'dart:convert';

import 'package:hossouko_merchant/core/net/api_client.dart';
import 'package:hossouko_merchant/core/wave_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_api.dart';

/// Points-only Wave: the merchant gets the webhook address first, then sends
/// only the signing secret. The API key is optional and sent on its own.
void main() {
  late List<http.Request> sent;

  WaveApi api(Map<String, Object?> reply) => WaveApi(ApiClient(
        inner: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode(reply), 200, headers: {'content-type': 'application/json'});
        }),
        tokenProvider: () async => FakeHossoukoServer.validJwt(),
        baseUrl: 'https://api.test.invalid',
      ));

  setUp(() => sent = []);

  test('starting sends no secret and returns the webhook address', () async {
    final c = await api({'connected': true, 'payments_enabled': false, 'webhook_configured': false, 'webhook_url': 'https://x/webhooks/wave/t'}).start();
    expect(jsonDecode(sent.single.body), isEmpty);
    expect(c.webhookUrl, 'https://x/webhooks/wave/t');
    expect(c.paymentsEnabled, isFalse);
  });

  test('saving the secret sends only the secret', () async {
    final c = await api({'connected': true, 'payments_enabled': false, 'webhook_configured': true}).connect(webhookSecret: 'whs_secret');
    expect(jsonDecode(sent.single.body), {'webhook_secret': 'whs_secret'});
    expect(c.webhookConfigured, isTrue);
  });

  test('the optional key is sent on its own', () async {
    final c = await api({'connected': true, 'payments_enabled': true, 'api_key_hint': '…abcd', 'webhook_configured': true})
        .connect(apiKey: 'wave_ci_prod_kkkkkkkkkkkk');
    expect(jsonDecode(sent.single.body), {'api_key': 'wave_ci_prod_kkkkkkkkkkkk'});
    expect(c.paymentsEnabled, isTrue);
  });
}
