import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stand-in for the Djassa backend that reproduces the behaviour the offline
/// queue depends on — above all, idempotency-key deduplication.
///
/// Modelled on `app/api/transactions.py`: a key already seen returns the
/// original transaction with status `already_processed` instead of creating a
/// second one.
class FakeDjassaServer {
  FakeDjassaServer();

  /// idempotency_key -> the transaction id assigned the first time.
  final Map<String, int> _byKey = {};
  int _nextId = 1;

  /// Requests the server received, in order. Used to prove the client batches
  /// instead of sending one request per sale.
  final List<Map<String, Object?>> receivedBatches = [];

  /// When set, every request fails this way before reaching the handler, to
  /// simulate an outage.
  Exception? failWith;

  /// Drops the response *after* recording the sale, reproducing the worst case
  /// on a flaky network: the server committed, the client never found out.
  bool dropResponseAfterCommit = false;

  /// Keys the server refuses permanently, as a validation failure would.
  final Set<String> rejectKeys = {};

  /// Distinct transactions the server believes it created.
  int get transactionCount => _byKey.length;

  http.Client client() {
    return MockClient((request) async {
      final failure = failWith;
      if (failure != null) throw failure;

      if (request.url.path == '/api/token') {
        return _tokenResponse(request);
      }
      if (request.url.path == '/api/transactions/sync') {
        return _syncResponse(request);
      }
      return http.Response('{"detail":"not found"}', 404,
          headers: {'content-type': 'application/json'});
    });
  }

  http.Response _tokenResponse(http.Request request) {
    final fields = Uri.splitQueryString(request.body);
    if (fields['username'] == 'demo' && fields['password'] == 'demo123') {
      return http.Response(
        jsonEncode({'access_token': validJwt(), 'token_type': 'bearer'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({'detail': 'Incorrect username or password'}),
      401,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response _syncResponse(http.Request request) {
    if (request.headers['authorization']?.startsWith('Bearer ') != true) {
      return http.Response(jsonEncode({'detail': 'Not authenticated'}), 401,
          headers: {'content-type': 'application/json'});
    }

    final body = jsonDecode(request.body) as Map<String, Object?>;
    receivedBatches.add(body);
    final operations = (body['operations'] as List).cast<Map<String, Object?>>();

    // The backend caps a batch at 50 operations.
    if (operations.isEmpty || operations.length > 50) {
      return http.Response(jsonEncode({'detail': 'invalid batch size'}), 422,
          headers: {'content-type': 'application/json'});
    }

    final results = <Map<String, Object?>>[];
    for (final op in operations) {
      final key = op['idempotency_key'] as String;

      if (rejectKeys.contains(key)) {
        results.add({
          'idempotency_key': key,
          'status': 'rejected',
          'error': 'operation could not be processed',
        });
        continue;
      }

      final existing = _byKey[key];
      if (existing != null) {
        results.add({
          'idempotency_key': key,
          'status': 'already_processed',
          'transaction': _transaction(existing, op),
        });
        continue;
      }

      final id = _nextId++;
      _byKey[key] = id;
      results.add({
        'idempotency_key': key,
        'status': 'accepted',
        'transaction': _transaction(id, op),
      });
    }

    if (dropResponseAfterCommit) {
      // Committed above, then the connection dies.
      throw http.ClientException('Connection closed before full header');
    }

    return http.Response(
      jsonEncode({'results': results}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  Map<String, Object?> _transaction(int id, Map<String, Object?> op) => {
        'id': id,
        'merchant_id': op['merchant_id'],
        'user_id': 'demo',
        'amount': op['amount'],
        'currency': op['currency'],
        'type': op['type'],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

  /// An unsigned token shaped like the backend's HS256 JWT. Only the payload is
  /// ever read client-side, and only to avoid a doomed round trip.
  static String validJwt({Duration validFor = const Duration(hours: 24)}) {
    String seg(Map<String, Object?> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final exp =
        DateTime.now().toUtc().add(validFor).millisecondsSinceEpoch ~/ 1000;
    return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${seg({'sub': 'demo', 'exp': exp})}.'
        'signature-not-verified-client-side';
  }

  static String expiredJwt() => validJwt(validFor: const Duration(hours: -1));
}
