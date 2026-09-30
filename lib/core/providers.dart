import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_repository.dart';
import 'auth/token_store.dart';
import 'data/database.dart';
import 'data/sale_dao.dart';
import 'data/sale_repository.dart';
import 'data/sync_service.dart';
import 'deals_api.dart';
import 'location_api.dart';
import 'wave_api.dart';
import 'loyalty_api.dart';
import 'payment_api.dart';
import 'net/api_client.dart';

/// Wiring for the whole app. Nothing here holds UI state.

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Opened once and kept for the process lifetime. Opening SQLite is slow on a
/// low-end device, so it is never opened per screen.
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final client = ApiClient(
    tokenProvider: tokenStore.readToken,
    // A 401 from any call means the token is dead. Clear it once, here, so no
    // call site has to remember to.
    onUnauthorized: () async {
      await tokenStore.clear();
      ref.read(sessionProvider.notifier).onTokenRejected();
    },
  );
  ref.onDispose(client.close);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final dealsApiProvider = Provider<DealsApi>((ref) => DealsApi(ref.watch(apiClientProvider)));

final loyaltyApiProvider = Provider<LoyaltyApi>((ref) => LoyaltyApi(ref.watch(apiClientProvider)));

final locationApiProvider = Provider<LocationApi>((ref) => LocationApi(ref.watch(apiClientProvider)));
final waveApiProvider = Provider<WaveApi>((ref) => WaveApi(ref.watch(apiClientProvider)));

final paymentApiProvider = Provider<PaymentApi>((ref) => PaymentApi(ref.watch(apiClientProvider)));

final saleDaoProvider = Provider<SaleDao>((ref) {
  // Depends on the database being open; the UI gates on [databaseProvider]
  // before reaching anything that uses this.
  final db = ref.watch(databaseProvider).requireValue;
  return SaleDao(db.db);
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    client: ref.watch(apiClientProvider),
    dao: ref.watch(saleDaoProvider),
  );
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository(
    dao: ref.watch(saleDaoProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

/// Whether the merchant is signed in.
class SessionState {
  const SessionState({required this.signedIn, this.username, this.checked = false});

  final bool signedIn;
  final String? username;

  /// Whether the stored token has been inspected yet. Distinguishes "signed
  /// out" from "we have not looked", so the app does not flash the login screen
  /// at a merchant who is already signed in.
  final bool checked;
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState(signedIn: false);
  }

  /// Reads the stored token at startup.
  Future<void> restore() async {
    final auth = ref.read(authRepositoryProvider);
    final valid = await auth.hasValidSession();
    state = SessionState(
      signedIn: valid,
      username: valid ? await auth.currentUsername() : null,
      checked: true,
    );
  }

  Future<SignInResult> signIn({
    required String username,
    required String password,
  }) async {
    final result = await ref
        .read(authRepositoryProvider)
        .signIn(username: username, password: password);
    if (result is SignInSuccess) {
      state = SessionState(
        signedIn: true,
        username: result.username,
        checked: true,
      );
    }
    return result;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const SessionState(signedIn: false, checked: true);
  }

  /// Called when the server rejects our token mid-session.
  void onTokenRejected() {
    state = const SessionState(signedIn: false, checked: true);
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
