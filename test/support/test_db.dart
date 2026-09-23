import 'package:djassa_merchant/core/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the real schema in memory.
///
/// Using the actual SQLite engine rather than a mock matters here: the sale
/// queue relies on a UNIQUE constraint on `idempotency_key` and on foreign-key
/// enforcement, and a hand-rolled fake would happily accept writes the device
/// would reject.
Future<AppDatabase> openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return AppDatabase.open(path: inMemoryDatabasePath);
}
