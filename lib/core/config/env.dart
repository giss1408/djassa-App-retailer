/// Build-time configuration.
///
/// Values come from `--dart-define`, never from a file shipped in the APK and
/// never from a runtime-editable store: a merchant's device is not a trusted
/// environment, and an attacker who can rewrite the API host owns every sale
/// and token that follows.
///
/// Release build:
///   flutter build apk --release \
///     --dart-define=DJASSA_API_BASE=https://api.djassa.ci
///
/// Local backend from the Android emulator:
///   flutter run --dart-define=DJASSA_API_BASE=http://10.0.2.2:8000
library;

class Env {
  const Env._();

  /// Base URL of the Djassa API, with no trailing slash and no `/api` suffix.
  /// The default points at the emulator loopback so a fresh checkout runs
  /// against a local backend without arguments; it is useless in production
  /// and `assertHttpsInRelease` refuses it in a release build.
  static const String apiBase = String.fromEnvironment(
    'DJASSA_API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Sign-in prefill for development, e.g.
  ///   --dart-define=DJASSA_DEV_USERNAME=demo
  ///   --dart-define=DJASSA_DEV_PASSWORD=demo123
  /// Empty unless passed, and ignored in a release build (see
  /// `devUsername`/`devPassword`), so no credential can ship in an APK by
  /// accident.
  static const String _devUsername = String.fromEnvironment('DJASSA_DEV_USERNAME');
  static const String _devPassword = String.fromEnvironment('DJASSA_DEV_PASSWORD');

  static String get devUsername => isRelease ? '' : _devUsername;
  static String get devPassword => isRelease ? '' : _devPassword;

  /// Wall-clock budget for a single request. Deliberately generous: a 2G
  /// round trip in a market can take several seconds, and failing early just
  /// makes the merchant retry and spend the bytes twice.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Budget for establishing the TCP+TLS connection.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Whether this is a release build. `kReleaseMode` lives in foundation, but
  /// keeping the check here avoids a flutter import in pure-Dart core code.
  static const bool isRelease = bool.fromEnvironment('dart.vm.product');

  /// Fails fast at startup rather than leaking traffic.
  ///
  /// A release build that talks http would send bearer tokens and sales in
  /// clear over a shared cell. The Android network security config already
  /// refuses it at the platform level; this is the second lock, so a
  /// misconfigured build dies loudly at launch instead of silently failing
  /// every request later.
  static void assertHttpsInRelease() {
    if (!isRelease) return;
    final uri = Uri.tryParse(apiBase);
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
      throw StateError(
        'Release builds require an https DJASSA_API_BASE. '
        'Rebuild with --dart-define=DJASSA_API_BASE=https://<host>',
      );
    }
  }
}
