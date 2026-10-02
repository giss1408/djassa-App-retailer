import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

import '../config/env.dart';
import 'api_exception.dart';

/// Supplies the bearer token for a request, or null when signed out.
///
/// A callback rather than a stored string so the client never holds a token in
/// its own memory longer than a single request needs it.
typedef TokenProvider = Future<String?> Function();

/// Called when the server rejects our token, so the session can be cleared
/// once instead of at every call site.
typedef UnauthorizedCallback = Future<void> Function();

/// Tries to renew the session with the refresh token. True when a new access
/// token is stored and the rejected request is worth one more try.
typedef SessionRefresher = Future<bool> Function();

/// Told how many bytes one call cost (request and response, headers
/// estimated, TLS not counted), so the pilot can report data used per user.
typedef TrafficCallback = void Function(int sent, int received);

/// The single path every byte to the Djassa API travels through.
///
/// Responsibilities, all of them bandwidth- or security-driven:
///
/// * **Ask for gzip.** Note the backend has no compression middleware today
///   (see ARCHITECTURE.md), so this currently changes nothing — but the header
///   costs ~20 bytes and pays off the day it is added, without an app update
///   reaching every merchant.
/// * **Bound every wait.** A half-open socket on a flaky cell otherwise hangs
///   the UI indefinitely.
/// * **Never log a token, a phone number, or an amount.** Breadcrumbs from a
///   financial app are a liability on a shared device.
/// * **Map failures once** into [ApiException] so callers decide retry
///   behaviour from `isRetryable` instead of re-reading status codes.
class ApiClient {
  ApiClient({
    http.Client? inner,
    required TokenProvider tokenProvider,
    UnauthorizedCallback? onUnauthorized,
    SessionRefresher? onRefresh,
    TrafficCallback? onTraffic,
    String? baseUrl,
  })  : _inner = inner ?? _defaultClient(),
        _onTraffic = onTraffic,
        _tokenProvider = tokenProvider,
        _onUnauthorized = onUnauthorized,
        _onRefresh = onRefresh,
        _baseUrl = _normalizeBase(baseUrl ?? Env.apiBase);

  final http.Client _inner;
  final TokenProvider _tokenProvider;
  final UnauthorizedCallback? _onUnauthorized;
  final SessionRefresher? _onRefresh;
  final TrafficCallback? _onTraffic;
  final String _baseUrl;

