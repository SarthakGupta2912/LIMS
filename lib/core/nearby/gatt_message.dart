// Defines the compact service/characteristic envelope exchanged over the
// Wi-Fi Direct byte stream. It contains no transport or routing behavior.

import 'dart:convert';
import 'dart:typed_data';

class GattMessage {
  GattMessage({
    required this.serviceId,
    required this.characteristicId,
    required this.payload,
    required String messageId,
  }) : messageId = _canonicalUuid(messageId) {
    if (serviceId.isEmpty || characteristicId.isEmpty) {
      throw ArgumentError('Service and characteristic IDs must not be empty');
    }
  }

  static const int headerLength = 33;
  static const int _magic = 0x47415454; // GATT
  static const int _version = 1;

  final String serviceId;
  final String characteristicId;
  final Uint8List payload;
  final String messageId;

  Uint8List encode() {
    final service = utf8.encode(serviceId);
    final characteristic = utf8.encode(characteristicId);
    if (service.length > 0xffff || characteristic.length > 0xffff) {
      throw ArgumentError('Service or characteristic ID is too long');
    }
    final totalLength =
        headerLength + service.length + characteristic.length + payload.length;
    final output = Uint8List(totalLength);
    final data = ByteData.sublistView(output);
    data
      ..setUint32(0, _magic, Endian.big)
      ..setUint8(4, _version)
      ..setUint32(5, totalLength, Endian.big)
      ..setUint16(9, service.length, Endian.big)
      ..setUint16(11, characteristic.length, Endian.big)
      ..setUint32(13, payload.length, Endian.big);
    output.setRange(17, 33, _uuidBytes(messageId));
    var offset = headerLength;
    output.setRange(offset, offset += service.length, service);
    output.setRange(offset, offset += characteristic.length, characteristic);
    output.setRange(offset, totalLength, payload);
    return output;
  }

  static GattMessage decode(Uint8List bytes) {
    final declaredLength = frameLength(bytes);
    if (bytes.length != declaredLength) {
      throw const FormatException('GATT message length does not match header');
    }
    final data = ByteData.sublistView(bytes);
    final serviceLength = data.getUint16(9, Endian.big);
    final characteristicLength = data.getUint16(11, Endian.big);
    final payloadLength = data.getUint32(13, Endian.big);
    if (headerLength + serviceLength + characteristicLength + payloadLength !=
        declaredLength) {
      throw const FormatException('Invalid GATT field lengths');
    }
    var offset = headerLength;
    final service = _decodeId(bytes, offset, offset += serviceLength);
    final characteristic = _decodeId(
      bytes,
      offset,
      offset += characteristicLength,
    );
    if (service.isEmpty || characteristic.isEmpty) {
      throw const FormatException('GATT IDs must not be empty');
    }
    return GattMessage(
      serviceId: service,
      characteristicId: characteristic,
      messageId: _uuidString(bytes.sublist(17, 33)),
      payload: Uint8List.fromList(bytes.sublist(offset)),
    );
  }

  static int frameLength(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw const FormatException('Incomplete GATT message header');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.big) != _magic) {
      throw const FormatException('Invalid GATT message magic');
    }
    if (data.getUint8(4) != _version) {
      throw const FormatException('Unsupported GATT message version');
    }
    final length = data.getUint32(5, Endian.big);
    if (length < headerLength) {
      throw const FormatException('Invalid GATT message length');
    }
    return length;
  }

  static String _decodeId(Uint8List bytes, int start, int end) {
    try {
      return utf8.decode(bytes.sublist(start, end));
    } on FormatException {
      throw const FormatException('GATT ID is not valid UTF-8');
    }
  }

  static String _canonicalUuid(String value) => _uuidString(_uuidBytes(value));

  static Uint8List _uuidBytes(String value) {
    final hex = value.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
      throw FormatException('Invalid message UUID: $value');
    }
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static String _uuidString(List<int> bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
