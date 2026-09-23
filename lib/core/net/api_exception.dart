/// Failures the client can distinguish and act on.
///
/// The distinction that matters most on a 2G network is **"could not reach the
/// server"** versus **"the server said no"**. The first means queue the work and
/// retry; the second means retrying will waste the merchant's data bundle
/// forever. Everything below exists to keep those two apart.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  /// Whether retrying the same request later could plausibly succeed.
  bool get isRetryable;

  @override
  String toString() => '$runtimeType: $message';
}

/// No usable connection, DNS failure, TLS failure, or the request timed out.
/// The request may or may not have reached the server, so anything it created
/// must carry an idempotency key.
class NetworkException extends ApiException {
  const NetworkException(super.message);

  @override
  bool get isRetryable => true;
}

/// The token is missing, expired, or rejected (HTTP 401).
/// Retrying with the same token is pointless; the merchant must sign in again.
class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Session expired']);

  @override
  bool get isRetryable => false;
}

/// The server understood the request and refused it (4xx other than 401).
/// A validation error, a duplicate idempotency key, or a missing resource.
/// Retrying an identical request produces an identical refusal.
class ClientErrorException extends ApiException {
  const ClientErrorException(this.statusCode, super.message, {this.detail});

  final int statusCode;

  /// FastAPI's `detail` field when present. May be a string or a validation
  /// structure, so it is kept as the decoded JSON value.
  final Object? detail;

  @override
  bool get isRetryable => false;
}

/// The server failed (5xx) or a payment provider was unreachable (502 from
/// `/api/payments`). The request was well-formed, so a later retry is sound.
class ServerErrorException extends ApiException {
  const ServerErrorException(this.statusCode, super.message);

  final int statusCode;

  @override
  bool get isRetryable => true;
}

/// The response was not the JSON shape the client expects. Treated as
/// non-retryable: a captive portal login page or a proxy error page will keep
/// coming back, and retrying burns data for nothing.
class MalformedResponseException extends ApiException {
  const MalformedResponseException(super.message);

  @override
  bool get isRetryable => false;
}
