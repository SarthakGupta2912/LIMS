// Adds the three delta-sync columns to existing SQLite tables.
// Why it exists: Nearby delta sync needs sync_status, updated_at, and
// version on every synced row to send only changes and ACK by ID.
// This runs safely on old installs: it only adds columns that are missing.

import 'package:sqlite3/sqlite3.dart';

// Tables that take part in Nearby delta sync.
const List<String> syncedTables = [
  'products',
  'customers',
  'invoices',
  'invoice_items',
  'payments',
  'local_orders',
  'local_order_items',
];

bool _hasColumn(Database database, String table, String column) {
  final rows = database.select('PRAGMA table_info($table)');
  for (final row in rows) {
    if (row['name'] == column) return true;
  }
  return false;
}

void _ensureColumn(Database database, String table, String column,
    String definition) {
  if (!_hasColumn(database, table, column)) {
    database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}

// Idempotent migration to user_version 3. Safe to call on every open.
void applyNearbySyncColumns(Database database) {
  final currentVersion =
      (database.select('PRAGMA user_version').first.values.first as int?) ??
          0;
  if (currentVersion >= 3) return;

  database.execute('BEGIN');
  try {
    for (final table in syncedTables) {
      _ensureColumn(
        database,
        table,
        'sync_status',
        "TEXT NOT NULL DEFAULT 'pending' "
        "CHECK(sync_status IN ('pending', 'synced', 'failed'))",
      );
      _ensureColumn(
        database,
        table,
        'updated_at',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _ensureColumn(
        database,
        table,
        'version',
        'INTEGER NOT NULL DEFAULT 1',
      );
    }

    // Backfill timestamps so delta queries never see 0 or NULL.
    database.execute(
      'UPDATE invoices SET updated_at = created_at '
      'WHERE updated_at = 0 OR updated_at IS NULL',
    );
    database.execute(
      'UPDATE invoice_items SET updated_at = 0 WHERE updated_at IS NULL',
    );
    database.execute(
      'UPDATE payments SET updated_at = 0 WHERE updated_at IS NULL',
    );
    database.execute(
      'UPDATE local_order_items SET updated_at = 0 WHERE updated_at IS NULL',
    );

    // Helpful indexes for "rows updated after X" delta queries.
    for (final table in syncedTables) {
      database.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_updated '
        'ON $table(updated_at)',
      );
    }

    database.execute(
      'INSERT OR IGNORE INTO schema_migrations(version, applied_at) '
      'VALUES(3, ?)',
      [DateTime.now().millisecondsSinceEpoch],
    );
    database.execute('PRAGMA user_version = 3');
    database.execute('COMMIT');
  } catch (_) {
    database.execute('ROLLBACK');
    rethrow;
  }
}
