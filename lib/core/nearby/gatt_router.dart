// Reassembles GATT-like messages from raw byte chunks and dispatches them by
// service and characteristic, including BLE-style payload subscriptions.

import 'dart:async';
import 'dart:typed_data';

import 'gatt_message.dart';

typedef GattMessageHandler = void Function(GattMessage message);
typedef CancelGattHandler = void Function();

class GattRouter {
  GattRouter({Stream<List<int>>? incoming, this.maximumFrameBytes = 16 << 20}) {
    _incomingSubscription = incoming?.listen(addBytes);
  }

  final int maximumFrameBytes;
  final List<int> _buffer = [];
  final Map<(String, String), Set<GattMessageHandler>> _handlers = {};
  final Map<(String, String), StreamController<Uint8List>> _payloads = {};
  StreamSubscription<List<int>>? _incomingSubscription;
  bool _disposed = false;

  Stream<Uint8List> subscribe(String serviceId, String characteristicId) {
    _checkActive();
    final key = (serviceId, characteristicId);
    return _payloads
        .putIfAbsent(key, () => StreamController<Uint8List>.broadcast())
        .stream;
  }

  CancelGattHandler registerHandler(
    String serviceId,
    String characteristicId,
    GattMessageHandler handler,
  ) {
    _checkActive();
    final key = (serviceId, characteristicId);
    _handlers.putIfAbsent(key, () => {}).add(handler);
    return () {
      final handlers = _handlers[key];
      handlers?.remove(handler);
      if (handlers?.isEmpty ?? false) _handlers.remove(key);
    };
  }

  void addBytes(List<int> bytes) {
    _checkActive();
    if (bytes.isEmpty) return;
    _buffer.addAll(bytes);
    var consumed = 0;
    try {
      while (_buffer.length - consumed >= GattMessage.headerLength) {
        final available = Uint8List.fromList(_buffer.sublist(consumed));
        final frameLength = GattMessage.frameLength(available);
        if (frameLength > maximumFrameBytes) {
          throw FormatException(
            'GATT message exceeds $maximumFrameBytes bytes',
          );
        }
        if (available.length < frameLength) break;
        final message = GattMessage.decode(
          Uint8List.sublistView(available, 0, frameLength),
        );
        consumed += frameLength;
        _dispatch(message);
      }
      if (_buffer.length > maximumFrameBytes) {
        throw FormatException(
          'Buffered GATT data exceeds $maximumFrameBytes bytes',
        );
      }
    } on FormatException {
      _buffer.clear();
      rethrow;
    } finally {
      if (consumed > 0 && consumed <= _buffer.length) {
        _buffer.removeRange(0, consumed);
      }
    }
  }

  void _dispatch(GattMessage message) {
    final key = (message.serviceId, message.characteristicId);
    for (final handler in _handlers[key]?.toList() ?? const []) {
      handler(message);
    }
    _payloads[key]?.add(Uint8List.fromList(message.payload));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _incomingSubscription?.cancel();
    await Future.wait(_payloads.values.map((controller) => controller.close()));
    _payloads.clear();
    _handlers.clear();
    _buffer.clear();
  }

  void _checkActive() {
    if (_disposed) throw StateError('GattRouter has been disposed');
  }
}
