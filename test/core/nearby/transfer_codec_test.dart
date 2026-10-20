import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/transfer_codec.dart';

void main() {
  const codec = BleTransferCodec();
  final now = DateTime.utc(2026, 1, 1);

  Uint8List payload(int length) =>
      Uint8List.fromList(List.generate(length, (index) => index % 251));

  test('round-trips single and multi-chunk payloads', () {
    for (final length in [1, 19, 20, 500, 5000]) {
      final data = payload(length);
      final frames = codec.encode(
        transferId: 7,
        payload: data,
        maxChunkPayloadBytes: 20,
      );
      final reassembler = TransferReassembler();
      ReassembledTransfer? result;
      for (final frame in frames) {
        result = reassembler.addFrame('peer', frame, now);
      }
      expect(result, isNotNull);
      expect(result!.payload, data);
    }
  });

  test('accepts duplicate and out-of-order chunks', () {
    final data = payload(100);
    final frames = codec.encode(
      transferId: 9,
      payload: data,
      maxChunkPayloadBytes: 20,
    );
    final reassembler = TransferReassembler();
    expect(reassembler.addFrame('peer', frames.last, now), isNull);
    expect(reassembler.addFrame('peer', frames.last, now), isNull);
    ReassembledTransfer? result;
    for (final frame in frames) {
      result = reassembler.addFrame('peer', frame, now) ?? result;
    }
    expect(result!.payload, data);
  });

  test('rejects checksum failures and malformed frames', () {
    final data = payload(64);
    final frames = codec.encode(
      transferId: 11,
      payload: data,
      maxChunkPayloadBytes: 20,
    );
    final corrupted = Uint8List.fromList(frames.first);
    corrupted[corrupted.length - 1] ^= 0xff;
    final reassembler = TransferReassembler();
    for (final frame in [...frames.skip(1), corrupted]) {
      expect(reassembler.addFrame('peer', frame, now), isNull);
    }
    expect(reassembler.pendingTransfers, 0);
    expect(
      reassembler.addFrame('peer', Uint8List.fromList([0, 1, 2]), now),
      isNull,
    );
  });

  test('expires incomplete transfers and bounds buffers', () {
    final data = payload(100);
    final frames = codec.encode(
      transferId: 13,
      payload: data,
      maxChunkPayloadBytes: 20,
    );
    final reassembler = TransferReassembler(
      incompleteTimeout: const Duration(seconds: 5),
      maxConcurrentTransfers: 1,
    );
    reassembler.addFrame('peer', frames.first, now);
    expect(reassembler.pendingTransfers, 1);
    reassembler.prune(now.add(const Duration(seconds: 6)));
    expect(reassembler.pendingTransfers, 0);

    final full = TransferReassembler(maxConcurrentTransfers: 1);
    full.addFrame('a', frames.first, now);
    full.addFrame('b', frames.first, now);
    expect(full.pendingTransfers, 1);
  });

  test('deduplicates completed transfers and rejects oversize payloads', () {
    final data = payload(32);
    final frames = codec.encode(
      transferId: 17,
      payload: data,
      maxChunkPayloadBytes: 32,
    );
    final reassembler = TransferReassembler();
    expect(reassembler.addFrame('peer', frames.single, now), isNotNull);
    expect(reassembler.addFrame('peer', frames.single, now), isNull);
    expect(
      () => codec.encode(
        transferId: 18,
        payload: Uint8List(200000),
        maxChunkPayloadBytes: 20,
      ),
      throwsArgumentError,
    );
  });
}
