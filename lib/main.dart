import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/monitoring/error_reporter.dart';
import 'core/monitoring/usage_tracker.dart';
import 'core/providers.dart';
import 'features/demo/demo_mode.dart';
import 'features/home_screen.dart';
import 'features/sign_in_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Refuses to launch a release build pointed at a cleartext host.
  Env.assertHttpsInRelease();

  final reporter = ErrorReporter(app: 'retailer')..install();
  final usage = UsageTracker(app: 'retailer');
  final container = ProviderContainer(overrides: [usageTrackerProvider.overrideWithValue(usage)]);
  // Ties usage to the merchant's shop when signed in (the pilot is measured
  // per merchant). Signed out, events still count, just not per shop.
  usage.tokenProvider = () => container.read(freshTokenProvider)();
  runApp(AppHost(container: container, usage: usage));
  // Whatever an earlier session could not send goes now, once. One small
  // request, and only when there is something to send.
  unawaited(reporter.flush());
  unawaited(usage.start());
}

/// Runs the real app, or the demo in its own provider container.
///
/// Swapping the whole container (rather than overriding a few providers lower
/// down) is what keeps the demo sealed: every route and dialog the demo opens
/// reads demo wiring, and the real ledger and session are never touched.
class AppHost extends StatefulWidget {
  const AppHost({super.key, required this.container, required this.usage});

  final ProviderContainer container;
  final UsageTracker usage;

  @override
  State<AppHost> createState() => _AppHostState();
}

class _AppHostState extends State<AppHost> {
  ProviderContainer? _demo;

  void _start() {
    widget.usage.track('demo_started');
    setState(() => _demo = createDemoContainer(onExit: _stop));
  }

  void _stop() {
    final demo = _demo;
    setState(() => _demo = null);
    // After the frame that stops using it.
    WidgetsBinding.instance.addPostFrameCallback((_) => demo?.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final demo = _demo;
    return DemoHost(
      active: demo != null,
      start: _start,
      stop: _stop,
      child: UncontrolledProviderScope(
        key: ObjectKey(demo ?? widget.container),
        container: demo ?? widget.container,
        child: FideliaApp(demo: demo != null),
      ),
    );
  }
}

class FideliaApp extends ConsumerWidget {
  const FideliaApp({super.key, this.demo = false});

  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Fidelia Pro',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [ref.read(usageTrackerProvider).navigatorObserver],
      theme: fideliaTheme(),
      builder: demo ? (context, child) => DemoFrame(child: child!) : null,
      home: const _Root(),
    );
  }
}

/// Opens the database, then shows either sign-in or the merchant home.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The local ledger must be open before anything reads it. Everything below
    // this gate can assume `databaseProvider.requireValue` is safe.
    final database = ref.watch(databaseProvider);

    return switch (database) {
      AsyncError(:final error) => _StartupFailure(error: error),
      AsyncData() => const _SessionGate(),
      _ => const _Splash(),
    };
  }
}

class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // Until the stored token has been inspected, show the splash rather than
    // flashing the login screen at a merchant who is already signed in.
    if (!session.checked) return const _Splash();
    return session.signedIn
        ? const _Tracked(name: 'home', child: HomeScreen())
        : const _Tracked(name: 'sign_in', child: SignInScreen());
  }
}

/// Records a screen view for a screen that is swapped in rather than pushed
/// (pushed routes are recorded by the navigator observer).
class _Tracked extends ConsumerStatefulWidget {
  const _Tracked({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  ConsumerState<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends ConsumerState<_Tracked> {
  @override
  void initState() {
    super.initState();
    ref.read(usageTrackerProvider).screen(widget.name);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // Continues the system splash: the mark on paper.
    return const Scaffold(
      backgroundColor: FideliaColors.paper,
      body: Center(child: FideliaMark(size: 112)),
    );
  }
}

/// Shown when the local database cannot be opened.
///
/// Deliberately explicit rather than a silent fallback to memory: without the
/// ledger the app cannot keep a sale safe, and pretending otherwise would lose
/// the merchant's money.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftCard(
                color: FideliaColors.sand,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: FideliaColors.danger),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fidelia Pro', style: text.headlineSmall),
                          const SizedBox(height: 8),
                          Text(
                            "Le telephone n'a pas pu ouvrir la base locale. "
                            'Redemarrez l\'application.',
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('$error', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
