import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/providers.dart';
import 'features/home_screen.dart';
import 'features/sign_in_screen.dart';
import 'ui/theme.dart';

void main() {
  // Refuses to launch a release build pointed at a cleartext host.
  Env.assertHttpsInRelease();

  runApp(const ProviderScope(child: DjassaApp()));
}

class DjassaApp extends StatelessWidget {
  const DjassaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Djassa',
      debugShowCheckedModeBanner: false,
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
    return session.signedIn ? const HomeScreen() : const SignInScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
              Text('Djassa', style: text.headlineMedium),
              const SizedBox(height: 12),
              Text(
                "Le telephone n'a pas pu ouvrir la base locale. "
                'Redemarrez l\'application.',
                style: text.bodyMedium,
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
