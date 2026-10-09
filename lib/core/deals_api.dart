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
}
