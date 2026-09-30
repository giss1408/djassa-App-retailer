import 'net/api_client.dart';

/// Where the shop is, as saved on the server (`app/api/venue_location.py`).
class ShopLocation {
  const ShopLocation({this.latitude, this.longitude, this.accuracyM, this.source, this.setAt});

  final double? latitude;
  final double? longitude;
  final int? accuracyM;

  /// "merchant_gps" when taken from this app in the shop, "admin" otherwise.
  final String? source;
  final DateTime? setAt;

  bool get isSet => latitude != null && longitude != null;

  factory ShopLocation.fromJson(Map<String, Object?> json) => ShopLocation(
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracyM: json['accuracy_m'] as int?,
        source: json['source'] as String?,
        setAt: json['set_at'] is String ? DateTime.tryParse('${json['set_at']}Z')?.toLocal() : null,
      );
}

class LocationApi {
  LocationApi(this._client);

  final ApiClient _client;

  Future<ShopLocation> mine() async => ShopLocation.fromJson(await _client.getJson('/api/merchant/venue/location'));

  Future<ShopLocation> save({required double latitude, required double longitude, required double accuracyM}) async =>
      ShopLocation.fromJson(await _client.putJson('/api/merchant/venue/location', body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
      }));
}

/// A GPS fix good enough to put the shop on the right street. The server
/// refuses anything above [maxSavableAccuracyM]; the screen waits for
/// [targetAccuracyM] and stops early when it gets there.
const double targetAccuracyM = 25;
const double maxSavableAccuracyM = 100;

bool isSavable(double accuracyM) => accuracyM > 0 && accuracyM <= maxSavableAccuracyM;
