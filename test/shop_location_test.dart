import 'dart:convert';

import 'package:hossouko_merchant/core/location_api.dart';
import 'package:hossouko_merchant/core/net/api_client.dart';
import 'package:hossouko_merchant/core/net/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_api.dart';

/// The shop's position, taken from the merchant's phone in the shop, so
/// customers get directions to it. The GPS itself is a device capability and
/// is exercised on a real phone; these cover what the app sends and reads.
void main() {
  late List<http.Request> sent;

  ApiClient client(http.Response Function(http.Request) respond) => ApiClient(
        inner: MockClient((request) async {
          sent.add(request);
          return respond(request);
        }),
        tokenProvider: () async => FakeHossoukoServer.validJwt(),
        baseUrl: 'https://api.test.invalid',
      );

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  setUp(() => sent = []);

  test('saving sends the fix with its precision, as a PUT', () async {
    final api = LocationApi(client((_) => json({
          'venue_id': 10,
          'venue_name': 'Maquis Chez Awa',
          'latitude': 5.3197,
          'longitude': -4.0165,
          'accuracy_m': 12,
          'source': 'merchant_gps',
          'set_at': '2026-09-30T17:00:00',
        })));

    final saved = await api.save(latitude: 5.3197, longitude: -4.0165, accuracyM: 12.4);

    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, '/api/merchant/venue/location');
    expect(sent.single.headers['authorization'], startsWith('Bearer '));
    expect(jsonDecode(sent.single.body), {'latitude': 5.3197, 'longitude': -4.0165, 'accuracy_m': 12.4});
    expect(saved.isSet, isTrue);
    expect(saved.accuracyM, 12);
    expect(saved.source, 'merchant_gps');
    expect(saved.setAt, isNotNull);
  });

  test('a shop without a position reads as not set', () async {
    final api = LocationApi(client((_) => json({
          'venue_id': 10,
          'venue_name': 'Maquis Chez Awa',
          'latitude': null,
          'longitude': null,
          'accuracy_m': null,
          'source': null,
          'set_at': null,
        })));
    final mine = await api.mine();
    expect(sent.single.method, 'GET');
    expect(mine.isSet, isFalse);
  });

  test("the server's refusal reaches the screen in its own words", () async {
    final api = LocationApi(client((_) => json({'detail': 'Position trop imprécise (450 m).'}, 422)));
    await expectLater(
      api.save(latitude: 5.3, longitude: -4.0, accuracyM: 450),
      throwsA(isA<ClientErrorException>().having((e) => e.detail, 'detail', 'Position trop imprécise (450 m).')),
    );
  });

  test('only a fix precise enough to find the street is saved', () {
    expect(isSavable(8), isTrue);
    expect(isSavable(maxSavableAccuracyM), isTrue);
    expect(isSavable(maxSavableAccuracyM + 1), isFalse);
    expect(isSavable(0), isFalse);
    expect(targetAccuracyM, lessThan(maxSavableAccuracyM));
  });
}
