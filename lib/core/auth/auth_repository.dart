import 'dart:async';

import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'token_store.dart';

/// Outcome of asking for a sign-in code.
sealed class CodeRequestResult {
  const CodeRequestResult();
}

class CodeSent extends CodeRequestResult {
  const CodeSent({required this.phoneMasked, required this.resendIn, this.devCode});

  /// "07 •• •• 56 78", to show where the SMS went.
  final String phoneMasked;
  final Duration resendIn;

  /// Only from a local backend with OTP_DEV_ECHO=1; always null in production.
  final String? devCode;
}

/// The server refused: invalid number, too many codes, wait before resending.
/// [message] is the server's own French sentence, ready to show.
class CodeRequestRefused extends CodeRequestResult {
  const CodeRequestRefused(this.message);
  final String message;
}

/// A recovery action failed; [message] is ready to show.
class AccountActionException implements Exception {
  const AccountActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Codes sent to both numbers for a number change.
class NumberChangeCodes {
  const NumberChangeCodes({
    required this.oldPhoneMasked,
    required this.newPhoneMasked,
    required this.resendIn,
    this.devOldCode,
    this.devNewCode,
  });

  final String oldPhoneMasked;
  final String newPhoneMasked;
  final Duration resendIn;

  /// Only from a local backend with OTP_DEV_ECHO=1.
  final String? devOldCode;
  final String? devNewCode;
}

class CodeRequestUnavailable extends CodeRequestResult {
  const CodeRequestUnavailable(this.message);
  final String message;
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

/// Sign-in with phone number + SMS code, session renewal, sign-out.
///
/// The backend (`djassa-BE/backend-api/app/api/auth.py`) sends a 6-digit code
/// to the number, and exchanges it for a 60-minute access token and a 90-day
/// single-use refresh token. Both live in [TokenStore]. An expired access
/// token is renewed with [refresh] before or after the request that needs it
/// (see `providers.dart`), so the session survives as long as the app is
/// opened at least once every 90 days.
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

  /// Sends a sign-in code by SMS to [phone], as the user typed it.
  Future<CodeRequestResult> requestCode(String phone) async {
    try {
      final body = await _client.postJson(
        '/api/auth/otp/request',
        body: {'phone': phone, 'app': appRole},
        authenticated: false,
      );
      return _codeSent(body, phone);
    } on ClientErrorException catch (error) {
      return CodeRequestRefused(_detail(error));
    } on ServerErrorException catch (error) {
      // 503: the SMS provider refused. The server says so in French.
      return CodeRequestUnavailable(error.statusCode == 503 ? 'Le SMS n\'a pas pu être envoyé. Réessayez.' : 'Le serveur est indisponible');
    } on NetworkException catch (error) {
      return CodeRequestUnavailable(error.message);
    } on ApiException catch (error) {
      return CodeRequestUnavailable(error.message);
    }
  }

  /// Exchanges the SMS code for a session.
  Future<SignInResult> verifyCode({required String phone, required String code}) async {
    try {
      final body = await _client.postJson(
        '/api/auth/otp/verify',
        body: {'phone': phone, 'code': code, 'app': appRole},
        authenticated: false,
      );
      return await _store(body) ? SignInSuccess(await currentUsername() ?? '') : const SignInUnavailable('La réponse du serveur est inutilisable');
    } on ClientErrorException catch (error) {
      // 401 wrong/expired code, 403 not a merchant or suspended, 422 bad number.
      return SignInRejected(_detail(error));
    } on ServerErrorException {
      return const SignInUnavailable('Le serveur est indisponible');
    } on NetworkException catch (error) {
      return SignInUnavailable(error.message);
    } on ApiException catch (error) {
      return SignInUnavailable(error.message);
    }
  }

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

  // --- Account recovery (djassa-BE app/api/account.py) ---------------------

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

  /// Sends a code to the current number and one to [newPhone]. Both are
  /// needed: a session alone, on a phone left unlocked, cannot move the
  /// account.
  Future<NumberChangeCodes> requestNumberChange(String newPhone) => _action(() async {
        final body = await _client.postJson('/api/auth/change-number/request', body: {'new_phone': newPhone});
        final resendIn = body['resend_in'];
        return NumberChangeCodes(
          oldPhoneMasked: body['old_phone_masked'] as String? ?? '',
          newPhoneMasked: body['new_phone_masked'] as String? ?? newPhone,
          resendIn: Duration(seconds: resendIn is int ? resendIn : 60),
          devOldCode: body['dev_old_code'] as String?,
          devNewCode: body['dev_new_code'] as String?,
        );
      });

  /// Moves the account to [newPhone]. The server ends every other session and
  /// returns a new one for this device, stored here. Returns the masked new
  /// number to show as the account name.
  Future<String> confirmNumberChange({
    required String newPhone,
    required String oldCode,
    required String newCode,
  }) =>
      _action(() async {
        final body = await _client.postJson(
          '/api/auth/change-number/confirm',
          body: {'new_phone': newPhone, 'old_code': oldCode, 'new_code': newCode},
        );
        if (!await _store(body)) throw const AccountActionException('La réponse du serveur est inutilisable');
        return await currentUsername() ?? '';
      });

  /// Lost number, step 1: a code to the new number, which proves it.
  Future<CodeRequestResult> requestRecoveryCode(String newPhone) async {
    try {
      final body = await _client.postJson('/api/auth/recovery/code', body: {'new_phone': newPhone}, authenticated: false);
      return _codeSent(body, newPhone);
    } on ClientErrorException catch (error) {
      return CodeRequestRefused(_detail(error));
    } on ApiException catch (error) {
      return CodeRequestUnavailable(error.message);
    }
  }

  /// Lost number, step 2: files the request a Djassa admin reviews. Returns
  /// the server's message saying what happens next.
  Future<String> fileRecovery({
    required String newPhone,
    required String code,
    required String oldPhone,
    required String details,
  }) =>
      _action(() async {
        final body = await _client.postJson(
          '/api/auth/recovery',
          body: {'new_phone': newPhone, 'code': code, 'old_phone': oldPhone, 'details': details},
          authenticated: false,
        );
        return body['message'] as String? ?? '';
      });

  // --- Joining Djassa (djassa-BE app/api/onboarding.py) --------------------

  /// A code to the phone that will become the merchant's login.
  Future<CodeRequestResult> requestPartnerCode(String phone) async {
    try {
      final body = await _client.postJson('/api/partner-requests/code', body: {'phone': phone}, authenticated: false);
      return _codeSent(body, phone);
    } on ClientErrorException catch (error) {
      return CodeRequestRefused(_detail(error));
    } on ApiException catch (error) {
      return CodeRequestUnavailable(error.message);
    }
  }

  /// Files the request an agent follows up. Returns the server's message.
  Future<String> filePartnerRequest({
    required String phone,
    required String code,
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
            'code': code,
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
    } on ServerErrorException catch (error) {
      throw AccountActionException(error.statusCode == 503 ? 'Le SMS n\'a pas pu être envoyé. Réessayez.' : 'Le serveur est indisponible');
    } on ApiException catch (error) {
      throw AccountActionException(error.message);
    }
  }

  static CodeSent _codeSent(Map<String, Object?> body, String phone) {
    final resendIn = body['resend_in'];
    return CodeSent(
      phoneMasked: body['phone_masked'] as String? ?? phone,
      resendIn: Duration(seconds: resendIn is int ? resendIn : 60),
      devCode: body['dev_code'] as String?,
    );
  }

  static String _detail(ClientErrorException error) =>
      error.detail is String ? error.detail as String : error.message;
}
