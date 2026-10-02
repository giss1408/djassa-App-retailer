import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';

/// Supplies a bearer token so the backend can tie events to the merchant's
/// shop, or null. The customer app never passes one.
typedef UsageTokenProvider = Future<String?> Function();

/// App usage for the pilot, sent to our own backend instead of an analytics
/// SDK (see ARCHITECTURE.md: no third-party SDK uploads on the user's data).
///
/// Same delivery rules as [ErrorReporter]: events wait in a small file queue
/// and go to `POST /api/usage-events` in one request when the app starts or
/// returns to the foreground — never on a timer. Repeats of one event on one
/// day are one entry with a count, so a busy day costs a few hundred bytes.
///
/// Identity: an *install id*, random, made on first launch and kept in the
/// app's storage. Not a device id, not a phone number; uninstalling the app
/// deletes it. The first launch is reported as `app_open` with `first: true`,
/// which is how installs are counted.
///
/// What is never sent: phone numbers, amounts, names, anything typed. Props
/// are short ids and labels chosen in code; the backend scrubs again.
class UsageTracker with WidgetsBindingObserver {
  UsageTracker({
    required this.app,
    http.Client? client,
    Future<Directory> Function()? directory,
    bool enabled = Env.reportErrors,
    String? baseUrl,
    this.tokenProvider,
    DateTime Function()? clock,
    Random? random,
  })  : _client = client ?? http.Client(),
        _directory = directory ?? getApplicationSupportDirectory,
        _enabled = enabled,
        _baseUrl = baseUrl ?? Env.apiBase,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  /// "user" or "retailer", as the backend expects.
  final String app;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final bool _enabled;
  final String _baseUrl;
  final DateTime Function() _clock;
  final Random _random;

  /// Set after start-up in the merchant app (the session lives in Riverpod).
  UsageTokenProvider? tokenProvider;

  static const _maxQueued = 200;
  static const _maxPerBatch = 50;

  /// Keyed by day + name + props, so 40 sales in a day are one entry.
  final Map<String, Map<String, Object?>> _queue = {};
  final Map<String, Object?> _state = {};
  bool _loaded = false;
  Future<void>? _flushing;
  Timer? _saveSoon;

  /// Whether events are recorded at all (off in debug builds and tests).
  bool get enabled => _enabled;

  /// The install id, once [start] has run.
  String? get installId => _state['install_id'] as String?;

