import 'net/api_client.dart';

/// One request to change where customers' payments are paid out (`app/api/wallet_change.py`).
class WalletChange {
  const WalletChange({
    required this.id,
    required this.status,
    required this.provider,
    required this.accountMasked,
    this.codeSent = false,
    this.activatesAt,
    this.activatedAt,
  });

  final int id;

  /// pending_confirmation | confirmed_waiting | active | frozen | rejected | cancelled
  final String status;
  final String provider;

  /// "••••1111": the full number never comes back from the server.
  final String accountMasked;
  final bool codeSent;
  final DateTime? activatesAt;
  final DateTime? activatedAt;

  bool get isOpen => status == 'pending_confirmation' || status == 'confirmed_waiting' || status == 'frozen';

  factory WalletChange.fromJson(Map<String, Object?> json) => WalletChange(
        id: json['id']! as int,
        status: json['status']! as String,
        provider: json['provider']! as String,
        accountMasked: json['account_masked'] as String? ?? '',
        codeSent: json['code_sent'] as bool? ?? false,
        activatesAt: _utc(json['activates_at']),
        activatedAt: _utc(json['activated_at']),
      );
}

/// The shop's active wallet and its open (or last) change.
class WalletState {
  const WalletState({this.provider, this.accountMasked, this.activeSince, this.capXof, this.change});

  final String? provider;
  final String? accountMasked;
  final DateTime? activeSince;

  /// Set during the first week of a new wallet: the most the shop can receive in total.
  final int? capXof;
  final WalletChange? change;

  bool get hasWallet => accountMasked != null;

  factory WalletState.fromJson(Map<String, Object?> json) => WalletState(
        provider: json['provider'] as String?,
        accountMasked: json['account_masked'] as String?,
        activeSince: _utc(json['active_since']),
        capXof: json['cap_xof'] as int?,
        change: json['change'] is Map ? WalletChange.fromJson((json['change']! as Map).cast<String, Object?>()) : null,
      );
}

DateTime? _utc(Object? v) => v is String ? DateTime.tryParse(v.endsWith('Z') ? v : '${v}Z')?.toLocal() : null;

/// Proves the password again just before a wallet change. Wired when the app signs in through the platform auth service
/// (`POST /v1/step-up` there returns a fresh token that the API client then uses). Until then the default refuses, and the
/// server would refuse a legacy session anyway (`auth_login_required`).
typedef StepUp = Future<void> Function(String password);

class StepUpUnavailable implements Exception {
  const StepUpUnavailable();
}

/// Owner only. Everything the server needs to keep the shop's money safe is checked THERE; this class only talks to it.
class WalletChangeApi {
  WalletChangeApi(this._client);

  final ApiClient _client;

  Future<WalletState> mine() async => WalletState.fromJson(await _client.getJson('/api/merchant/wallet'));

  Future<WalletChange> request({required String provider, required String account}) async =>
      WalletChange.fromJson(await _client.postJson('/api/merchant/wallet-change', body: {'provider': provider, 'account': account}));

  /// The 6-digit code an admin sent to the merchant's own WhatsApp.
  Future<WalletChange> confirm(String code) async =>
      WalletChange.fromJson(await _client.postJson('/api/merchant/wallet-change/confirm', body: {'code': code}));

  /// "Ce n'etait pas moi": freezes the change and alerts the team. Always available, it only makes things safer.
  Future<WalletChange> notMe() async => WalletChange.fromJson(await _client.postJson('/api/merchant/wallet-change/not-me', body: {}));

  Future<WalletChange> cancel() async => WalletChange.fromJson(await _client.postJson('/api/merchant/wallet-change/cancel', body: {}));
}