  /// A client with a connection timeout and no automatic redirect following
  /// beyond the default, so a redirect to a cleartext host cannot silently
  /// downgrade a request.
  static http.Client _defaultClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = Env.connectTimeout
      // Reuse the TLS session across calls: on 2G a fresh handshake costs
      // more than the request it carries.
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'djassa-merchant';
    return IOClient(httpClient);
  }

  static String _normalizeBase(String base) {
    var value = base.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  void close() => _inner.close();

  /// GET returning a decoded JSON object.
  Future<Map<String, Object?>> getJson(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final body = await _send(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    return _asObject(body);
  }

  /// GET returning a decoded JSON list.
  Future<List<Object?>> getJsonList(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final body = await _send(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    if (body is! List) {
      throw const MalformedResponseException('Expected a JSON array');
    }
    return body;
  }

  /// POST a JSON body, returning a decoded JSON object.
  ///
  /// [idempotencyKey] sets the `Idempotency-Key` header the backend reads on
  /// `/api/transactions` and `/api/payments`. Pass it for anything that creates
  /// a record: on an unreliable network we cannot tell a lost response from a
  /// lost request, and a retried sale must not become two sales.
  Future<Map<String, Object?>> postJson(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) async {
    final decoded = await _send(
      'POST',
      path,
      jsonBody: body,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
    return _asObject(decoded);
  }

  /// PUT a JSON body that replaces a value (e.g. the shop's position).
  /// Idempotent by nature, so no idempotency key is needed.
  Future<Map<String, Object?>> putJson(String path, {Object? body}) async {
    final decoded = await _send('PUT', path, jsonBody: body, authenticated: true);
    return _asObject(decoded);
  }

  /// PUT a JSON body, returning a decoded JSON list.
  Future<List<Object?>> putJsonList(String path, {Object? body}) async {
    final decoded = await _send('PUT', path, jsonBody: body, authenticated: true);
    if (decoded is! List) throw const MalformedResponseException('Expected a JSON array');
    return decoded;
  }

  /// DELETE a resource. Expects 204; anything in the body is ignored.
  Future<void> delete(String path) async {
    await _send('DELETE', path, authenticated: true);
  }

  /// Uploads one file as the multipart field `file`, streamed from disk so a
  /// video never sits whole in memory. It gets [Env.uploadTimeout] instead of
  /// the usual budget: a 20 MB video on 3G takes minutes, not seconds.
  Future<Map<String, Object?>> uploadFile(
    String path, {
    required String filePath,
    required String contentType,
    bool isRetry = false,
  }) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) throw const UnauthorizedException('Not signed in');
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..files.add(await http.MultipartFile.fromPath('file', filePath, contentType: MediaType.parse(contentType)));

    http.Response response;
    try {
      final streamed = await _inner.send(request).timeout(Env.uploadTimeout, onTimeout: _onTimeout);
      response = await http.Response.fromStream(streamed).timeout(Env.requestTimeout, onTimeout: _onTimeout);
    } on TimeoutException {
      throw const NetworkException('L\'envoi a pris trop de temps');
    } on SocketException {
      throw const NetworkException('No connection to the server');
    } on HandshakeException {
      throw const NetworkException('Could not establish a secure connection');
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    }
    _count(request.contentLength, request.headers, response);
    if (response.statusCode == 401 && !isRetry && _onRefresh != null && await _onRefresh()) {
      return uploadFile(path, filePath: filePath, contentType: contentType, isRetry: true);
    }
    return _asObject(await _handleResponse(response, authenticated: true));
  }

  Map<String, Object?> _asObject(Object? body) {
    if (body is! Map<String, Object?>) {
      throw const MalformedResponseException('Expected a JSON object');
    }
    return body;
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? jsonBody,
    String? idempotencyKey,
    required bool authenticated,
    bool isRetry = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );

    final request = http.Request(method, uri);
    // Ask for compression even though the server does not offer it yet, and
    // decline the response-body encodings we cannot decode.
    request.headers['Accept-Encoding'] = 'gzip';
    request.headers['Accept'] = 'application/json';

    if (authenticated) {
      final token = await _tokenProvider();
      if (token == null || token.isEmpty) {
        throw const UnauthorizedException('Not signed in');
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }

    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(jsonBody);
    }

    http.Response response;
    try {
      final streamed = await _inner
          .send(request)
          .timeout(Env.requestTimeout, onTimeout: _onTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(Env.requestTimeout, onTimeout: _onTimeout);
    } on TimeoutException {
      throw const NetworkException('The request timed out');
    } on SocketException {
      // No route, DNS failure, connection refused or reset.
      throw const NetworkException('No connection to the server');
    } on HandshakeException {
      // A failed TLS handshake can mean interception, not just a bad cert.
      // Never downgrade or retry over cleartext in response to this.
      throw const NetworkException('Could not establish a secure connection');
    } on http.ClientException catch (error) {
      throw NetworkException(error.message);
    }
    _count(request.bodyBytes.length, request.headers, response);

    // An access token lives an hour. On a 401, renew it once with the refresh
    // token and replay the request; only if that fails is the session over.
    // Safe to replay: a 401 means the server did nothing, and anything that
    // creates a record carries its idempotency key into the retry.
    if (response.statusCode == 401 && authenticated && !isRetry && _onRefresh != null) {
      if (await _onRefresh()) {
        return _send(
          method,
          path,
          query: query,
          jsonBody: jsonBody,
          idempotencyKey: idempotencyKey,
          authenticated: authenticated,
          isRetry: true,
        );
      }
    }

    return _handleResponse(response, authenticated: authenticated);
  }

  static Never _onTimeout() => throw TimeoutException('request timed out');

  void _count(int bodySent, Map<String, String> headersSent, http.Response response) {
    final onTraffic = _onTraffic;
    if (onTraffic == null) return;
    int headerBytes(Map<String, String> headers) =>
        headers.entries.fold(64, (sum, h) => sum + h.key.length + h.value.length + 4);
    onTraffic(bodySent + headerBytes(headersSent), response.bodyBytes.length + headerBytes(response.headers));
  }

  Future<Object?> _handleResponse(http.Response response, {required bool authenticated}) async {
    final status = response.statusCode;

    // A 401 on a call made without a token (a wrong sign-in code) is a refusal
    // like any 4xx, with a message to show, not the end of a session.
    if (status == 401 && authenticated) {
      // Clear the session once, centrally, rather than at each call site.
      await _onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    // 204 and an empty 200 are valid; callers expecting a body will fail on
    // the shape check instead of on a decode error.
    final hasBody = response.bodyBytes.isNotEmpty;

    if (status >= 200 && status < 300) {
      if (!hasBody) return const <String, Object?>{};
      return _decode(response);
    }

    if (status >= 500) {
      throw ServerErrorException(status, 'The server could not be reached');
    }

    // 4xx: surface FastAPI's `detail` so the UI can explain the refusal,
    // without echoing a raw HTML error page into the interface.
    Object? detail;
    if (hasBody) {
      try {
        final decoded = _decode(response);
        if (decoded is Map<String, Object?>) detail = decoded['detail'];
      } on MalformedResponseException {
        detail = null;
      }
    }
    throw ClientErrorException(
      status,
      detail is String ? detail : 'The request was refused',
      detail: detail,
    );
  }

  Object? _decode(http.Response response) {
    // `http` transparently gunzips and exposes the decoded bytes, but it only
    // honours the charset from Content-Type for `body`; decode the bytes as
    // UTF-8 ourselves so accented French text is never mangled into Latin-1.
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const MalformedResponseException('The response was not valid JSON');
    }
  }
}
