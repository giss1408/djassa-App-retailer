import 'net/api_client.dart';

/// Whether this shop offers "payer en plusieurs fois", its limits, and the
/// terms to read to the customer (`app/api/layaway.py`).
class LayawaySettings {
  const LayawaySettings({
    required this.enabled,
    required this.maxDays,
    required this.maxPrice,
    required this.termsVersion,
    required this.terms,
  });

  final bool enabled;
  final int maxDays;
  final int maxPrice;

  /// Sent back when a plan is opened, so the server knows which wording the
  /// customer agreed to.
  final String termsVersion;

  /// With `{item}`, `{price}` and `{due_by}` placeholders; see [termsFor].
  final String terms;

  factory LayawaySettings.fromJson(Map<String, Object?> json) => LayawaySettings(
        enabled: json['enabled'] as bool? ?? false,
        maxDays: json['max_days'] as int,
        maxPrice: json['max_price'] as int,
        termsVersion: json['terms_version'] as String,
        terms: json['terms'] as String,
      );

  /// The terms as the customer hears them, for this good, price and date.
  String termsFor({required String item, required String price, required String dueBy}) =>
      terms.replaceAll('{item}', item).replaceAll('{price}', price).replaceAll('{due_by}', dueBy);
}

class LayawayInstallment {
  const LayawayInstallment({required this.amount, required this.paidAt});

  final int amount;
  final DateTime paidAt;

  factory LayawayInstallment.fromJson(Map<String, Object?> json) => LayawayInstallment(
        amount: json['amount'] as int,
        paidAt: _date(json['paid_at'])!,
      );
}

/// One good paid in several installments. The merchant keeps the money; the
/// server keeps the record.
class LayawayPlan {
  const LayawayPlan({
    required this.id,
    required this.customer,
    required this.item,
    required this.price,
    required this.paid,
    required this.remaining,
    required this.status,
    required this.dueBy,
    required this.installments,
    this.refundedAmount,
  });

  final int id;

  /// Masked by the server ("07 •• •• 56 78").
  final String? customer;
  final String item;
  final int price;
  final int paid;
  final int remaining;

  /// open | completed (paid, not yet handed over) | delivered | cancelled.
  final String status;
  final DateTime dueBy;
  final List<LayawayInstallment> installments;
  final int? refundedAmount;

  bool get isOpen => status == 'open';
  bool get readyToHandOver => status == 'completed';
  bool get isClosed => status == 'delivered' || status == 'cancelled';
  bool get isOverdue => isOpen && dueBy.isBefore(DateTime.now());
  double get progress => price == 0 ? 0 : (paid / price).clamp(0, 1).toDouble();

  factory LayawayPlan.fromJson(Map<String, Object?> json) => LayawayPlan(
        id: json['id'] as int,
        customer: json['customer'] as String?,
        item: json['item'] as String,
        price: json['price'] as int,
        paid: json['paid'] as int,
        remaining: json['remaining'] as int,
        status: json['status'] as String,
        dueBy: _date(json['due_by'])!,
        refundedAmount: json['refunded_amount'] as int?,
        installments: [
          for (final i in (json['installments'] as List<Object?>? ?? const []))
            LayawayInstallment.fromJson(i! as Map<String, Object?>),
        ],
      );
}

/// The server sends naive UTC timestamps.
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value.endsWith('Z') ? value : '${value}Z')?.toLocal() : null;

/// "Payer en plusieurs fois" at the counter. Needs a connection: the balance
/// lives on the server, so two staff phones cannot both take the last payment.
/// Every write carries a key made before the first send, so a retry after a
/// dropped response is counted once.
class LayawayApi {
  LayawayApi(this._client);

  final ApiClient _client;

  Future<LayawaySettings> settings() async =>
      LayawaySettings.fromJson(await _client.getJson('/api/merchant/layaway/settings'));

  Future<List<LayawayPlan>> list() async {
    final list = await _client.getJsonList('/api/merchant/layaway');
    return [for (final p in list) LayawayPlan.fromJson(p! as Map<String, Object?>)];
  }

  Future<LayawayPlan> open({
    required String customerPhone,
    required String item,
    required int price,
    required DateTime dueBy,
    required String termsVersion,
    required String key,
    int? firstInstallment,
  }) async =>
      LayawayPlan.fromJson(await _client.postJson('/api/merchant/layaway', body: {
        'customer_phone': customerPhone,
        'item': item,
        'price': price,
        'due_by': dueBy.toUtc().toIso8601String(),
        'terms_version': termsVersion,
        'terms_accepted': true,
        if (firstInstallment != null && firstInstallment > 0)
          'first_installment': {'amount': firstInstallment, 'idempotency_key': key},
      }));

  Future<LayawayPlan> pay(int planId, {required int amount, required String key}) async => LayawayPlan.fromJson(
        await _client
            .postJson('/api/merchant/layaway/$planId/installments', body: {'amount': amount, 'idempotency_key': key}),
      );

  Future<LayawayPlan> handOver(int planId) async =>
      LayawayPlan.fromJson(await _client.postJson('/api/merchant/layaway/$planId/deliver'));

  /// Owner only. Records what the merchant handed back; moves nothing.
  Future<LayawayPlan> cancel(int planId, {required String reason, required int refunded}) async =>
      LayawayPlan.fromJson(await _client
          .postJson('/api/merchant/layaway/$planId/cancel', body: {'reason': reason, 'refunded_amount': refunded}));
}
