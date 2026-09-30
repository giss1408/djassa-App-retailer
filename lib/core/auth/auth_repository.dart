import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'token_store.dart';

/// Outcome of a sign-in attempt, as something the UI can render directly.
sealed class SignInResult {
  const SignInResult();
}

class SignInSuccess extends SignInResult {
  const SignInSuccess(this.username);
  final String username;
}

/// The server rejected the credentials. Distinct from [SignInUnavailable] so
/// the UI can say "wrong password" instead of "no connection".
class SignInRejected extends SignInResult {
  const SignInRejected();
}

/// The server could not be reached, or it failed. Sign-in is the one operation
/// that cannot be queued offline: without a token there is nothing to queue
/// against.
class SignInUnavailable extends SignInResult {
  const SignInUnavailable(this.message);
  final String message;
}

/// Sign-in, sign-out, and "am I signed in".
///
/// ## What this can and cannot do today
///
/// The backend's `/api/token` authenticates a **single hardcoded demo user**
/// (`app/api/auth.py:8`). There is no registration, no OTP, no phone-based
/// login, and no refresh token. `djassa-BE/docs/business/CONCEPT.md` calls for Tier 0 identity
/// anchored to a mobile-money account, which does not exist server-side yet.
///
/// This class therefore speaks the API that exists — username and password —
/// while keeping that fact in one place. When phone-based Tier 0 login lands,
/// only [signIn] changes; nothing above it does.
class AuthRepository {
  AuthRepository({required ApiClient client, required TokenStore tokenStore})
      : _client = client,
        _tokenStore = tokenStore;

  final ApiClient _client;
  final TokenStore _tokenStore;

  /// Whether a usable token is on the device.
  ///
  /// Checks client-side expiry only to avoid a pointless round trip; the server
  /// remains the authority and a 401 from any call clears the session.
  Future<bool> hasValidSession() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) return false;
    if (isTokenExpired(token)) {
      await _tokenStore.clear();
      return false;
    }
    return true;
  }

  Future<String?> currentUsername() => _tokenStore.readUsername();

  /// Exchanges credentials for a bearer token.
  ///
  /// `/api/token` expects an OAuth2 password *form*, not JSON.
  Future<SignInResult> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final body = await _client.postForm(
        '/api/token',
        {
          'username': username,
          'password': password,
          'grant_type': 'password',
        },
        authenticated: false,
      );

      final token = body['access_token'];
      if (token is! String || token.isEmpty) {
        return const SignInUnavailable('The server response was not usable');
      }

      await _tokenStore.save(token: token, username: username);
      return SignInSuccess(username);
    } on UnauthorizedException {
      // 401 here means bad credentials, not an expired session.
      return const SignInRejected();
    } on ClientErrorException catch (error) {
      // 422 from FastAPI means the form did not validate.
      return SignInUnavailable(error.message);
    } on ServerErrorException {
      return const SignInUnavailable('The server is unavailable');
    } on NetworkException catch (error) {
      return SignInUnavailable(error.message);
    } on MalformedResponseException {
      return const SignInUnavailable('The server response was not usable');
    }
  }

  /// Clears the local session.
  ///
  /// There is no server-side revocation endpoint, so the token stays valid
  /// until it expires. That is a backend gap, recorded in ARCHITECTURE.md;
  /// the client cannot fix it alone.
  ///
  /// Queued sales are intentionally preserved — see [TokenStore.clear].
  Future<void> signOut() => _tokenStore.clear();
}
