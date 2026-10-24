import 'dart:async';

import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'token_store.dart';

/// A recovery action failed; [message] is ready to show.
class AccountActionException implements Exception {
  const AccountActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Outcome of a sign-in attempt, as something the UI can render directly.
sealed class SignInResult {
  const SignInResult();
}

class SignInSuccess extends SignInResult {
  const SignInSuccess(this.username);

  /// The masked phone number, shown as the account name.
  final String username;
}

/// Wrong or expired code, or (merchant app) a number with no shop. Distinct
/// from [SignInUnavailable] so the UI can say why instead of "no connection".
class SignInRejected extends SignInResult {
  const SignInRejected(this.message);
  final String message;
}

/// The server could not be reached, or it failed. Sign-in is the one operation
/// that cannot be queued offline: without a token there is nothing to queue
/// against.
class SignInUnavailable extends SignInResult {
  const SignInUnavailable(this.message);
  final String message;
}

/// Sign-in with phone number + password, session renewal, sign-out.
///
/// The backend (`fidelia-BE/backend-api/app/api/password_auth.py`) exchanges
/// the password for a 60-minute access token and a 90-day single-use refresh
/// token. Both live in [TokenStore]. An expired access token is renewed with
/// [refresh] before or after the request that needs it (see `providers.dart`),
/// so the session survives as long as the app is opened at least once every
/// 90 days.
///
/// A shop's login is created by the Fidelia team, without a password: the
/// merchant asks for one ([requestPassword]), an admin sends a temporary one
/// on WhatsApp, and the first session must replace it ([changePassword]).
/// The same request covers a forgotten password.
class AuthRepository {
  AuthRepository({required ApiClient client, required TokenStore tokenStore})
      : _client = client,
        _tokenStore = tokenStore;

  /// The session this app opens.
  /// Needs the merchant role, granted by an admin with the shop's venue.
  static const appRole = 'merchant';

  final ApiClient _client;
  final TokenStore _tokenStore;

  /// The refresh in flight, shared by every caller. Refresh tokens are single
  /// use and the server treats a second use as theft, so two concurrent
  /// refreshes with the same token would sign the user out.
  Completer<bool>? _refreshing;

  /// Whether this device holds a session: a live access token, or a refresh
  /// token that can mint one. The server stays the authority; a refused
  /// refresh clears the session.
  Future<bool> hasValidSession() async {
    final token = await _tokenStore.readToken();
    if (token != null && token.isNotEmpty && !isTokenExpired(token)) return true;
    final refresh = await _tokenStore.readRefreshToken();
    if (refresh != null && refresh.isNotEmpty) return true;
    await _tokenStore.clear();
    return false;
  }

  Future<String?> currentUsername() => _tokenStore.readUsername();

  static const _unusable = 'La reponse du serveur est inutilisable';

  /// Exchanges the number and password for a session.
  Future<SignInResult> signIn({required String phone, required String password}) async {
    try {
      final body = await _client.postJson(
        '/api/auth/login',
        body: {'phone': phone.replaceAll(RegExp(r'\s+'), ''), 'country_code': 'CI', 'password': password, 'app': appRole},
        authenticated: false,
      );
      return await _store(body) ? SignInSuccess(await currentUsername() ?? '') : const SignInUnavailable(_unusable);
    } on ClientErrorException catch (error) {
      // 409: a login the team created, still waiting for its first password.
      if (error.statusCode == 409 && error.detail == 'password_not_set') return const SignInRejected(passwordNotSet);
      // 401 wrong password, 403 not a merchant or suspended, 423 locked.
      return SignInRejected(_detail(error));
    } on ServerErrorException {
      return const SignInUnavailable('Le serveur est indisponible');
    } on NetworkException catch (error) {
      return SignInUnavailable(error.message);
    } on ApiException catch (error) {
      return SignInUnavailable(error.message);
    }
  }

  static const passwordNotSet = 'Ce compte n\'a pas encore de mot de passe. Demandez-le a Fidelia.';

  /// Asks the team for a temporary password, sent on WhatsApp to [phone]: the
  /// first one for a new shop login, or a forgotten one. Returns the server's
  /// answer, which never says whether the number has an account.
  Future<String> requestPassword(String phone) => _action(() async {
        final body = await _client.postJson(
          '/api/auth/password-reset',
          body: {'phone': phone.replaceAll(RegExp(r'\s+'), ''), 'country_code': 'CI'},
          authenticated: false,
        );
        return body['message'] as String? ?? '';
      });

  /// Sets a new password. [current] is omitted right after signing in with a
  /// temporary password. The server's new token pair replaces the stored
  /// one, which no longer carries the `pc` claim.
  Future<void> changePassword({String? current, required String newPassword}) => _action(() async {
        final body = await _client.postJson(
          '/api/auth/password',
          body: {if (current != null) 'current': current, 'new': newPassword},
          // A wrong current password is a 401 that must not end the session.
          unauthorizedEndsSession: false,
        );
        if (!await _store(body)) throw const AccountActionException(_unusable);
      });

