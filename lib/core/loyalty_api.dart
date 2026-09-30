import 'net/api_client.dart';

/// A customer's standing at this merchant's venue, looked up by phone.
class CounterLoyalty {
  const CounterLoyalty({required this.customer, required this.points, required this.rewards});

  /// The number, masked by the server ("07 •• •• 56 78"): enough to check it
  /// was typed right without repeating it on screen.
  final String customer;
  final int points;
  final List<CounterReward> rewards;

  factory CounterLoyalty.fromJson(Map<String, Object?> json) => CounterLoyalty(
        customer: json['customer'] as String,
        points: json['points'] as int,
        rewards: [
          for (final r in (json['rewards'] as List<Object?>))
            CounterReward.fromJson(r! as Map<String, Object?>),
        ],
      );
}

class CounterReward {
  const CounterReward({required this.id, required this.title, required this.costPoints});

  final int id;
  final String title;
  final int costPoints;

  factory CounterReward.fromJson(Map<String, Object?> json) => CounterReward(
        id: json['id'] as int,
        title: json['title'] as String,
        costPoints: json['cost_points'] as int,
      );
}

class Voucher {
  const Voucher({required this.code, required this.rewardTitle, required this.remainingPoints});

  final String code;
  final String rewardTitle;
  final int remainingPoints;

  factory Voucher.fromJson(Map<String, Object?> json) => Voucher(
        code: json['voucher_code'] as String,
        rewardTitle: json['reward_title'] as String,
        remainingPoints: json['remaining_points'] as int,
      );
}

/// Loyalty at the counter (`app/api/counter_loyalty.py`): for customers who
/// pay cash and give their number, with or without the customer app.
///
/// Both calls are POSTs so the customer's number never sits in a URL, where
/// proxies and access logs would keep it.
class LoyaltyApi {
  LoyaltyApi(this._client);

  final ApiClient _client;

  Future<CounterLoyalty> lookUp(String phone) async =>
      CounterLoyalty.fromJson(await _client.postJson('/api/merchant/customers/loyalty', body: {'phone': phone}));

  Future<Voucher> redeem({required String phone, required int rewardId}) async => Voucher.fromJson(
        await _client.postJson('/api/merchant/customers/redeem', body: {'phone': phone, 'reward_id': rewardId}),
      );
}
