import 'dart:convert';
import 'dart:io';

import 'package:fidelia_merchant/core/media_api.dart';
import 'package:fidelia_merchant/core/net/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_api.dart';

void main() {
  test('content types follow the picked file', () {
    expect(MediaApi.contentTypeFor('/x/IMG_1.jpg'), 'image/jpeg');
    expect(MediaApi.contentTypeFor('/x/a.PNG'), 'image/png');
    expect(MediaApi.contentTypeFor('/x/VID.mp4'), 'video/mp4');
    expect(MediaApi.contentTypeFor('/x/clip.mov'), 'video/quicktime');
  });

  test('an upload is one multipart request with the file and its type', () async {
    final dir = await Directory.systemTemp.createTemp('fidelia-upload-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/shop.jpg')..writeAsBytesSync(List.filled(2048, 7));
    late http.BaseRequest seen;
    late String body;
    final api = MediaApi(ApiClient(
      inner: MockClient.streaming((request, stream) async {
        seen = request;
        body = latin1.decode(await stream.toBytes());
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'id': 9, 'kind': 'image', 'status': 'ready', 'position': 1, 'thumb_url': 'https://m/t.webp'}))),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
      tokenProvider: () async => FakeFideliaServer.validJwt(),
      baseUrl: 'https://api.test.invalid',
    ));

    final media = await api.upload(file.path);
    expect(media.status, 'ready');
    expect(seen.url.path, '/api/merchant/media');
    expect(seen.headers['Content-Type'], startsWith('multipart/form-data'));
    expect(body, contains('name="file"; filename="shop.jpg"'));
    expect(body, contains('content-type: image/jpeg'));
  });
}