  /// Whether the team turned the number down: it is not on WhatsApp, so no
  /// code can reach it. False when the server cannot say.
  Future<bool> numberRefused() async {
    try {
      final body = await _client.getJson('/api/auth/me');
      return body['number_refused'] == true;
    } on ApiException {
      return false;
    }
  }

  /// Proves the number with the code a Fidelia admin sent on WhatsApp. The
  /// new session carries `vf`; every other session on the account ends.
  Future<void> verifyNumber(String code) => _action(() async {
        final body = await _client.postJson(
          '/api/auth/verify-number',
          body: {'code': code.replaceAll(' ', '')},
          unauthorizedEndsSession: false,
        );
        if (!await _store(body)) throw const AccountActionException(_unusable);
      });

  /// Renews the access token. True when a new one is stored; false when the
  /// server refused the refresh token (the session is over). Throws
  /// [NetworkException] or [ServerErrorException] when the server could not
  /// say, so being offline never signs anyone out.
  Future<bool> refresh() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;
    final completer = _refreshing = Completer<bool>();
    _doRefresh().then(completer.complete, onError: completer.completeError).whenComplete(() => _refreshing = null);
    return completer.future;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final body = await _client.postJson(
        '/api/auth/refresh',
        body: {'refresh_token': refreshToken},
        authenticated: false,
      );
      return _store(body);
    } on ClientErrorException {
      return false;
    }
  }

  Future<bool> _store(Map<String, Object?> body) async {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty) return false;
    await _tokenStore.save(
      token: access,
      refreshToken: refresh,
      username: body['phone_masked'] as String? ?? '',
    );
    return true;
  }

  /// Ends the session: revoked on the server when reachable, always wiped
  /// here. Offline, the refresh token dies with the local copy anyway, and
  /// the last access token expires within the hour.
  ///
  /// Queued sales are intentionally preserved — see [TokenStore.clear].
  Future<void> signOut() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.postJson('/api/auth/logout', body: {'refresh_token': refreshToken}, authenticated: false);
      } on ApiException {
        // Best effort; the local wipe below is what matters on this device.
      }
    }
    await _tokenStore.clear();
  }

  // --- Account recovery (fidelia-BE app/api/account.py) ---------------------

  /// Ends every session but this device's: a lost or stolen phone that is
  /// still signed in loses access within the hour. Returns how many ended.
  Future<int> revokeOtherSessions() => _action(() async {
        final refreshToken = await _tokenStore.readRefreshToken();
        final body = await _client.postJson(
          '/api/auth/sessions/revoke-others',
          body: {if (refreshToken != null) 'refresh_token': refreshToken},
        );
        final revoked = body['revoked'];
        return revoked is int ? revoked : 0;
      });

  /// Asks the team for a WhatsApp code on [newPhone]. The password proves
  /// the person: a phone left unlocked must not be enough to move the shop.
  /// Returns the masked new number.
  Future<String> requestNumberChange({required String newPhone, required String password}) => _action(() async {
        final body = await _client.postJson(
          '/api/auth/change-number/request',
          body: {'new_phone': newPhone, 'country_code': 'CI', 'password': password},
          unauthorizedEndsSession: false,
        );
        return body['new_phone_masked'] as String? ?? newPhone;
      });

  /// Moves the account to the new number with the code the team sent there.
  /// The server ends every other session and returns a new one for this
  /// device, stored here. Returns the masked new number.
  Future<String> confirmNumberChange(String code) => _action(() async {
        final body = await _client.postJson(
          '/api/auth/change-number/confirm',
          body: {'code': code.replaceAll(' ', '')},
          unauthorizedEndsSession: false,
        );
        if (!await _store(body)) throw const AccountActionException(_unusable);
        return await currentUsername() ?? '';
      });

  // --- Joining Fidelia (fidelia-BE app/api/onboarding.py) --------------------

  /// Files the request an agent follows up. The agent calls the number, so
  /// nothing proves it here. Returns the server's message.
  Future<String> filePartnerRequest({
    required String phone,
    required String contactName,
    required String shopName,
    required String category,
    required String commune,
    String? address,
    String? walletProvider,
    String? notes,
  }) =>
      _action(() async {
        final body = await _client.postJson(
          '/api/partner-requests',
          body: {
            'phone': phone,
            'contact_name': contactName,
            'shop_name': shopName,
            'category': category,
            'commune': commune,
            if (address != null && address.isNotEmpty) 'address': address,
            if (walletProvider != null) 'wallet_provider': walletProvider,
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          },
          authenticated: false,
        );
        return body['message'] as String? ?? '';
      });

  Future<T> _action<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ClientErrorException catch (error) {
      throw AccountActionException(_detail(error));
    } on ServerErrorException {
      throw const AccountActionException('Le serveur est indisponible');
    } on ApiException catch (error) {
      throw AccountActionException(error.message);
    }
  }

  static String _detail(ClientErrorException error) =>
      error.detail is String ? error.detail as String : error.message;
}
