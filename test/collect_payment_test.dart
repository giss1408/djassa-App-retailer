import 'dart:convert';

import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:fidelia_merchant/core/payment_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_api.dart';

/// Getting paid by QR: what the merchant app sends and how it reads the
/// request's life (open -> processing -> paid, or expired / cancelled).
void main() {
  late List<http.Request> sent;

  PaymentApi api(http.Response Function(http.Request) respond) => PaymentApi(ApiClient(
        inner: MockClient((request) async {
          sent.add(request);
          return respond(request);
        }),
        tokenProvider: () async => FakeFideliaServer.validJwt(),
        baseUrl: 'https://api.test.invalid',
      ));

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, Object?> request({String status = 'open', int? points, String? wallet}) => {
        'id': 42,
        'code': 'K7Q2M9XW4P',
        'qr_payload': 'fidelia://pay/K7Q2M9XW4P',
        'amount': 2500,
        'status': status,
        'venue_name': 'Maquis Chez Awa',
        'created_at': '2026-09-30T18:00:00',
        'expires_at': '2026-09-30T18:10:00',
        'paid_at': null,
        'wallet_provider': wallet,
        'points_awarded': points,
      };

  setUp(() => sent = []);

  test('asking for a QR sends only the amount; the server names the shop', () async {
    final r = await api((_) => json(request(), 201)).request(2500);
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/api/merchant/payment-requests');
    expect(jsonDecode(sent.single.body), {'amount': 2500});
    expect(r.isOpen, isTrue);
    expect(r.qrPayload, 'fidelia://pay/K7Q2M9XW4P');
    expect(r.expiresAt, DateTime.utc(2026, 9, 30, 18, 10));
  });

  test('a paid request carries the wallet and the points the customer earned', () async {
    final r = await api((_) => json(request(status: 'paid', points: 25, wallet: 'wave'))).status(42);
    expect(sent.single.url.path, '/api/merchant/payment-requests/42');
    expect(r.isPaid, isTrue);
    expect(r.isOpen, isFalse);
    expect(r.walletProvider, 'wave');
    expect(r.pointsAwarded, 25);
  });

  test('a customer mid-payment keeps the QR open', () async {
    final r = await api((_) => json(request(status: 'processing'))).status(42);
    expect(r.isOpen, isTrue);
  });

  test('expired and cancelled requests are closed', () async {
    for (final status in ['expired', 'cancelled']) {
      final r = await api((_) => json(request(status: status))).status(42);
      expect(r.isOpen, isFalse, reason: status);
      expect(r.isPaid, isFalse, reason: status);
    }
  });

  test('the fixed counter QR is read from the server', () async {
    final code = await api((_) => json({
          'venue_id': 10,
          'name': 'Maquis Chez Awa',
          'pay_code': 'B4NJ8R2T6Z',
          'qr_payload': 'fidelia://pay/B4NJ8R2T6Z',
        })).fixedCode();
    expect(sent.single.url.path, '/api/merchant/pay-code');
    expect(code.qrPayload, 'fidelia://pay/B4NJ8R2T6Z');
  });

  test('amounts outside the server limits are caught on the phone', () {
    expect(isPayableAmount(2500), isTrue);
    expect(isPayableAmount(minPaymentAmount), isTrue);
    expect(isPayableAmount(maxPaymentAmount), isTrue);
    expect(isPayableAmount(99), isFalse);
    expect(isPayableAmount(maxPaymentAmount + 1), isFalse);
  });
}
