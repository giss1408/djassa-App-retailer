import 'money.dart';
import 'phone.dart';

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
    this.customerConsent = false,
    this.pointsAwarded,
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

  /// The customer's phone number, captured at the counter and normalised to
  /// E.164 before saving (`normalizeIvorianPhone`). Sent as `customer_phone`,
  /// so the customer earns this venue's points on the sale.
  final String? customerRef;

  /// The merchant asked and the customer agreed that Djassa keeps their
  /// number for points. Without it the number is not sent (see [toApiJson]).
  final bool customerConsent;

  /// Points the server granted the customer, once the sale is accepted. Null
  /// while pending, or for a sale recorded before points existed.
  final int? pointsAwarded;

  bool get isPending => syncState == SaleSyncState.pending;

  Sale copyWith({
    int? localId,
    int? serverId,
    SaleSyncState? syncState,
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
    int? pointsAwarded,
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
      customerConsent: customerConsent,
      pointsAwarded: pointsAwarded ?? this.pointsAwarded,
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
        // Only a number that normalises is sent. A sale queued by an older
        // version of this app may hold free text here; sending it would get
        // the whole sale rejected, and a rejected sale is money missing from
        // the merchant's books. Better to record it without the points.
        //
        // Same for a number without the customer's consent (queued before
        // this app asked for it): the server would refuse the sale for a
        // number it has no consent for, so it goes without the number.
        if (_customerPhone != null) ...{
          'customer_phone': _customerPhone,
          'customer_consent': true,
        },
      };

  String? get _customerPhone {
    final ref = customerRef;
    return ref == null || !customerConsent ? null : normalizeIvorianPhone(ref);
  }

  /// The per-operation shape inside `POST /api/merchant/sales/sync`, which is
  /// the same plus the idempotency key.
  Map<String, Object?> toSyncOperationJson() => {
        ...toApiJson(),
        'idempotency_key': idempotencyKey,
      };
}
