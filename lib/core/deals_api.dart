import 'model/deal.dart';
import 'net/api_client.dart';

/// The merchant's own deals ("bons plans") on the Fidelia customer app.
class DealsApi {
  DealsApi(this._client);

  final ApiClient _client;

  Future<List<Deal>> mine() async {
    final list = await _client.getJsonList('/api/merchant/deals');
    return [for (final d in list) Deal.fromJson(d! as Map<String, Object?>)];
  }

  Future<Deal> publish(DealDraft draft) async =>
      Deal.fromJson(await _client.postJson('/api/merchant/deals', body: draft.toJson(DateTime.now())));

  /// Ends a deal now. Customers stop seeing it immediately.
  Future<void> end(int id) => _client.delete('/api/merchant/deals/$id');

  /// A customer came to the counter with this deal. [key] is made once per
  /// tap, so retrying after a dropped connection records one visit, not two.
  Future<void> recordUse(int dealId, {required bool newCustomer, required String key}) =>
      _client.postJson('/api/merchant/deals/$dealId/uses', body: {'idempotency_key': key, 'new_customer': newCustomer});

  /// Customers who came with a deal over the last 7 days, and how many were new.
  Future<DealUseSummary> useSummary() async =>
      DealUseSummary.fromJson(await _client.getJson('/api/merchant/deals/uses/summary'));
}
