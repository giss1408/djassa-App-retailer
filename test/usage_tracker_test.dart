import 'dart:convert';
import 'dart:io';

import 'package:hossouko_merchant/core/monitoring/usage_tracker.dart';
import 'package:hossouko_merchant/core/net/api_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<http.Request> sent;
  var status = 202;
  var offline = false;
  var now = DateTime.utc(2026, 10, 2, 9);

  MockClient client() => MockClient((request) async {
        if (offline) throw const SocketException('no signal');
        sent.add(request);
        return http.Response('{"accepted": 1}', status);
      });

  UsageTracker tracker({UsageTokenProvider? token}) => UsageTracker(
        app: 'retailer',
        client: client(),
        directory: () async => dir,
        enabled: true,
        baseUrl: 'https://api.test',
        tokenProvider: token,
        clock: () => now,
      );

  Map<String, Object?> body(http.Request request) => jsonDecode(request.body) as Map<String, Object?>;
  List<Map<String, Object?>> events(http.Request request) =>
      [for (final e in body(request)['events'] as List) Map<String, Object?>.from(e as Map)];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('usage_test');
    sent = [];
    status = 202;
    offline = false;
    now = DateTime.utc(2026, 10, 2, 9);
  });

  tearDown(() => dir.delete(recursive: true));

  test('first launch makes an install id and reports it as the first open', () async {
    final first = tracker();
    await first.start();
    expect(sent, hasLength(1));
    expect(body(sent.single)['install_id'], allOf(startsWith('inst_'), first.installId));
    expect(events(sent.single).single, containsPair('props', {'first': true}));

    // Next launch: same install, not counted again as an install.
    final second = tracker();
    await second.start();
    expect(second.installId, first.installId);
    // Along with it goes the byte count of the first launch's request.
    final open = events(sent.last).singleWhere((e) => e['name'] == 'app_open');
    expect(open.containsKey('props'), isFalse);
  });

  test('repeats on one day are one entry with a count', () async {
    final usage = tracker();
    await usage.start();
    for (var i = 0; i < 40; i++) {
      usage.track('sale_recorded', {'seconds': 15, 'with_customer': false});
    }
    usage.track('sale_recorded', {'seconds': 20, 'with_customer': false});
    await usage.flush();
    final recorded = events(sent.last).where((e) => e['name'] == 'sale_recorded').toList();
    expect(recorded.map((e) => e['count']), unorderedEquals([40, 1]));
  });

  test('offline, the queue survives a restart and goes on the next launch', () async {
    offline = true;
    final usage = tracker();
    await usage.start();
    usage.track('sale_form_opened');
    await usage.flush();
    await Future<void>.delayed(const Duration(seconds: 3)); // the debounced save
    expect(sent, isEmpty);

    offline = false;
    await tracker().start();
    final names = events(sent.single).map((e) => e['name']);
    expect(names, containsAll(['app_open', 'sale_form_opened']));
  });

  test('a 5xx keeps the queue, a 4xx drops it', () async {
    final usage = tracker();
    status = 503;
    await usage.start();
    expect(usage.queued, isNotEmpty);
    status = 422;
    await usage.flush();
    expect(usage.queued.keys.where((k) => !k.endsWith('data_used')), isEmpty);
  });

  test("today's byte counter alone is not worth a request", () async {
    final usage = tracker();
    await usage.start();
    final requests = sent.length;
    usage.addTraffic(400, 2000);
    await usage.flush();
    expect(sent.length, requests);

    // It rides along with the next real event, and counts both directions.
    usage.track('screen_view', {'screen': 'deals'});
    await usage.flush();
    final data = events(sent.last).firstWhere((e) => e['name'] == 'data_used');
    final props = data['props'] as Map;
    expect(props['bytes_received'], greaterThanOrEqualTo(2000));
    expect(props['bytes_sent'], greaterThanOrEqualTo(400));
  });

  test('the merchant token goes along so the backend can tie usage to the shop', () async {
    await tracker(token: () async => 'abc.def.ghi').start();
    expect(sent.single.headers['Authorization'], 'Bearer abc.def.ghi');
  });

  test('the end-of-day question is asked once a day', () async {
    final usage = tracker();
    await usage.start();
    expect(usage.trackedToday('daily_report'), isFalse);
    usage
      ..track('daily_report', {'sales_estimate': 8})
      ..markToday('daily_report');
    await usage.flush();
    expect(usage.trackedToday('daily_report'), isTrue);
    now = now.add(const Duration(days: 1));
    expect(usage.trackedToday('daily_report'), isFalse);
  });

  testWidgets('named routes are screen views; dialogs and sheets are not', (tester) async {
    final usage = tracker();
    await tester.runAsync(usage.start);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(WidgetsApp(
      navigatorKey: navigator,
      navigatorObservers: [usage.navigatorObserver],
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (c, _, __) => builder(c)),
      home: const SizedBox(),
    ));
    navigator.currentState!.push(PageRouteBuilder(settings: const RouteSettings(name: 'deals'), pageBuilder: (_, __, ___) => const SizedBox()));
    navigator.currentState!.push(PageRouteBuilder(pageBuilder: (_, __, ___) => const SizedBox()));
    await tester.pumpAndSettle();
    final screens = usage.queued.values.where((e) => e['name'] == 'screen_view').map((e) => (e['props'] as Map)['screen']);
    expect(screens, ['deals']);
    await tester.pump(const Duration(seconds: 3)); // let the debounced save run
  });

  test('every API call reports the bytes it cost, both ways', () async {
    final traffic = <(int, int)>[];
    final api = ApiClient(
      inner: MockClient((request) async => http.Response(jsonEncode({'ok': 'x' * 1000}), 200)),
      tokenProvider: () async => 't',
      baseUrl: 'https://api.test',
      onTraffic: (sent, received) => traffic.add((sent, received)),
    );
    await api.postJson('/api/merchant/sales', body: {'amount': 1500});
    final (out, back) = traffic.single;
    expect(out, greaterThan(jsonEncode({'amount': 1500}).length));
    expect(back, greaterThan(1000));
  });
}
