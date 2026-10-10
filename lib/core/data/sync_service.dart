import 'dart:async';
import 'dart:math';

import '../model/sale.dart';
import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'sale_dao.dart';

/// What a sync pass achieved, for the UI to report honestly.
class SyncOutcome {
  const SyncOutcome({
    this.sent = 0,
    this.alreadyOnServer = 0,
    this.rejected = 0,
    this.remaining = 0,
    this.failure,
  });

  /// Sales the server accepted on this pass.
  final int sent;

  /// Sales the server already had, recognised by their idempotency key. Not an
  /// error — it is the duplicate protection working, and it means an earlier
  /// attempt did reach the server even though we never saw the response.
  final int alreadyOnServer;

  /// Sales the server refused permanently.
  final int rejected;

  /// Still queued after this pass.
  final int remaining;

  /// Set when the pass could not run at all (offline, signed out, server down).
  /// Individual rejections are counted in [rejected] instead.
  final ApiException? failure;

  bool get didReachServer => failure == null;
  bool get changedAnything => sent > 0 || alreadyOnServer > 0 || rejected > 0;
}

/// Pushes queued sales to the backend in batches.
///
/// ## The guarantee
///
/// A sale is recorded locally first and sent later. Every send carries the
/// idempotency key generated when the sale was recorded, so the backend can
/// recognise a repeat: it looks the key up and returns the existing sale event
/// rather than creating a second one (`app/api/sales.py`).
///
/// This matters because on a flaky network **we cannot distinguish a lost
/// request from a lost response**. Without the key, every timeout would force a
/// choice between losing a sale and double-recording it. With it, the safe
/// action is always to retry.
///
/// ## Why batches
///
/// `POST /api/merchant/sales/sync` takes up to 50 operations in one request. On
/// 2G, fifty round trips cost fifty TLS-protected exchanges and a lot of the
/// merchant's data bundle; one request costs one. The backend commits each
/// operation separately and returns a per-operation result, so a single bad row
/// cannot block the rest.
class SyncService {
  SyncService({
    required ApiClient client,
    required SaleDao dao,
    Duration baseBackoff = const Duration(seconds: 30),
    Duration maxBackoff = const Duration(hours: 6),
    int maxAttempts = 12,
    Random? random,
  })  : _client = client,
        _dao = dao,
        _baseBackoff = baseBackoff,
        _maxBackoff = maxBackoff,
        _maxAttempts = maxAttempts,
        _random = random ?? Random();

  final ApiClient _client;
  final SaleDao _dao;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final int _maxAttempts;
  final Random _random;

  /// Guards against two passes running at once, which would send the same
  /// batch twice. Harmless thanks to idempotency, but it wastes data.
  bool _running = false;
  bool get isRunning => _running;

  /// Sends one batch, if anything is due.
  ///
  /// Returns without touching the network when the queue is empty, so calling
  /// this on every app resume is free.
  Future<SyncOutcome> syncOnce() async {
    if (_running) {
      return SyncOutcome(remaining: await _dao.pendingCount());
    }
    _running = true;
    try {
      final batch = await _dao.pendingBatch();
      if (batch.isEmpty) {
        return SyncOutcome(remaining: await _dao.pendingCount());
      }
      return await _sendBatch(batch);
    } finally {
      _running = false;
    }
  }

  /// Drains the queue, one batch per round trip.
  ///
  /// Stops at the first failure that reaches nothing — there is no point
  /// burning through batches while offline — and at [maxPasses] so a
  /// pathological queue cannot loop forever.
  Future<SyncOutcome> drain({int maxPasses = 20}) async {
    var sent = 0;
    var already = 0;
    var rejected = 0;
    ApiException? failure;

    for (var pass = 0; pass < maxPasses; pass++) {
      final outcome = await syncOnce();
      sent += outcome.sent;
      already += outcome.alreadyOnServer;
      rejected += outcome.rejected;
      if (!outcome.didReachServer) {
        failure = outcome.failure;
        break;
      }
      if (!outcome.changedAnything) break;
    }

    return SyncOutcome(
      sent: sent,
      alreadyOnServer: already,
      rejected: rejected,
      remaining: await _dao.pendingCount(),
      failure: failure,
    );
  }

