// Runs one delta-sync round using timestamps and ACKs.
// Why it exists: this is the brain of Step 4. It decides what to send
// (rows newer than the peer), applies what arrives (UUID upsert), and
// only marks sent rows synced after the ACK. No Nearby code lives here.

import '../core/app_database.dart';
import 'delta_store.dart';
import 'sync_message.dart';

const String lastSyncedAtKey = 'nearby_last_synced_at';

int loadLastSyncedAt(AppDatabase store) {
  final saved = store.setting(lastSyncedAtKey);
  return int.tryParse(saved ?? '0') ?? 0;
}

void saveLastSyncedAt(AppDatabase store, int timestamp) {
  store.setSetting(lastSyncedAtKey, '$timestamp');
}

// One delta message per table, only rows the peer has not seen.
List<Map<String, dynamic>> buildOutgoingDeltas(
    AppDatabase store, int peerLastSyncedAt) {
  final deltas = <Map<String, dynamic>>[];
  for (final table in deltaTables) {
    final rows = fetchChangedRows(store, table, peerLastSyncedAt);
    if (rows.isNotEmpty) {
      deltas.add(buildDeltaMessage(table, rows));
    }
  }
  return deltas;
}

// Receiver side: upsert rows, then reply with an ACK for applied UUIDs.
Map<String, dynamic> applyIncomingDelta(
    AppDatabase store, Map<String, dynamic> delta) {
  final table = delta['table'] as String? ?? '';
  final rows = (delta['rows'] as List? ?? [])
      .whereType<Map>()
      .map((row) => Map<String, Object?>.from(row))
      .toList();
  final applied = upsertRowsByUuid(store, table, rows);
  return buildAckMessage(table, applied);
}

// Sender side: peer confirmed receipt, so flip to synced.
void applyIncomingAck(AppDatabase store, Map<String, dynamic> ack) {
  final table = ack['table'] as String? ?? '';
  final uuids = (ack['uuids'] as List? ?? []).whereType<String>().toList();
  markRowsSynced(store, table, uuids);
  saveLastSyncedAt(store, DateTime.now().millisecondsSinceEpoch);
}
