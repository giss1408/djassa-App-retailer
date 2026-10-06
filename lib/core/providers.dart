import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_repository.dart';
import 'auth/token_store.dart';
import 'data/database.dart';
import 'data/sale_dao.dart';
import 'data/sale_repository.dart';
import 'data/sync_service.dart';
import 'deals_api.dart';
import 'location_api.dart';
import 'media_api.dart';
import 'wave_api.dart';
import 'loyalty_api.dart';
import 'payment_api.dart';
import 'staff_api.dart';
import 'monitoring/usage_tracker.dart';
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

/// Pilot usage analytics. Disabled here; `main` overrides it with the live
/// tracker, so tests and previews never send anything.
final usageTrackerProvider = Provider<UsageTracker>((ref) => UsageTracker(app: 'retailer', enabled: false));

/// The current access token, renewed first when it is past its hour. Shared
/// by the API client and the usage tracker (which ties events to the shop).
final Provider<TokenProvider> freshTokenProvider = Provider<TokenProvider>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  // Read lazily: the auth repository itself talks through the API client.
  return () async {
    final token = await tokenStore.readToken();
    if (token == null || token.isEmpty || !isTokenExpired(token)) return token;
    return await ref.read(authRepositoryProvider).refresh() ? tokenStore.readToken() : token;
  };
});

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);
  final client = ApiClient(
    // An access token past its hour is renewed before the request rather
    // than spending a round trip on a certain 401.
    tokenProvider: ref.watch(freshTokenProvider),
    onTraffic: ref.watch(usageTrackerProvider).addTraffic,
    // A 401 anyway (token revoked, clock skew): renew once and replay.
    // Offline, renewal throws a NetworkException instead of answering, so a
    // merchant with queued sales is never signed out by a dead cell.
    onRefresh: () => ref.read(authRepositoryProvider).refresh(),
    // Renewal refused too: the session is over. Clear it once, here, so no
    // call site has to remember to.
    onUnauthorized: () async {
      await tokenStore.clear();
      ref.read(sessionProvider.notifier).onTokenRejected();
    },
  );
  ref.onDispose(client.close);
  return client;
});

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final dealsApiProvider = Provider<DealsApi>((ref) => DealsApi(ref.watch(apiClientProvider)));

final loyaltyApiProvider = Provider<LoyaltyApi>((ref) => LoyaltyApi(ref.watch(apiClientProvider)));

final locationApiProvider = Provider<LocationApi>((ref) => LocationApi(ref.watch(apiClientProvider)));
final mediaApiProvider = Provider<MediaApi>((ref) => MediaApi(ref.watch(apiClientProvider)));
final waveApiProvider = Provider<WaveApi>((ref) => WaveApi(ref.watch(apiClientProvider)));

final paymentApiProvider = Provider<PaymentApi>((ref) => PaymentApi(ref.watch(apiClientProvider)));
final staffApiProvider = Provider<StaffApi>((ref) => StaffApi(ref.watch(apiClientProvider)));

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

/// Whether the merchant is signed in, and as whom.
class SessionState {
  const SessionState({required this.signedIn, this.username, this.checked = false, this.role = 'merchant'});

  final bool signedIn;
  final String? username;

  /// "merchant" (the shop owner) or "cashier" (staff the owner added). A
  /// cashier records sales, collects payments and serves points; money
  /// settings, deals, photos, location and the team stay with the owner.
  final String role;

  bool get isOwner => role != 'cashier';

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
      role: await _role(),
    );
  }

  Future<String> _role() async {
    final token = await ref.read(tokenStoreProvider).readToken();
    return token == null || token.isEmpty ? 'merchant' : jwtRole(token);
  }

  Future<SignInResult> verifyCode({required String phone, required String code}) async {
    final result = await ref.read(authRepositoryProvider).verifyCode(phone: phone, code: code);
    if (result is SignInSuccess) {
      state = SessionState(
        signedIn: true,
        username: result.username,
        checked: true,
        role: await _role(),
      );
    }
    return result;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const SessionState(signedIn: false, checked: true);
  }


  /// The account moved to another number; this device holds its new session.
  void onNumberChanged(String username) {
    state = SessionState(signedIn: true, username: username, checked: true, role: state.role);
  }

  /// Called when the server rejects our token mid-session.
  void onTokenRejected() {
    state = const SessionState(signedIn: false, checked: true);
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// The Hossouko team's WhatsApp link for suggestions: free for shops, so it is
/// there as soon as the server has a number set. Null keeps the menu entry
/// hidden, including when offline.
final suggestionsLinkProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final json = await ref.watch(apiClientProvider).getJson('/api/support/suggestions/whatsapp');
    return json['available'] == true ? json['whatsapp_url'] as String? : null;
  } catch (_) {
    return null;
  }
});
