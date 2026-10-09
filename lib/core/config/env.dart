/// Build-time configuration.
///
/// Values come from `--dart-define`, never from a file shipped in the APK and
/// never from a runtime-editable store: a merchant's device is not a trusted
/// environment, and an attacker who can rewrite the API host owns every sale
/// and token that follows.
///
/// Release build:
///   flutter build apk --release \
///     --dart-define=FIDELIA_API_BASE=https://api.fidelia.ci
///
/// Local backend from the Android emulator:
///   flutter run --dart-define=FIDELIA_API_BASE=http://10.0.2.2:8000
library;

class Env {
  const Env._();

  /// Base URL of the Fidelia API, with no trailing slash and no `/api` suffix.
  /// The default points at the emulator loopback so a fresh checkout runs
  /// against a local backend without arguments; it is useless in production
  /// and `assertHttpsInRelease` refuses it in a release build.
  static const String apiBase = String.fromEnvironment(
    'FIDELIA_API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Sign-in prefill for development, e.g.
  ///   --dart-define=FIDELIA_DEV_PHONE=0712345678
  /// Empty unless passed, and ignored in a release build, so no number can
  /// ship in an APK by accident. Locally the backend's console sender with
  /// OTP_DEV_ECHO=1 returns the code too, so no SIM is needed.
  static const String _devPhone = String.fromEnvironment('FIDELIA_DEV_PHONE');

  static String get devPhone => isRelease ? '' : _devPhone;

  /// Reported with each error so a crash maps to the build that shipped it.
  /// Keep in step with `version:` in pubspec.yaml; the release script passes
  /// it as --dart-define=FIDELIA_APP_VERSION=<version>.
  static const String appVersion = String.fromEnvironment('FIDELIA_APP_VERSION', defaultValue: '0.1.0+1');

  /// Debug builds print errors instead of reporting them, unless asked with
  /// --dart-define=FIDELIA_REPORT_ERRORS=true (to test the pipeline locally).
  static const bool reportErrors = isRelease || bool.fromEnvironment('FIDELIA_REPORT_ERRORS');

  /// Pilot only: the end-of-day "how many sales today?" question, the
  /// denominator of the share of sales recorded. Remove once that share is
  /// high enough to make the question moot (planning W4-3); turn off sooner
  /// with --dart-define=FIDELIA_PILOT_DAILY_REPORT=false.
  static const bool pilotDailyReport = bool.fromEnvironment('FIDELIA_PILOT_DAILY_REPORT', defaultValue: true);

  /// Wall-clock budget for a single request. Deliberately generous: a 2G
  /// round trip in a market can take several seconds, and failing early just
  /// makes the merchant retry and spend the bytes twice.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Budget for sending one photo or video. Long on purpose: a video on a
  /// slow cell takes minutes, and cutting it off would waste what was sent.
  static const Duration uploadTimeout = Duration(minutes: 10);

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
        'Release builds require an https FIDELIA_API_BASE. '
        'Rebuild with --dart-define=FIDELIA_API_BASE=https://<host>',
      );
    }
  }
}
