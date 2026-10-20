import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/gatt_message.dart';
import 'package:lims/core/nearby/gatt_router.dart';

void main() {
  GattMessage message(String characteristic, List<int> payload) => GattMessage(
    serviceId: 'invoice_service',
    characteristicId: characteristic,
    payload: Uint8List.fromList(payload),
    messageId: 'd9428888-122b-11e1-b85c-61cd3cbb3210',
  );

  test('reassembles fragmented messages', () async {
    final router = GattRouter();
    final payload = router.subscribe('invoice_service', 'invoice_data').first;
    final encoded = message('invoice_data', [1, 2, 3]).encode();

    router.addBytes(encoded.sublist(0, 12));
    router.addBytes(encoded.sublist(12));

    expect(await payload, [1, 2, 3]);
    await router.dispose();
  });

  test('routes concatenated messages only to matching subscribers', () async {
    final router = GattRouter();
    final dataPayloads = <Uint8List>[];
    final ackPayloads = <Uint8List>[];
    final dataSubscription = router
        .subscribe('invoice_service', 'invoice_data')
        .listen(dataPayloads.add);
    final ackSubscription = router
        .subscribe('invoice_service', 'ack')
        .listen(ackPayloads.add);

    router.addBytes([
      ...message('invoice_data', [4]).encode(),
      ...message('ack', [5]).encode(),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(dataPayloads, [
      Uint8List.fromList([4]),
    ]);
    expect(ackPayloads, [
      Uint8List.fromList([5]),
    ]);
    await dataSubscription.cancel();
    await ackSubscription.cancel();
    await router.dispose();
  });

  test('registered handlers receive the full envelope and can unregister', () {
    final router = GattRouter();
    final received = <GattMessage>[];
    final unregister = router.registerHandler(
      'invoice_service',
      'sync_status',
      received.add,
    );

    router.addBytes(message('sync_status', [9]).encode());
    unregister();
    router.addBytes(message('sync_status', [10]).encode());

    expect(received, hasLength(1));
    expect(received.single.payload, [9]);
  });

  test('rejects oversized frames and clears corrupt buffered data', () async {
    final router = GattRouter(maximumFrameBytes: 64);
    final oversized = message('invoice_data', List.filled(64, 1)).encode();

    expect(() => router.addBytes(oversized), throwsFormatException);
    final next = router.subscribe('invoice_service', 'ack').first;
    router.addBytes(message('ack', [1]).encode());
    expect(await next, [1]);
    await router.dispose();
  });
}
