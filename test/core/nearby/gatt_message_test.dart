import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/gatt_message.dart';

void main() {
  const messageId = 'd9428888-122b-11e1-b85c-61cd3cbb3210';

  test('round trips binary payload and identifiers', () {
    final original = GattMessage(
      serviceId: 'invoice_service',
      characteristicId: 'invoice_data',
      payload: Uint8List.fromList([0, 1, 2, 127, 128, 255]),
      messageId: messageId,
    );

    final decoded = GattMessage.decode(original.encode());

    expect(decoded.serviceId, original.serviceId);
    expect(decoded.characteristicId, original.characteristicId);
    expect(decoded.payload, original.payload);
    expect(decoded.messageId, messageId);
  });

  test('rejects truncated and trailing data', () {
    final encoded = GattMessage(
      serviceId: 'invoice_service',
      characteristicId: 'ack',
      payload: Uint8List(0),
      messageId: messageId,
    ).encode();

    expect(
      () => GattMessage.decode(Uint8List.fromList(encoded.sublist(0, 20))),
      throwsFormatException,
    );
    expect(
      () => GattMessage.decode(Uint8List.fromList([...encoded, 0])),
      throwsFormatException,
    );
  });

  test('rejects invalid UUIDs and corrupt field lengths', () {
    expect(
      () => GattMessage(
        serviceId: 'invoice_service',
        characteristicId: 'ack',
        payload: Uint8List(0),
        messageId: 'not-a-uuid',
      ),
      throwsFormatException,
    );

    final encoded = GattMessage(
      serviceId: 'invoice_service',
      characteristicId: 'ack',
      payload: Uint8List(0),
      messageId: messageId,
    ).encode();
    ByteData.sublistView(encoded).setUint32(13, 10, Endian.big);
    expect(() => GattMessage.decode(encoded), throwsFormatException);
  });
}
