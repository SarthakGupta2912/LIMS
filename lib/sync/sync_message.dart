// Defines the three JSON messages used by Nearby delta sync.
// Why it exists: both phones must agree on hello/delta/ack shapes.
// This file has no database or transport code, only encoding.

import 'dart:convert';
import 'dart:typed_data';

// hello: {"type":"hello","lastSyncedAt":123}
// delta: {"type":"delta","table":"customers","rows":[{...}]}
// ack:   {"type":"ack","table":"customers","uuids":["..."]}
Map<String, dynamic> buildHelloMessage(int lastSyncedAt) {
  return {'type': 'hello', 'lastSyncedAt': lastSyncedAt};
}

Map<String, dynamic> buildDeltaMessage(
    String table, List<Map<String, Object?>> rows) {
  return {'type': 'delta', 'table': table, 'rows': rows};
}

Map<String, dynamic> buildAckMessage(String table, List<String> uuids) {
  return {'type': 'ack', 'table': table, 'uuids': uuids};
}

Uint8List encodeMessage(Map<String, dynamic> message) {
  return Uint8List.fromList(utf8.encode(jsonEncode(message)));
}

Map<String, dynamic> decodeMessage(Uint8List bytes) {
  return Map<String, dynamic>.from(
    jsonDecode(utf8.decode(bytes)) as Map,
  );
}