  Future<SyncOutcome> _sendBatch(List<Sale> batch) async {
    final byKey = {for (final sale in batch) sale.idempotencyKey: sale};

    Map<String, Object?> response;
    try {
      response = await _client.postJson(
        '/api/merchant/sales/sync',
        body: {
          'operations':
              batch.map((sale) => sale.toSyncOperationJson()).toList(),
        },
      );
    } on ApiException catch (error) {
      // The whole request failed, so no operation was decided. Back every row
      // off rather than guessing which ones the server saw.
      await _backOffAll(batch, error.message);
      return SyncOutcome(
        remaining: await _dao.pendingCount(),
        failure: error,
      );
    }

    final results = response['results'];
    if (results is! List) {
      const error = MalformedResponseException('Reponse inattendue du serveur. Reessayez.');
      await _backOffAll(batch, error.message);
      return SyncOutcome(
        remaining: await _dao.pendingCount(),
        failure: error,
      );
    }

    var sent = 0;
    var already = 0;
    var rejected = 0;
    final decided = <String>{};

    for (final entry in results) {
      if (entry is! Map) continue;
      final key = entry['idempotency_key'];
      if (key is! String) continue;
      final sale = byKey[key];
      // A result for a key we did not send is ignored rather than trusted.
      if (sale?.localId == null) continue;
      decided.add(key);

      final status = entry['status'];
      final serverId = _serverIdOf(entry['sale']);
      final points = _pointsOf(entry['sale']);

      switch (status) {
        case 'accepted':
          await _dao.markSynced(localId: sale!.localId!, serverId: serverId, pointsAwarded: points);
          sent++;
        case 'already_processed':
          // The key was already on the server: an earlier attempt landed and we
          // never saw the reply. Exactly the duplicate we exist to prevent.
          // The server reports the points it granted then, not new ones.
          await _dao.markSynced(localId: sale!.localId!, serverId: serverId, pointsAwarded: points);
          already++;
        case 'rejected':
          final reason = entry['error'];
          await _dao.markRejected(
            localId: sale!.localId!,
            error: reason is String ? reason : 'Le serveur a refuse cette vente',
          );
          rejected++;
        default:
          // An unknown status is treated as retryable: keeping the sale is
          // always safer than discarding it.
          await _dao.markRetryable(
            localId: sale!.localId!,
            error: 'Unexpected sync status: $status',
            nextAttemptAt: _nextAttempt(sale.attemptCount + 1),
          );
      }
    }

    // Rows the server did not mention at all. Back them off; they stay queued.
    final undecided =
        batch.where((sale) => !decided.contains(sale.idempotencyKey));
    for (final sale in undecided) {
      if (sale.localId == null) continue;
      await _dao.markRetryable(
        localId: sale.localId!,
        error: 'No result returned for this sale',
        nextAttemptAt: _nextAttempt(sale.attemptCount + 1),
      );
    }

    return SyncOutcome(
      sent: sent,
      alreadyOnServer: already,
      rejected: rejected,
      remaining: await _dao.pendingCount(),
    );
  }

  int? _pointsOf(Object? sale) {
    if (sale is Map) {
      final points = sale['points_awarded'];
      if (points is int) return points;
    }
    return null;
  }

  int? _serverIdOf(Object? sale) {
    if (sale is Map) {
      final id = sale['id'];
      if (id is int) return id;
    }
    return null;
  }

  Future<void> _backOffAll(List<Sale> batch, String error) async {
    for (final sale in batch) {
      if (sale.localId == null) continue;
      await _dao.markRetryable(
        localId: sale.localId!,
        error: error,
        nextAttemptAt: _nextAttempt(sale.attemptCount + 1),
      );
    }
  }

  /// Exponential backoff with jitter, capped.
  ///
  /// Two reasons beyond politeness to the server: retrying hard over 2G spends
  /// the merchant's data bundle on failures, and it drains a small battery.
  /// The jitter stops every device in a market that lost the same cell from
  /// retrying in lockstep when it returns.
  ///
  /// After [_maxAttempts] the delay stays at the cap rather than growing
  /// without limit — the sale is never abandoned, just retried sparingly.
  DateTime _nextAttempt(int attemptCount) {
    final clamped = min(attemptCount, _maxAttempts);
    final exponential = _baseBackoff.inMilliseconds * pow(2, clamped - 1);
    final capped = min(exponential.toDouble(), _maxBackoff.inMilliseconds.toDouble());
    // Full jitter over [0.5x, 1.0x] of the capped delay.
    final jittered = capped * (0.5 + _random.nextDouble() * 0.5);
    return DateTime.now().toUtc().add(Duration(milliseconds: jittered.round()));
  }
}
