import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/sync_protocol.dart';

void main() {
  SyncEnvelope envelope() => const SyncEnvelope(
    protocolVersion: 2,
    sessionId: 'session',
    messageId: 'message',
    kind: 'delta',
    entityType: 'order_status',
    entityId: 'order-1',
    entityVersion: 3,
    payload: {'status': 'preparing'},
    cursor: SyncCursor(updatedAt: 10, version: 3, recordId: 'order-1'),
  );

  test('round-trips valid envelopes and cursors', () {
    final decoded = SyncEnvelope.fromJson(envelope().toJson());
    expect(decoded.sessionId, 'session');
    expect(decoded.cursor!.version, 3);
  });

  test('rejects malformed envelopes and unsupported shapes', () {
    expect(() => SyncEnvelope.fromJson({}), throwsFormatException);
    expect(
      () =>
          SyncEnvelope.fromJson({...envelope().toJson(), 'entityVersion': '3'}),
      throwsFormatException,
    );
  });

  test('does not classify a versioned handshake as a sync envelope', () {
    expect(
      isSyncEnvelope({
        'type': 'hello',
        'protocolVersion': 2,
        'profileId': 'customer-1',
      }),
      isFalse,
    );
    expect(isSyncEnvelope(envelope().toJson()), isTrue);
  });

  test('orders versions and detects divergent payloads', () {
    expect(
      decideDelta(
        localVersion: 3,
        remoteVersion: 2,
        localPayloadHash: 'a',
        remotePayloadHash: 'a',
      ),
      DeltaDecision.duplicate,
    );
    expect(
      decideDelta(
        localVersion: 3,
        remoteVersion: 3,
        localPayloadHash: 'a',
        remotePayloadHash: 'a',
      ),
      DeltaDecision.duplicate,
    );
    expect(
      decideDelta(
        localVersion: 3,
        remoteVersion: 3,
        localPayloadHash: 'a',
        remotePayloadHash: 'b',
      ),
      DeltaDecision.conflict,
    );
    expect(
      decideDelta(
        localVersion: 3,
        remoteVersion: 4,
        localPayloadHash: 'a',
        remotePayloadHash: 'b',
      ),
      DeltaDecision.apply,
    );
  });
}
