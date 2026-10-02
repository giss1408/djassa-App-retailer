import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access and refresh tokens in the Android Keystore.
///
/// Not `SharedPreferences`: that is a plain XML file in the app's data
/// directory, readable by adb backup on older devices, by root, and by any
/// device-management tool. A bearer token is the merchant's entire sales
/// history and, once payments are live, their money.
///
/// [encryptedSharedPreferences] moves the backing store to Android's
/// EncryptedSharedPreferences (AES-256-GCM, key held in the Keystore) instead
/// of the legacy RSA-wrapped file. It needs API 23+; on API 21-22 the plugin
/// falls back to the legacy scheme, which is why the app still refuses cloud
/// backup rather than relying on storage encryption alone.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _usernameKey = 'username';

  /// In-memory cache so a request does not hit the Keystore every time. The
  /// Keystore round trip is slow on low-end hardware, and the token is already
  /// in this process's memory the moment it is used.
  String? _cachedToken;
  bool _cacheLoaded = false;

  Future<String?> readToken() async {
    if (_cacheLoaded) return _cachedToken;
    try {
      _cachedToken = await _storage.read(key: _tokenKey);
    } on Exception {
      // A corrupt or unreadable keystore entry must not brick the app: treat
      // it as signed out and let the merchant sign in again.
      _cachedToken = null;
    }
    _cacheLoaded = true;
    return _cachedToken;
  }

  /// The long-lived token that renews the access token (`/api/auth/refresh`).
  /// Read rarely, about once an hour, so it is not cached in memory.
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _refreshKey);
    } on Exception {
      return null;
    }
  }

  Future<String?> readUsername() async {
    try {
      return await _storage.read(key: _usernameKey);
    } on Exception {
      return null;
    }
  }

  /// [username] is what the UI shows: the masked phone ("07 •• •• 56 78").
  /// [refreshToken] is null only for a renewed access token whose refresh
  /// token did not change.
  Future<void> save({required String token, String? refreshToken, required String username}) async {
    _cachedToken = token;
    _cacheLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
    if (refreshToken != null) await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _usernameKey, value: username);
  }

  /// Wipes the session.
  ///
  /// Only the token and username are removed. The queued sales stay: they are
  /// the merchant's own record of money taken, and signing out — or having a
  /// token expire overnight — must never destroy work that has not reached the
  /// server yet.
  Future<void> clear() async {
    _cachedToken = null;
    _cacheLoaded = true;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshKey);
      await _storage.delete(key: _usernameKey);
    } on Exception {
      // Nothing useful to do; the in-memory cache is already cleared.
    }
  }
}

/// Reads the `exp` claim from a JWT without verifying it.
///
/// **This is not a security check.** Only the server can validate the
/// signature, and this code must never be used to decide whether a token is
/// trustworthy. Its single purpose is to avoid spending a 2G round trip on a
/// request we already know will 401 — the client's opinion of expiry is a
/// bandwidth optimisation, nothing more.
///
/// Phone sign-in access tokens live 60 minutes (`app/api/auth.py`); an
/// expired one is renewed with the refresh token before the request is sent,
/// so the user signs in again only after 90 days without opening the app.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = parts[1];
    // base64url without padding, which Dart's decoder requires.
    final normalized = base64Url.normalize(payload);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) return null;
    final exp = decoded['exp'];
    if (exp is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  } on Exception {
    return null;
  }
}

/// Whether a token is past, or within [leeway] of, its expiry.
///
/// A token with no readable `exp` is treated as usable: the server is the
/// authority, and refusing to send would strand a merchant whose token might
/// be perfectly valid.
bool isTokenExpired(String token,
    {Duration leeway = const Duration(minutes: 2)}) {
  final expiry = jwtExpiry(token);
  if (expiry == null) return false;
  return DateTime.now().toUtc().add(leeway).isAfter(expiry);
}
