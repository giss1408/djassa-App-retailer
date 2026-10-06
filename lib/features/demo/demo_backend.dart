import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../l10n/strings.dart';

/// A pretend Djassa server, inside the app, for the demo mode.
///
/// The demo runs the real screens against this instead of the network, so a
/// merchant can try everything before having an account and nothing they do
/// reaches Djassa. It answers what a merchant can safely play with (sales,
/// points at the counter, offers) from memory, and refuses, in French, what
/// only makes sense with a real shop: payment QR codes, Wave, photos, the
/// team, the shop's position.
class DemoBackend extends http.BaseClient {
  DemoBackend({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock().toUtc();
    _deals.addAll([
      _deal('Garba + alloco', price: 1000, original: 1500, ribbon: 'bon_plan', ends: now.add(const Duration(days: 5))),
      _deal('Poulet braise du midi', percent: 30, ribbon: 'flash', ends: now.add(const Duration(hours: 6))),
      _deal('Jus de bissap offert', price: 0, ribbon: 'promo', ends: now.add(const Duration(days: 2))),
    ]);
    // A regular, so "Points client" has someone to find.
    _points[_regular] = 120;
  }

  final DateTime Function() _clock;
  final _deals = <Map<String, Object?>>[];
  final _points = <String, int>{};
  int _nextId = 1;

  static const _regular = '+2250712345678';
  static const _rewards = [
    {'id': 1, 'title': 'Un jus offert', 'cost_points': 50},
    {'id': 2, 'title': 'Un plat offert', 'cost_points': 150},
  ];

  Map<String, Object?> _deal(String title, {int? price, int? original, int? percent, required String ribbon, required DateTime ends}) => {
        'id': _nextId++,
        'title': title,
        'price': price,
        'original_price': original,
        'discount_percent': percent,
        'ribbon': ribbon,
        'is_featured': false,
        'ends_at': _wire(ends),
      };

  /// The backend's naive-UTC timestamp form.
  static String _wire(DateTime t) => t.toUtc().toIso8601String().replaceAll('Z', '');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request && request.body.isNotEmpty ? jsonDecode(request.body) : null;
    final (status, json) = _route(request.method, request.url.path, body);
    final bytes = utf8.encode(jsonEncode(json));
    return http.StreamedResponse(Stream.value(bytes), status,
        headers: {'content-type': 'application/json; charset=utf-8'}, request: request);
  }

  (int, Object?) _route(String method, String path, Object? body) {
    final map = body is Map ? body : const {};
    switch ((method, path)) {
      case ('GET', '/api/merchant/deals'):
        return (200, _deals);
      case ('POST', '/api/merchant/deals'):
        final deal = {...map.cast<String, Object?>(), 'id': _nextId++, 'is_featured': false};
        _deals.insert(0, deal);
        return (201, deal);
      case ('POST', '/api/merchant/sales/sync'):
        final ops = (map['operations'] as List?) ?? const [];
        return (200, {'results': [for (final op in ops) _sale(op as Map)]});
      case ('POST', '/api/merchant/sales'):
        return (201, _sale(map)['sale']);
      case ('POST', '/api/merchant/customers/loyalty'):
        final phone = _phone(map['phone']);
        return (200, {'customer': _masked(phone), 'points': _points[phone] ?? 0, 'rewards': _rewards});
      case ('POST', '/api/merchant/customers/redeem'):
        return _redeem(_phone(map['phone']), map['reward_id']);
      case ('GET', '/api/merchant/wave'):
        return (200, {'connected': false});
      case ('GET', '/api/merchant/venue/location'):
        return (200, <String, Object?>{});
      case ('GET', '/api/merchant/staff'):
      case ('GET', '/api/merchant/media'):
        return (200, <Object?>[]);
      case ('GET', '/api/support/suggestions/whatsapp'):
        return (200, {'available': false});
      case ('POST', '/api/auth/logout'):
        return (200, <String, Object?>{});
    }
    final end = RegExp(r'^/api/merchant/deals/(\d+)$').firstMatch(path);
    if (method == 'DELETE' && end != null) {
      _deals.removeWhere((d) => d['id'] == int.parse(end.group(1)!));
      return (204, null);
    }
    // Everything tied to a real shop or a real account.
    return (403, {'detail': Strings.demoNeedsAccount});
  }

  Map<String, Object?> _sale(Map op) {
    final amount = num.tryParse('${op['amount']}') ?? 0;
    final phone = op['customer_phone'] is String ? op['customer_phone'] as String : null;
    final points = phone != null && op['customer_consent'] == true ? amount ~/ 100 : 0;
    if (points > 0) _points[phone!] = (_points[phone] ?? 0) + points;
    return {
      'idempotency_key': op['idempotency_key'],
      'status': 'accepted',
      'sale': {'id': _nextId++, 'points_awarded': points},
    };
  }

  (int, Object?) _redeem(String phone, Object? rewardId) {
    final reward = _rewards.firstWhere((r) => r['id'] == rewardId, orElse: () => const {});
    if (reward.isEmpty) return (404, {'detail': 'reward not found'});
    final cost = reward['cost_points']! as int;
    final balance = _points[phone] ?? 0;
    if (balance < cost) return (409, {'detail': 'not enough points: $balance of $cost'});
    _points[phone] = balance - cost;
    return (201, {
      'voucher_code': 'DEMO42',
      'reward_title': reward['title'],
      'venue_name': Strings.demoShopName,
      'points_spent': cost,
      'remaining_points': balance - cost,
    });
  }

  static String _phone(Object? raw) {
    final digits = '$raw'.replaceAll(RegExp(r'\D'), '');
    final local = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    return '+225$local';
  }

  static String _masked(String e164) {
    final local = e164.substring(4);
    return local.length < 4 ? local : '${local.substring(0, 2)} •• •• ${local.substring(local.length - 4, local.length - 2)} ${local.substring(local.length - 2)}';
  }
}
