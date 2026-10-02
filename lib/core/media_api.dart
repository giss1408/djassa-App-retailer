import 'net/api_client.dart';

/// A photo or video of the shop, as the server reports it
/// (`app/api/media.py`). The server shrinks every upload; [thumbUrl] is the
/// only image this app loads, so the screen stays cheap on a prepaid bundle.
class ShopMedia {
  const ShopMedia({
    required this.id,
    required this.kind,
    required this.status,
    this.error,
    this.thumbUrl,
    this.videoBytes,
    this.durationS,
  });

  final int id;

  /// "image" or "video".
  final String kind;

  /// "processing", "ready" or "failed".
  final String status;

  /// Why it failed, in French, ready to show.
  final String? error;
  final String? thumbUrl;
  final int? videoBytes;
  final int? durationS;

  bool get isVideo => kind == 'video';

  factory ShopMedia.fromJson(Map<String, Object?> json) => ShopMedia(
        id: json['id']! as int,
        kind: json['kind']! as String,
        status: json['status']! as String,
        error: json['error'] as String?,
        thumbUrl: json['thumb_url'] as String?,
        videoBytes: json['video_bytes'] as int?,
        durationS: json['duration_s'] as int?,
      );
}

class MediaApi {
  MediaApi(this._client);

  final ApiClient _client;

  static const maxImages = 10;
  static const maxVideos = 3;

  Future<List<ShopMedia>> mine() async => [
        for (final m in await _client.getJsonList('/api/merchant/media')) ShopMedia.fromJson(m! as Map<String, Object?>),
      ];

  Future<ShopMedia> upload(String filePath) async =>
      ShopMedia.fromJson(await _client.uploadFile('/api/merchant/media', filePath: filePath, contentType: contentTypeFor(filePath)));

  Future<void> delete(int id) => _client.delete('/api/merchant/media/$id');

  /// Moves [id] first, keeping the others in their order.
  Future<List<ShopMedia>> putFirst(int id, List<ShopMedia> current) async {
    final ids = [id, ...current.map((m) => m.id).where((other) => other != id)];
    final body = await _client.putJsonList('/api/merchant/media/order', body: {'ids': ids});
    return [for (final m in body) ShopMedia.fromJson(m! as Map<String, Object?>)];
  }

  /// The type the server checks, from the file name the picker returns.
  static String contentTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      '3gp' => 'video/3gpp',
      'webm' => 'video/webm',
      _ => 'image/jpeg',
    };
  }
}
