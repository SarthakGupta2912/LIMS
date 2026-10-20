// Reads and writes synced rows by UUID.
// Why it exists: delta sync must never use plain INSERT (duplicates on
// retry). All writes here are INSERT ... ON CONFLICT(uuid) upserts and
// sync_status only flips to synced after an ACK arrives.

import '../core/app_database.dart';

// Same allow-list as the Step 3 migration. Keeps table names safe.
const List<String> deltaTables = [
  'products',
  'customers',
  'invoices',
  'invoice_items',
  'payments',
  'local_orders',
  'local_order_items',
];

bool isDeltaTable(String table) => deltaTables.contains(table);

// Rows changed after peerLastSyncedAt, oldest first, bounded.
List<Map<String, Object?>> fetchChangedRows(
  AppDatabase store,
  String table,
  int peerLastSyncedAt, {
  int limit = 50,
}) {
  if (!isDeltaTable(table)) return [];
  final rows = store.db.select(
    'SELECT * FROM $table WHERE updated_at > ? '
    'ORDER BY updated_at ASC LIMIT ?',
    [peerLastSyncedAt, limit],
  );
  return rows.map((row) => Map<String, Object?>.from(row)).toList();
}

// UUID upsert. New UUIDs insert, known UUIDs update only if incoming
// version is newer or equal. Returns the UUIDs that were applied.
List<String> upsertRowsByUuid(
    AppDatabase store, String table, List<Map<String, Object?>> rows) {
  if (!isDeltaTable(table) || rows.isEmpty) return [];
  final database = store.db;
  final applied = <String>[];
  database.execute('BEGIN');
  try {
    for (final row in rows) {
      final uuid = row['uuid'] as String?;
      if (uuid == null || uuid.isEmpty) continue;
      final columns = row.keys.where((key) => key != 'id').toList();
      final placeholders = List.filled(columns.length, '?').join(', ');
      final updates = columns
          .where((column) => column != 'uuid')
          .map((column) => '$column = excluded.$column')
          .join(', ');
      database.execute(
        'INSERT INTO $table(${columns.join(', ')}) VALUES($placeholders) '
        'ON CONFLICT(uuid) DO UPDATE SET $updates '
        'WHERE excluded.version >= $table.version',
        [for (final column in columns) row[column]],
      );
      applied.add(uuid);
    }
    database.execute('COMMIT');
  } catch (_) {
    database.execute('ROLLBACK');
    rethrow;
  }
  return applied;
}

// Only called after the receiver ACKs these UUIDs.
void markRowsSynced(AppDatabase store, String table, List<String> uuids) {
  if (!isDeltaTable(table) || uuids.isEmpty) return;
  final database = store.db;
  final placeholders = List.filled(uuids.length, '?').join(', ');
  database.execute(
    "UPDATE $table SET sync_status = 'synced' WHERE uuid IN ($placeholders)",
    uuids,
  );
}
