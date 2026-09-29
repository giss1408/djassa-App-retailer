import 'money.dart';

/// Where a locally recorded sale stands relative to the server.
///
/// This is the client's own lifecycle, not the backend's: the backend has no
/// concept of a pending sale, because a sale only reaches it once we send it.
enum SaleSyncState {
  /// Written to the local database, not yet sent. The merchant's source of
  /// truth until it is.
  pending,

  /// Sent and accepted. Carries a server id.
  synced,

  /// The server refused it permanently (validation, duplicate key conflict).
  /// Retrying byte-for-byte will fail again, so it needs the merchant's
  /// attention rather than another attempt.
  rejected;

  static SaleSyncState fromStorage(String value) => switch (value) {
        'pending' => SaleSyncState.pending,
        'synced' => SaleSyncState.synced,
        'rejected' => SaleSyncState.rejected,
        // An unknown state in the database is treated as pending: re-sending
        // is safe because of the idempotency key, whereas dropping a sale
        // loses the merchant's money.
        _ => SaleSyncState.pending,
      };

  String get storageValue => name;
}

/// A sale recorded at the counter.
///
/// Maps to the backend's `sale_events` stream (as `cash_declared`), with the
/// local-only fields the offline queue needs. Immutable: a recorded sale is
/// amended by writing a new row, never by mutating history in place.
class Sale {
  const Sale({
    this.localId,
    required this.idempotencyKey,
    required this.amount,
    required this.type,
    required this.recordedAt,
    this.serverId,
    this.syncState = SaleSyncState.pending,
    this.attemptCount = 0,
    this.lastError,
    this.customerRef,
  });

  /// sqflite rowid. Null until inserted.
  final int? localId;

  /// Generated on the device before the first send attempt, and reused for
  /// every retry of *this* sale.
  ///
  /// This is the whole reason a dropped response cannot become a double
  /// charge: the backend looks the key up and returns the existing
  /// transaction instead of creating a second one
  /// (`app/api/sales.py`, `app/services/sale_events.py`).
  final String idempotencyKey;

  final Money amount;

  /// Free-form category the backend stores verbatim, max 32 chars.
  final String type;

  /// When the merchant recorded it on the device, which is not when the server
  /// received it. Sent as `occurred_at`; the server records its own
  /// `recorded_at` alongside, and keeps the gap because the offline window is
  /// itself a signal. The merchant's daily total uses this one.
  final DateTime recordedAt;

  /// The backend's transaction id, once accepted.
  final int? serverId;

  final SaleSyncState syncState;

  /// How many times we have tried to send this. Drives the retry backoff and
  /// stops an unsendable row from consuming the data bundle forever.
  final int attemptCount;

  /// Why the last attempt failed, for the merchant to read. Never contains a
  /// token or a raw server payload.
  final String? lastError;

  /// Optional customer identifier (phone or QR payload) captured at the
  /// counter. Local-only today: the backend's transaction schema has no field
  /// for it, and loyalty endpoints do not exist yet.
  final String? customerRef;

  bool get isPending => syncState == SaleSyncState.pending;

  Sale copyWith({
    int? localId,
    int? serverId,
    SaleSyncState? syncState,
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return Sale(
      localId: localId ?? this.localId,
      idempotencyKey: idempotencyKey,
      amount: amount,
      type: type,
      recordedAt: recordedAt,
      serverId: serverId ?? this.serverId,
      syncState: syncState ?? this.syncState,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      customerRef: customerRef,
    );
  }

  /// The body shape `POST /api/merchant/sales` expects.
  ///
  /// Two fields are deliberately absent, for the same reason: **the server
  /// decides who a sale belongs to, not the client.**
  ///
  /// * `user_id` — ownership comes from the bearer token.
  /// * `merchant_id` — the venue is derived from the token too
  ///   (`app/api/sales.py`). The old endpoint took it from the body, so this app
  ///   sent a hardcoded id and the backend created a merchant row to match it.
  ///   Sending it now would be ignored at best and misleading at worst.
  Map<String, Object?> toApiJson() => {
        'amount': amount.toWireString(),
        'currency': amount.currency,
        'type': type,
        // The merchant's own clock, so a sale queued overnight counts on the day
        // it was made rather than the day the network came back.
        'occurred_at': recordedAt.toUtc().toIso8601String(),
      };

  /// The per-operation shape inside `POST /api/merchant/sales/sync`, which is
  /// the same plus the idempotency key.
  Map<String, Object?> toSyncOperationJson() => {
        ...toApiJson(),
        'idempotency_key': idempotencyKey,
      };
}
