import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';

/// Our own crash and error reporting, instead of a third-party SDK.
///
/// Catches uncaught Flutter and Dart errors, keeps them in a small file
/// queue, and sends them to `POST /api/client-events` in one request when the
/// app starts or returns to the foreground. Nothing is sent on a timer, so a
/// healthy app costs zero bytes, and a sick one at most a few KB per launch.
///
/// What is sent: the error message with every run of digits replaced
/// (phones, amounts, ids), the stack trace, the app version, Android version,
/// and a count. Never a token, a phone number, the user, or the screen
/// contents. The backend scrubs again on arrival.
///
/// Stacks are left intact: frames carry no values, and release builds are
/// obfuscated, so a stack is hex addresses that only `flutter symbolize` and
/// the build's archived symbols (build/symbols/) can read.
///
/// Native crashes (in the engine or a plugin's Java code) kill the process
/// before Dart can see them and are not covered; Play Console's Android
/// vitals reports those for free.
class ErrorReporter with WidgetsBindingObserver {
  ErrorReporter({
    required this.app,
    http.Client? client,
    Future<Directory> Function()? directory,
    bool enabled = Env.reportErrors,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _directory = directory ?? getApplicationSupportDirectory,
        _enabled = enabled,
        _baseUrl = baseUrl ?? Env.apiBase;

  /// "user" or "retailer", as the backend expects.
  final String app;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final bool _enabled;
  final String _baseUrl;

  static const _maxQueued = 30;
  static const _maxPerBatch = 20;
  static const _maxStackLines = 25;

  /// Keyed by fingerprint, so one bug hit 200 times is one entry with a count.
  final Map<String, Map<String, Object?>> _queue = {};
  bool _loaded = false;
  Future<void>? _flushing;
  Timer? _saveSoon;

  /// Hooks the global error handlers. Call once, before `runApp`.
  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      record(details.exception, details.stack, crash: false);
    };
    // Uncaught async errors. Returning true marks them handled, as the
    // framework would have only logged them anyway.
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, crash: true);
      return true;
    };
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  /// Records one error. Safe to call from anywhere, including catch blocks
  /// for errors worth knowing about that the UI already handled.
  void record(Object error, StackTrace? stack, {bool crash = false}) {
    if (!_enabled) {
      debugPrint('ErrorReporter (not sent in debug): $error');
      return;
    }
    try {
      final message = scrub(error.toString());
      final lines = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(_maxStackLines).toList();
      final kind = crash ? 'crash' : 'error';
      // Frames only: an obfuscated trace opens with header lines every error
      // of the build shares.
      final frames = lines.where((l) => l.trimLeft().startsWith('#')).take(5).map(_stripPosition);
      final key = '$kind|${error.runtimeType}|${frames.join('|')}';
      final existing = _queue[key];
      if (existing != null) {
        existing['count'] = (existing['count'] as int) + 1;
      } else {
        if (_queue.length >= _maxQueued) return;
        _queue[key] = {
          'kind': kind,
          'message': message.length > 500 ? message.substring(0, 500) : message,
          'stack': lines.join('\n'),
          'count': 1,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
        };
      }
      _saveSoon?.cancel();
      _saveSoon = Timer(const Duration(seconds: 2), () => unawaited(_save()));
    } catch (_) {
      // The reporter must never be the thing that crashes the app.
    }
  }

  /// Sends what is queued, if anything. Concurrent calls share one request.
  Future<void> flush() => _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    if (!_enabled) return;
    try {
      await _load();
      if (_queue.isEmpty) return;
      final keys = _queue.keys.take(_maxPerBatch).toList();
      final body = jsonEncode({
        'app': app,
        'app_version': Env.appVersion,
        'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
        'os_version': _osVersion(),
        'events': [for (final key in keys) _queue[key]],
      });
      final response = await _client
          .post(
            Uri.parse('${_base()}/api/client-events'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: body,
          )
          .timeout(Env.requestTimeout);
      // 2xx: delivered. 4xx: the server will never accept these; dropping
      // them stops a malformed entry from blocking the queue forever.
      if (response.statusCode < 500) {
        for (final key in keys) {
          _queue.remove(key);
        }
        await _save();
      }
    } catch (_) {
      // Offline or server down: keep the queue for the next launch.
    }
  }

  Future<File> _file() async => File('${(await _directory()).path}/pending_errors.json');

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final stored = jsonDecode(await file.readAsString());
      if (stored is Map) {
        for (final entry in stored.entries) {
          if (_queue.length >= _maxQueued) break;
          if (entry.value is Map) _queue.putIfAbsent(entry.key as String, () => Map<String, Object?>.from(entry.value as Map));
        }
      }
    } catch (_) {
      // A corrupt queue file is not worth a crash; start over.
    }
  }

  Future<void> _save() async {
    try {
      await _load();
      final file = await _file();
      if (_queue.isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(jsonEncode(_queue), flush: true);
      }
    } catch (_) {}
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

  /// Replaces every run of 5+ digits (phone numbers, amounts, ids) in a
  /// message. Short numbers such as an index or a status code survive.
  @visibleForTesting
  static String scrub(String text) => text.replaceAll(RegExp(r'\+?\d[\d ]{3,}\d'), '<num>');

  static String _stripPosition(String frame) => frame
      .trim()
      .replaceAll(RegExp(r':\d+(:\d+)?\)?'), '')
      .replaceAll(RegExp(r'^#\d+\s+'), '')
      .replaceAll(RegExp(r'abs [0-9a-f]+\s*'), '');
}