  /// Loads the queue, makes the install id on first launch, reports this
  /// launch, and sends what earlier sessions could not. Call once, after
  /// `runApp`.
  Future<void> start() async {
    if (!_enabled) return;
    await _load();
    final first = _state['install_id'] == null;
    if (first) _state['install_id'] = _newInstallId();
    track('app_open', first ? const {'first': true} : null);
    WidgetsBinding.instance.addObserver(this);
    await flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  /// Records one event. Props must be short, chosen in code, and never hold
  /// what a person typed: ids as numbers, labels as fixed strings.
  void track(String name, [Map<String, Object>? props]) {
    if (!_enabled) {
      debugPrint('UsageTracker (not sent in debug): $name ${props ?? ''}');
      return;
    }
    try {
      final now = _clock().toUtc();
      final day = now.toIso8601String().substring(0, 10);
      final key = '$day|$name|${jsonEncode(props ?? const {})}';
      final existing = _queue[key];
      if (existing != null) {
        existing['count'] = (existing['count'] as int) + 1;
      } else {
        if (_queue.length >= _maxQueued) return;
        _queue[key] = {
          'name': name,
          if (props != null && props.isNotEmpty) 'props': props,
          'count': 1,
          'occurred_at': now.toIso8601String(),
        };
      }
      _saveLater();
    } catch (_) {
      // Measuring must never be the thing that breaks the app.
    }
  }

  /// A screen was shown. Names are fixed snake_case labels set in code.
  void screen(String name) => track('screen_view', {'screen': name});

  /// Adds the bytes one API call cost to today's `data_used` entry, so the
  /// pilot can report data consumed per user.
  void addTraffic(int sent, int received) {
    if (!_enabled || (sent <= 0 && received <= 0)) return;
    try {
      final day = _clock().toUtc().toIso8601String().substring(0, 10);
      final key = '$day|data_used';
      final entry = _queue.putIfAbsent(
          key,
          () => {
                'name': 'data_used',
                'props': <String, Object>{'bytes_sent': 0, 'bytes_received': 0},
                'count': 1,
                'occurred_at': _clock().toUtc().toIso8601String(),
              });
      final props = Map<String, Object>.from(entry['props'] as Map);
      props['bytes_sent'] = (props['bytes_sent'] as int) + sent;
      props['bytes_received'] = (props['bytes_received'] as int) + received;
      entry['props'] = props;
      _saveLater();
    } catch (_) {}
  }

  /// Whether `name` was already recorded today (e.g. the end-of-day report).
  bool trackedToday(String name) {
    final day = _clock().toUtc().toIso8601String().substring(0, 10);
    return _state['last_$name'] == day ||
        _queue.keys.any((k) => k.startsWith('$day|$name|'));
  }

  /// Remembers that `name` was done today, across restarts and after the
  /// event itself has been sent.
  void markToday(String name) {
    _state['last_$name'] = _clock().toUtc().toIso8601String().substring(0, 10);
    _saveLater();
  }

  /// Records screen views for routes pushed with a `RouteSettings(name:)`.
  late final NavigatorObserver navigatorObserver = _ScreenObserver(this);

  /// Sends what is queued, if anything. Concurrent calls share one request.
  Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    if (!_enabled) return;
    try {
      await _load();
      final installId = this.installId;
      if (installId == null) return;
      // Today's byte counter alone is not worth a request (sending it would
      // itself add bytes, and so on): it rides along with the next event.
      final today =
          '${_clock().toUtc().toIso8601String().substring(0, 10)}|data_used';
      if (_queue.keys.every((key) => key == today)) return;
      final keys = _queue.keys.take(_maxPerBatch).toList();
      final body = jsonEncode({
        'app': app,
        'app_version': Env.appVersion,
        'platform':
            Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
        'os_version': _osVersion(),
        'install_id': installId,
        'events': [for (final key in keys) _queue[key]],
      });
      final headers = {'Content-Type': 'application/json; charset=utf-8'};
      final token = await tokenProvider?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .post(Uri.parse('${_base()}/api/usage-events'),
              headers: headers, body: body)
          .timeout(Env.requestTimeout);
      // 2xx: delivered. 4xx: will never be accepted (e.g. an event name an
      // older backend does not know); dropping it unblocks the queue.
      if (response.statusCode < 500) {
        for (final key in keys) {
          _queue.remove(key);
        }
        // This request is data the user paid for too; count it tomorrow.
        addTraffic(utf8.encode(body).length, response.bodyBytes.length);
        await _save();
      }
    } catch (_) {
      // Offline or server down: keep the queue for the next launch.
    }
  }

  void _saveLater() {
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}/pending_usage.json');

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final stored = jsonDecode(await file.readAsString());
      if (stored is! Map) return;
      if (stored['state'] is Map) {
        _state.addAll(Map<String, Object?>.from(stored['state'] as Map));
      }
      final queue = stored['queue'];
      if (queue is Map) {
        for (final entry in queue.entries) {
          if (_queue.length >= _maxQueued) break;
          if (entry.value is Map) {
            _queue.putIfAbsent(entry.key as String,
                () => Map<String, Object?>.from(entry.value as Map));
          }
        }
      }
    } catch (_) {
      // A corrupt file is not worth a crash. The install id is lost with it,
      // which counts this phone once more as an install: acceptable.
    }
  }

  Future<void> _save() async {
    try {
      await _load();
      await (await _file()).writeAsString(
          jsonEncode({'state': _state, 'queue': _queue}),
          flush: true);
    } catch (_) {}
  }

  String _newInstallId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return 'inst_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  String _base() {
    var base = _baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  static String _osVersion() {
    final value = Platform.operatingSystemVersion;
    return value.length > 64 ? value.substring(0, 64) : value;
  }

  @visibleForTesting
  Map<String, Map<String, Object?>> get queued => _queue;
}

class _ScreenObserver extends NavigatorObserver {
  _ScreenObserver(this._tracker);

  final UsageTracker _tracker;

  void _record(Route<dynamic>? route) {
    final name = route?.settings.name;
    // Unnamed routes (dialogs, sheets) and the root '/' are not screens we
    // chose to measure.
    if (name != null && name.isNotEmpty && name != '/') _tracker.screen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);
}
