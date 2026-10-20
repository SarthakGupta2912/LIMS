import 'dart:typed_data';

/// Pure nearby application-frame codec.
///
/// The codec only encodes, validates, and reassembles complete payloads. It
/// never performs transport I/O, so timeouts, retries, and buffers can be tested
/// deterministically.
class BleTransferCodec {
  const BleTransferCodec({
    this.magic = 0x4d,
    this.protocolVersion = 2,
    this.headerLength = 16,
    this.maxChunksPerTransfer = 256,
    this.maxPayloadBytes = 131072,
    this.completedTransferMemory = 512,
  });

  final int magic;
  final int protocolVersion;
  final int headerLength;
  final int maxChunksPerTransfer;
  final int maxPayloadBytes;
  final int completedTransferMemory;

  List<Uint8List> encode({
    required int transferId,
    required Uint8List payload,
    required int maxChunkPayloadBytes,
  }) {
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError('Payload exceeds nearby transfer limit');
    }
    final chunkPayload = maxChunkPayloadBytes.clamp(1, 505);
    final count = (payload.length / chunkPayload).ceil().clamp(
      1,
      maxChunksPerTransfer,
    );
    if (payload.length > chunkPayload * maxChunksPerTransfer) {
      throw ArgumentError('Payload exceeds nearby transfer limit');
    }
    final checksum = _crc32(payload);
    final frames = <Uint8List>[];
    for (var index = 0; index < count; index++) {
      final start = index * chunkPayload;
      final end = (start + chunkPayload).clamp(0, payload.length);
      final frame = Uint8List(headerLength + end - start);
      final header = ByteData.sublistView(frame, 0, headerLength);
      frame[0] = magic;
      frame[1] = protocolVersion;
      header.setUint16(2, transferId & 0xffff, Endian.big);
      header.setUint16(4, index, Endian.big);
      header.setUint16(6, count, Endian.big);
      header.setUint32(8, payload.length, Endian.big);
      header.setUint32(12, checksum, Endian.big);
      frame.setRange(headerLength, frame.length, payload, start);
      frames.add(frame);
    }
    return frames;
  }
}

class ReassembledTransfer {
  ReassembledTransfer(this.payload);

  final Uint8List payload;
}

class TransferReassembler {
  TransferReassembler({
    this._codec = const BleTransferCodec(),
    this.incompleteTimeout = const Duration(seconds: 20),
    this.maxConcurrentTransfers = 8,
  });

  final BleTransferCodec _codec;
  final Duration incompleteTimeout;
  final int maxConcurrentTransfers;
  final Map<String, _PartialTransfer> _partials = {};
  final Map<String, DateTime> _completedAt = {};

  ReassembledTransfer? addFrame(String peerId, Uint8List frame, DateTime now) {
    if (frame.length < _codec.headerLength || frame[0] != _codec.magic) {
      return null;
    }
    if (frame[1] != _codec.protocolVersion) return null;
    final header = ByteData.sublistView(frame, 0, _codec.headerLength);
    final transferId = header.getUint16(2, Endian.big);
    final index = header.getUint16(4, Endian.big);
    final count = header.getUint16(6, Endian.big);
    final totalLength = header.getUint32(8, Endian.big);
    final checksum = header.getUint32(12, Endian.big);
    if (count == 0 ||
        count > _codec.maxChunksPerTransfer ||
        index >= count ||
        totalLength > _codec.maxPayloadBytes) {
      return null;
    }
    final key = '$peerId:$transferId';
    if (_completedAt.containsKey(key)) return null;
    var partial = _partials[key];
    if (partial == null) {
      if (_partials.length >= maxConcurrentTransfers) return null;
      partial = _PartialTransfer(count, totalLength, checksum, now);
      _partials[key] = partial;
    } else if (partial.count != count ||
        partial.totalLength != totalLength ||
        partial.checksum != checksum) {
      _partials.remove(key);
      return null;
    }
    partial.chunks[index] = frame.sublist(_codec.headerLength);
    if (partial.chunks.length != count) return null;
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      final chunk = partial.chunks[i];
      if (chunk == null) return null;
      builder.add(chunk);
    }
    final payload = builder.takeBytes();
    if (payload.length != totalLength || _crc32(payload) != checksum) {
      _partials.remove(key);
      return null;
    }
    _partials.remove(key);
    _completedAt[key] = now;
    while (_completedAt.length > _codec.completedTransferMemory) {
      _completedAt.remove(_completedAt.keys.first);
    }
    return ReassembledTransfer(payload);
  }

  void prune(DateTime now) {
    _partials.removeWhere(
      (_, partial) => now.difference(partial.firstSeen) > incompleteTimeout,
    );
    _completedAt.removeWhere(
      (_, completedAt) => now.difference(completedAt) > incompleteTimeout,
    );
  }

  int get pendingTransfers => _partials.length;
}

class _PartialTransfer {
  _PartialTransfer(this.count, this.totalLength, this.checksum, this.firstSeen);

  final int count;
  final int totalLength;
  final int checksum;
  final DateTime firstSeen;
  final Map<int, Uint8List> chunks = {};
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
