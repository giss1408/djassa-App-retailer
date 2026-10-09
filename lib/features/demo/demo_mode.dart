import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;

import '../../core/data/database.dart';
import '../../core/data/sale_dao.dart';
import '../../core/model/money.dart';
import '../../core/model/sale.dart';
import '../../core/monitoring/usage_tracker.dart';
import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../l10n/strings.dart';
import '../../ui/theme.dart';
import 'demo_backend.dart';

/// The demo: the whole merchant app, without an account.
///
/// A separate provider container, so every screen, dialog and pushed route
/// reads demo wiring: an in-memory ledger (the real one on disk is never
/// opened) and [DemoBackend] instead of the network. Leaving the demo
/// disposes all of it; nothing is kept and nothing was ever sent.
ProviderContainer createDemoContainer({required VoidCallback onExit}) {
  final backend = DemoBackend();
  return ProviderContainer(overrides: [
    // Silent: pretend sales must not count in the pilot's figures. The real
    // tracker records only that the demo was opened (main.dart).
    usageTrackerProvider.overrideWithValue(UsageTracker(app: 'retailer', enabled: false)),
    databaseProvider.overrideWith((ref) async {
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      ref.onDispose(db.close);
      await _seedToday(db);
      return db;
    }),
    freshTokenProvider.overrideWithValue(() async => 'demo'),
    apiClientProvider.overrideWith((ref) {
      final client = ApiClient(inner: backend, tokenProvider: () async => 'demo', baseUrl: 'https://demo.fidelia.invalid');
      ref.onDispose(client.close);
      return client;
    }),
    sessionProvider.overrideWith(() => DemoSession(onExit)),
  ]);
}

/// A morning's worth of sales, so "Aujourd'hui" is not empty.
Future<void> _seedToday(AppDatabase db) async {
  final dao = SaleDao(db.db);
  final now = DateTime.now();
  final sales = [(2500, 'sale', 3, null), (1500, 'sale', 2, '+2250712345678'), (4000, 'sale', 1, null)];
  for (final (i, (amount, type, hoursAgo, customer)) in sales.indexed) {
    final sale = await dao.insert(Sale(
      idempotencyKey: 'demo-seed-$i',
      amount: Money.fromMajor(amount, 'XOF'),
      type: type,
      recordedAt: now.subtract(Duration(hours: hoursAgo)),
      customerRef: customer,
      customerConsent: customer != null,
    ));
    await dao.markSynced(localId: sale.localId!, serverId: 1000 + i, pointsAwarded: customer != null ? amount ~/ 100 : null);
  }
}

/// Signed in as the demo shop's owner, so every screen is there to try.
/// "Se déconnecter" leaves the demo.
class DemoSession extends SessionNotifier {
  DemoSession(this._onExit);

  final VoidCallback _onExit;

  @override
  SessionState build() => const SessionState(signedIn: true, checked: true, username: Strings.demoShopName);

  @override
  Future<void> signOut() async => _onExit();

  @override
  void onTokenRejected() {}
}

/// Lets the sign-in screen start the demo and the demo bar leave it.
class DemoHost extends InheritedWidget {
  const DemoHost({super.key, required this.active, required this.start, required this.stop, required super.child});

  final bool active;
  final VoidCallback start;
  final VoidCallback stop;

  static DemoHost? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DemoHost>();

  @override
  bool updateShouldNotify(DemoHost oldWidget) => active != oldWidget.active;
}

/// Under every demo screen: a "DEMO" bar saying nothing is sent, with the way
/// to a real account.
class DemoFrame extends StatelessWidget {
  const DemoFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final host = DemoHost.maybeOf(context);
    return Column(
      children: [
        Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: child)),
        Material(
          color: FideliaColors.ink,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: FideliaColors.green, borderRadius: BorderRadius.circular(99)),
                    child: const Text(Strings.demoBadge,
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(Strings.demoBar, style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: host?.stop,
                    // The theme makes buttons full width; not in this row.
                    style: FilledButton.styleFrom(
                      backgroundColor: FideliaColors.orange,
                      minimumSize: const Size(0, 40),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(Strings.demoSignIn),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
