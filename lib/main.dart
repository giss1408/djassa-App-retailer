import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/monitoring/error_reporter.dart';
import 'core/monitoring/usage_tracker.dart';
import 'core/providers.dart';
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
  runApp(UncontrolledProviderScope(container: container, child: const DjassaApp()));
  // Whatever an earlier session could not send goes now, once. One small
  // request, and only when there is something to send.
  unawaited(reporter.flush());
  unawaited(usage.start());
}

class DjassaApp extends ConsumerWidget {
  const DjassaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Djassa Pro',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [ref.read(usageTrackerProvider).navigatorObserver],
      theme: djassaTheme(),
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
    return Scaffold(
      backgroundColor: DjassaColors.orangeDeep,
      body: Center(
        child: Text('d', style: serifStyle(64, color: Colors.white, height: 0.9)),
      ),
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
                color: DjassaColors.sand,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: DjassaColors.danger),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Djassa Pro', style: text.headlineSmall),
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
