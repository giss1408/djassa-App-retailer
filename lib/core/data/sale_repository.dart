import 'dart:convert';
import 'dart:math';

import '../model/money.dart';
import '../model/sale.dart';
import 'sale_dao.dart';
import 'sync_service.dart';

/// Records sales and reports on them. The app's entry point to the ledger.
///
/// The ordering rule this class enforces: **write locally, then try to send.**
/// Never the reverse. A merchant at a stall with no signal must be able to take
/// money and move to the next customer, and the confirmation they see has to
/// mean the sale is on disk.
class SaleRepository {
  SaleRepository({
    required SaleDao dao,
    required SyncService syncService,
    Random? random,
    bool syncAfterRecording = true,
  })  : _dao = dao,
        _syncService = syncService,
        _random = random ?? Random.secure(),
        _syncAfterRecording = syncAfterRecording;

  final SaleDao _dao;
  final SyncService _syncService;
  final Random _random;

  /// Whether recording a sale also kicks off a sync attempt.
  ///
  /// On for the app: the common case is a merchant with signal, and sending
  /// immediately keeps the queue short. Off in tests that need to control
  /// exactly when the network is touched — a background attempt otherwise
  /// races the test's own assertions.
  final bool _syncAfterRecording;

  /// Records a sale and returns immediately once it is durably stored.
  ///
  /// Sync is deliberately **not** awaited. Waiting on a 2G round trip before
  /// confirming would leave the merchant staring at a spinner with a customer
  /// in front of them; worse, a timeout would look like a failure for a sale
  /// that is safely recorded.
  Future<Sale> recordSale({
    required Money amount,
    required String type,
    String? customerRef,
    DateTime? recordedAt,
  }) async {
    if (amount.isNegative || amount.isZero) {
      // The backend enforces gt=0; failing here saves a doomed round trip.
      throw ArgumentError('A sale amount must be greater than zero');
    }

    final sale = Sale(
      idempotencyKey: newIdempotencyKey(_random),
      amount: amount,
      type: type,
      recordedAt: recordedAt ?? DateTime.now(),
      customerRef: customerRef,
    );

    final stored = await _dao.insert(sale);

    // Fire and forget. A failure here changes nothing: the sale is on disk and
    // the next sync pass will pick it up. Deliberately not awaited — see the
    // note above about not making the merchant wait on a 2G round trip.
    if (_syncAfterRecording) {
      _syncService.syncOnce().ignore();
    }

    return stored;
  }

  Future<List<Sale>> recentSales({int limit = 50}) => _dao.recent(limit: limit);

  Future<int> pendingCount() => _dao.pendingCount();

  Future<int> rejectedCount() => _dao.rejectedCount();

  /// Sales the merchant made today, for the day's total.
  Future<List<Sale>> salesToday() => _dao.forLocalDay(DateTime.now());

  /// Sum of today's sales, or null when there are none.
  ///
  /// Returns null rather than a zero amount because with no sales there is no
  /// currency to attribute a zero to, and guessing one would be wrong.
  ///
  /// Sales in different currencies are not summed: mixing XOF and GHS into one
  /// number would be meaningless. Only the dominant currency's total is given,
  /// which in practice is the merchant's only currency.
  Future<Money?> totalToday() async {
    final sales = await _dao.forLocalDay(DateTime.now());
    if (sales.isEmpty) return null;
    final currency = sales.first.amount.currency;
    var total = Money.fromMinor(0, currency);
    for (final sale in sales) {
      if (sale.amount.currency != currency) continue;
      total = total + sale.amount;
    }
    return total;
  }

  /// Asks the sync service to push whatever is queued.
  Future<SyncOutcome> syncNow() => _syncService.drain();

  /// Puts a rejected sale back in the queue at the merchant's request.
  Future<void> retryRejected(int localId) => _dao.requeue(localId);
}

/// Generates an idempotency key for a new sale.
///
/// Requirements, in order of importance:
///
/// 1. **Unique across devices.** Two merchants recording a 1000 XOF sale at the
///    same second must not collide, or one sale would silently replace the
///    other via the backend's key lookup.
/// 2. **Unpredictable.** A guessable key lets someone who can reach the API
///    probe whether a specific sale exists, or claim a key before the real
///    sale arrives. Hence [Random.secure], not a timestamp or a counter.
/// 3. **Within the backend's 8-128 character bound**
///    (`app/schemas/__init__.py:55`).
///
/// 128 bits of randomness, base64url without padding: 22 characters, and no
/// character that needs escaping in a JSON string or an HTTP header.
String newIdempotencyKey(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final encoded = base64Url.encode(bytes).replaceAll('=', '');
  return 'sale-$encoded';
}
