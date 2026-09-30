import 'net/api_client.dart';

/// The merchant's own Wave Business account, as connected on the server
/// (`app/api/wave.py`). The key and the signing secret go up once and never
/// come back: the server keeps them sealed and returns only a hint.
class WaveConnection {
  const WaveConnection({required this.connected, this.keyHint, this.webhookConfigured = false, this.webhookUrl, this.lastEventAt});

  final bool connected;

  /// "…a1B2": enough to recognise which key is connected.
  final String? keyHint;
  final bool webhookConfigured;

  /// The address to paste into the Wave portal's webhook form.
  final String? webhookUrl;
  final DateTime? lastEventAt;

  factory WaveConnection.fromJson(Map<String, Object?> json) => WaveConnection(
        connected: json['connected'] as bool? ?? false,
        keyHint: json['api_key_hint'] as String?,
        webhookConfigured: json['webhook_configured'] as bool? ?? false,
        webhookUrl: json['webhook_url'] as String?,
        lastEventAt: json['last_event_at'] is String ? DateTime.tryParse('${json['last_event_at']}Z')?.toLocal() : null,
      );
}

class WaveApi {
  WaveApi(this._client);

  final ApiClient _client;

  Future<WaveConnection> mine() async => WaveConnection.fromJson(await _client.getJson('/api/merchant/wave'));

  /// Omit [apiKey] only when already connected: then only the secret changes.
  Future<WaveConnection> connect({required String apiKey, String? webhookSecret}) async =>
      WaveConnection.fromJson(await _client.putJson('/api/merchant/wave', body: {
        'api_key': apiKey,
        if (webhookSecret != null && webhookSecret.isNotEmpty) 'webhook_secret': webhookSecret,
      }));

  Future<void> disconnect() => _client.delete('/api/merchant/wave');
}
