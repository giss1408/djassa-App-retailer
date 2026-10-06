import 'net/api_client.dart';

/// A one-time payment QR for a given amount (`app/api/payment_requests.py`).
///
/// open -> processing (the customer is paying) -> paid; or open -> expired |
/// cancelled. A declined wallet puts it back to open, payable again.
class PaymentRequest {
  const PaymentRequest({
    required this.id,
    required this.code,
    required this.qrPayload,
    required this.amount,
    required this.status,
    required this.expiresAt,
    this.walletProvider,
    this.pointsAwarded,
  });

  final int id;

  /// The code under the QR, for a customer whose camera cannot scan.
  final String code;

  /// The exact text in the QR (`hossouko://pay/<code>`), as the server built it.
  final String qrPayload;
  final int amount;
  final String status;
  final DateTime expiresAt;
  final String? walletProvider;
  final int? pointsAwarded;

  bool get isOpen => status == 'open' || status == 'processing';
  bool get isPaid => status == 'paid';

  factory PaymentRequest.fromJson(Map<String, Object?> json) => PaymentRequest(
        id: json['id'] as int,
        code: json['code'] as String,
        qrPayload: json['qr_payload'] as String,
        amount: json['amount'] as int,
        status: json['status'] as String,
        expiresAt: _utc(json['expires_at'] as String),
        walletProvider: json['wallet_provider'] as String?,
        pointsAwarded: json['points_awarded'] as int?,
      );
}

/// The shop's fixed QR, for a sticker on the counter; the customer types the
/// amount.
class ShopPayCode {
  const ShopPayCode({required this.name, required this.code, required this.qrPayload});

  final String name;
  final String code;
  final String qrPayload;

  factory ShopPayCode.fromJson(Map<String, Object?> json) => ShopPayCode(
        name: json['name'] as String,
        code: json['pay_code'] as String,
        qrPayload: json['qr_payload'] as String,
      );
}

/// The backend sends naive UTC timestamps.
DateTime _utc(String value) {
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.parse(hasZone ? value : '${value}Z');
}

class PaymentApi {
  PaymentApi(this._client);

  final ApiClient _client;

  Future<PaymentRequest> request(int amount) async =>
      PaymentRequest.fromJson(await _client.postJson('/api/merchant/payment-requests', body: {'amount': amount}));

  /// Polled by the QR screen while the request is open.
  Future<PaymentRequest> status(int id) async =>
      PaymentRequest.fromJson(await _client.getJson('/api/merchant/payment-requests/$id'));

  Future<PaymentRequest> cancel(int id) async =>
      PaymentRequest.fromJson(await _client.postJson('/api/merchant/payment-requests/$id/cancel'));

  Future<ShopPayCode> fixedCode() async => ShopPayCode.fromJson(await _client.getJson('/api/merchant/pay-code'));
}

/// The server's limits for one payment request (PaymentRequestIn).
const int minPaymentAmount = 100;
const int maxPaymentAmount = 2000000;

bool isPayableAmount(int amount) => amount >= minPaymentAmount && amount <= maxPaymentAmount;
