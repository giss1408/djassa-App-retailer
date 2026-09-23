import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the local SQLite database.
///
/// This database is the merchant's source of truth between sales and sync. If a
/// row is lost, money the merchant actually took disappears from their books,
/// so durability wins over speed everywhere the two conflict.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _fileName = 'djassa.db';

  /// Bump on every schema change and add a matching branch in [_migrate].
  static const int schemaVersion = 1;

  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), _fileName);
    final db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        // Enforce the sale -> merchant relationship in the engine rather than
        // trusting every future query to get it right.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => _createSchema(db),
      onUpgrade: (db, from, to) => _migrate(db, from, to),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    // Amounts are stored as INTEGER minor units, never REAL. SQLite's REAL is
    // an IEEE-754 double, and a rounding drift in a sales ledger is a dispute
    // we cannot win. The currency travels with the amount so a row is always
    // interpretable on its own.
    await db.execute('''
      CREATE TABLE sales (
        local_id         INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key  TEXT    NOT NULL UNIQUE,
        merchant_id      INTEGER NOT NULL,
        amount_minor     INTEGER NOT NULL,
        currency         TEXT    NOT NULL,
        type             TEXT    NOT NULL,
        recorded_at      INTEGER NOT NULL,
        customer_ref     TEXT,
        server_id        INTEGER,
        sync_state       TEXT    NOT NULL DEFAULT 'pending',
        attempt_count    INTEGER NOT NULL DEFAULT 0,
        next_attempt_at  INTEGER,
        last_error       TEXT
      )
    ''');

    // The sync loop's only hot query: pending rows whose backoff has elapsed,
    // oldest first. Without this index it degrades to a table scan as the
    // ledger grows over months of use on a slow device.
    await db.execute('''
      CREATE INDEX idx_sales_sync_queue
        ON sales (sync_state, next_attempt_at, local_id)
    ''');

    // Drives the day's totals and the recent-sales list.
    await db.execute('''
      CREATE INDEX idx_sales_recorded_at ON sales (recorded_at DESC)
    ''');

    // A cache of `/api/config/countries`, so currency, phone prefixes and
    // support channels work offline. Fetched rarely; it barely changes.
    await db.execute('''
      CREATE TABLE country_config (
        code              TEXT PRIMARY KEY,
        name              TEXT NOT NULL,
        currency          TEXT NOT NULL,
        phone_prefixes    TEXT NOT NULL,
        languages         TEXT NOT NULL,
        support_channels  TEXT NOT NULL,
        payment_providers TEXT NOT NULL,
        fetched_at        INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    // Only v1 exists. When v2 arrives, add an `if (from < 2)` block here that
    // migrates forward without dropping the sales table: a merchant who
    // upgrades with unsynced sales must not lose them.
    //
    // Never recreate `sales` from scratch in a migration.
  }

  Future<void> close() => db.close();
}
