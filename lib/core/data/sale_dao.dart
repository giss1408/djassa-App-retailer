import 'package:sqflite/sqflite.dart';

import '../model/money.dart';
import '../model/sale.dart';

/// Reads and writes sales. All SQL for the ledger lives here.
class SaleDao {
  const SaleDao(this._db);

  final Database _db;

  /// Records a sale locally and returns it with its assigned `local_id`.
  ///
  /// This is the write that must never fail silently. It completes before the
  /// UI confirms the sale to the merchant, so a confirmation on screen always
  /// means the row is on disk — not in flight, not in memory.
  Future<Sale> insert(Sale sale) async {
    final localId = await _db.insert('sales', {
      'idempotency_key': sale.idempotencyKey,
      // `merchant_id` is a vestigial NOT NULL column: the server derives the
      // venue from the token now, but SQLite before 3.35 (Android < 14, and
      // minSdk here is 21) cannot DROP COLUMN, and recreating `sales` would
      // risk a merchant's unsynced sales. Written as 0 and never read.
      'merchant_id': 0,
      'amount_minor': sale.amount.minorUnits,
      'currency': sale.amount.currency,
      'type': sale.type,
      'recorded_at': sale.recordedAt.toUtc().millisecondsSinceEpoch,
      'customer_ref': sale.customerRef,
      'server_id': sale.serverId,
      'sync_state': sale.syncState.storageValue,
      'attempt_count': sale.attemptCount,
      // Eligible for the next sync pass immediately.
      'next_attempt_at': 0,
      'last_error': sale.lastError,
    });
    return sale.copyWith(localId: localId);
  }

  /// The next batch to send.
  ///
  /// Capped at 50 because that is the backend's hard limit on
  /// `SaleSyncIn.operations` (`app/schemas/customer.py`); a larger batch is
  /// rejected wholesale. Oldest first, so a long outage drains in the order the
  /// merchant made the sales.
  Future<List<Sale>> pendingBatch({int limit = 50}) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final rows = await _db.query(
      'sales',
      where: 'sync_state = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      whereArgs: [SaleSyncState.pending.storageValue, now],
      orderBy: 'local_id ASC',
      limit: limit > 50 ? 50 : limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// How many sales are waiting, including those in backoff.
  ///
  /// Shown to the merchant as a plain count: on an unreliable network, "3 sales
  /// not yet sent" is the difference between trusting the app and not.
  Future<int> pendingCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales WHERE sync_state = ?',
      [SaleSyncState.pending.storageValue],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<int> rejectedCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales WHERE sync_state = ?',
      [SaleSyncState.rejected.storageValue],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Marks a sale accepted by the server.
  Future<void> markSynced({required int localId, required int? serverId, int? pointsAwarded}) async {
    await _db.update(
      'sales',
      {
        'sync_state': SaleSyncState.synced.storageValue,
        'server_id': serverId,
        'points_awarded': pointsAwarded,
        'last_error': null,
        'next_attempt_at': null,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Records a failed attempt that is worth repeating, with the backoff moment
  /// the caller computed.
  Future<void> markRetryable({
    required int localId,
    required String error,
    required DateTime nextAttemptAt,
  }) async {
    await _db.rawUpdate(
      '''
      UPDATE sales
         SET attempt_count   = attempt_count + 1,
             last_error      = ?,
             next_attempt_at = ?
       WHERE local_id = ?
      ''',
      [error, nextAttemptAt.toUtc().millisecondsSinceEpoch, localId],
    );
  }

  /// Marks a sale the server refused permanently.
  ///
  /// The row is kept, never deleted. It is a record of money the merchant took;
  /// deleting it to tidy a queue would erase their books. It surfaces in the UI
  /// for the merchant to resolve.
  Future<void> markRejected({
    required int localId,
    required String error,
  }) async {
    await _db.rawUpdate(
      '''
      UPDATE sales
         SET sync_state      = ?,
             attempt_count   = attempt_count + 1,
             last_error      = ?,
             next_attempt_at = NULL
       WHERE local_id = ?
      ''',
      [SaleSyncState.rejected.storageValue, error, localId],
    );
  }

  /// Puts a rejected sale back in the queue, after the merchant asked for it.
  ///
  /// The idempotency key is deliberately unchanged: if the original attempt did
  /// reach the server despite the error we saw, the retry returns that same
  /// transaction instead of creating a duplicate.
  Future<void> requeue(int localId) async {
    await _db.update(
      'sales',
      {
        'sync_state': SaleSyncState.pending.storageValue,
        'next_attempt_at': 0,
        'last_error': null,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Most recent sales for the merchant's own review.
  Future<List<Sale>> recent({int limit = 50}) async {
    final rows = await _db.query(
      'sales',
      orderBy: 'recorded_at DESC, local_id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// Sales recorded within a local calendar day, for the day's total.
  ///
  /// Uses [recordedAt], not the server timestamp: a sale made at 22:00 and
  /// synced at 08:00 the next morning belongs to the day the merchant made it.
  Future<List<Sale>> forLocalDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.query(
      'sales',
      where: 'recorded_at >= ? AND recorded_at < ?',
      whereArgs: [
        start.toUtc().millisecondsSinceEpoch,
        end.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Sale _fromRow(Map<String, Object?> row) {
    final currency = row['currency'] as String;
    final minor = row['amount_minor'] as int;
    return Sale(
      localId: row['local_id'] as int?,
      idempotencyKey: row['idempotency_key'] as String,
      amount: Money.fromMinor(minor, currency),
      type: row['type'] as String,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at'] as int,
        isUtc: true,
      ).toLocal(),
      customerRef: row['customer_ref'] as String?,
      serverId: row['server_id'] as int?,
      syncState: SaleSyncState.fromStorage(row['sync_state'] as String),
      attemptCount: (row['attempt_count'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
      pointsAwarded: row['points_awarded'] as int?,
    );
  }
}
