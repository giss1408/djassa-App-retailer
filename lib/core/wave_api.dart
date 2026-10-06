import 'net/api_client.dart';

/// The merchant's own Wave Business account, as connected on the server
/// (`app/api/wave.py`). Secrets go up once and never come back: the server
/// keeps them sealed and returns only a hint.
///
/// Points only (the default) needs just the webhook's signing secret, which
/// cannot create or move a payment. The API key is optional and only enables
/// paying the shop from inside the Hossouko app.
class WaveConnection {
  const WaveConnection({
    required this.connected,
    this.keyHint,
    this.paymentsEnabled = false,
    this.webhookConfigured = false,
    this.webhookUrl,
    this.lastEventAt,
  });

  final bool connected;

  /// A key is connected: customers can pay the shop from the Hossouko app.
  final bool paymentsEnabled;

  /// "…a1B2": enough to recognise which key is connected.
  final String? keyHint;
  final bool webhookConfigured;

  /// The address to paste into the Wave portal's webhook form.
  final String? webhookUrl;
  final DateTime? lastEventAt;

  factory WaveConnection.fromJson(Map<String, Object?> json) => WaveConnection(
        connected: json['connected'] as bool? ?? false,
        keyHint: json['api_key_hint'] as String?,
        paymentsEnabled: json['payments_enabled'] as bool? ?? false,
        webhookConfigured: json['webhook_configured'] as bool? ?? false,
        webhookUrl: json['webhook_url'] as String?,
        lastEventAt: json['last_event_at'] is String ? DateTime.tryParse('${json['last_event_at']}Z')?.toLocal() : null,
      );
}

class WaveApi {
  WaveApi(this._client);

  final ApiClient _client;

  Future<WaveConnection> mine() async => WaveConnection.fromJson(await _client.getJson('/api/merchant/wave'));

  /// Creates the connection and its webhook address, with no secret yet:
  /// the merchant needs the address before Wave gives them the secret.
  Future<WaveConnection> start() => connect();

  /// Only what is given changes on the server.
  Future<WaveConnection> connect({String? apiKey, String? webhookSecret}) async =>
      WaveConnection.fromJson(await _client.putJson('/api/merchant/wave', body: {
        if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
        if (webhookSecret != null && webhookSecret.isNotEmpty) 'webhook_secret': webhookSecret,
      }));

  Future<void> disconnect() => _client.delete('/api/merchant/wave');
}
