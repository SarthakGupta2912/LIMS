/// Versioned Nearby synchronization envelopes.
///
/// Transport framing, checksums, and chunk retries live in the nearby codec.
/// This protocol validates application identity, entity ownership, versions,
/// and cursors before SQLite applies anything.
class SyncEnvelope {
  const SyncEnvelope({
    required this.protocolVersion,
    required this.sessionId,
    required this.messageId,
    required this.kind,
    required this.entityType,
    required this.entityId,
    required this.entityVersion,
    required this.payload,
    this.cursor,
  });

  final int protocolVersion;
  final String sessionId;
  final String messageId;
  final String kind;
  final String entityType;
  final String entityId;
  final int entityVersion;
  final Map<String, Object?> payload;
  final SyncCursor? cursor;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'sessionId': sessionId,
    'messageId': messageId,
    'kind': kind,
    'entityType': entityType,
    'entityId': entityId,
    'entityVersion': entityVersion,
    'payload': payload,
    if (cursor != null) 'cursor': cursor!.toJson(),
  };

  static SyncEnvelope fromJson(Map<String, Object?> json) {
    final protocolVersion = json['protocolVersion'];
    final sessionId = json['sessionId'];
    final messageId = json['messageId'];
    final kind = json['kind'];
    final entityType = json['entityType'];
    final entityId = json['entityId'];
    final entityVersion = json['entityVersion'];
    final payload = json['payload'];
    if (protocolVersion is! int ||
        sessionId is! String ||
        messageId is! String ||
        kind is! String ||
        entityType is! String ||
        entityId is! String ||
        entityVersion is! int ||
        payload is! Map) {
      throw const FormatException('Invalid sync envelope');
    }
    final cursor = json['cursor'];
    return SyncEnvelope(
      protocolVersion: protocolVersion,
      sessionId: sessionId,
      messageId: messageId,
      kind: kind,
      entityType: entityType,
      entityId: entityId,
      entityVersion: entityVersion,
      payload: Map<String, Object?>.from(payload),
      cursor: cursor == null
          ? null
          : SyncCursor.fromJson(Map<String, Object?>.from(cursor as Map)),
    );
  }
}

bool isSyncEnvelope(Map<String, Object?> json) =>
    json['kind'] is String && json['payload'] is Map;

class SyncCursor {
  const SyncCursor({
    required this.updatedAt,
    required this.version,
    required this.recordId,
  });

  final int updatedAt;
  final int version;
  final String recordId;

  Map<String, Object?> toJson() => {
    'updatedAt': updatedAt,
    'version': version,
    'recordId': recordId,
  };

  static SyncCursor fromJson(Map<String, Object?> json) {
    final updatedAt = json['updatedAt'];
    final version = json['version'];
    final recordId = json['recordId'];
    if (updatedAt is! int || version is! int || recordId is! String) {
      throw const FormatException('Invalid sync cursor');
    }
    return SyncCursor(
      updatedAt: updatedAt,
      version: version,
      recordId: recordId,
    );
  }
}

enum DeltaDecision { apply, duplicate, conflict }

/// Pure conflict rule used before touching SQLite.
DeltaDecision decideDelta({
  required int localVersion,
  required int remoteVersion,
  required String localPayloadHash,
  required String remotePayloadHash,
}) {
  if (remoteVersion < localVersion) return DeltaDecision.duplicate;
  if (remoteVersion == localVersion) {
    return remotePayloadHash == localPayloadHash
        ? DeltaDecision.duplicate
        : DeltaDecision.conflict;
  }
  return DeltaDecision.apply;
}
