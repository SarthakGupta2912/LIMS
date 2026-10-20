import 'dart:async';
import 'dart:typed_data';

import 'package:lims/core/nearby/nearby_transport.dart';

/// In-memory nearby-device transport for tests.
///
/// Two instances can be paired so frames written by one arrive at the other.
/// Faults (drop, disconnect, MTU) are scriptable per test.
class FakeTransport implements NearbyTransport {
  FakeTransport();

  FakeTransport? peer;
  NearbyAdapterState adapterState = NearbyAdapterState.on;
  int mtu = 23;
  bool failNextSend = false;
  int dropEveryNthFrame = 0;
  int _sentFrames = 0;
  int discoveryStartCount = 0;
  int discoveryStopCount = 0;

  final _adapterStates = StreamController<NearbyAdapterState>.broadcast();
  final _discoveredPeers = StreamController<NearbyDiscoveredPeer>.broadcast();
  final _connectionEvents = StreamController<NearbyConnectionEvent>.broadcast();
  final _notifyReadyEvents =
      StreamController<NearbyChannelReadyEvent>.broadcast();
  final _inboundFrames = StreamController<NearbyInboundFrame>.broadcast();

  final Set<String> _connected = {};
  final Set<String> _notified = {};
  bool _discovering = false;
  bool _advertising = false;
  int listenerCount = 0;

  @override
  Stream<NearbyAdapterState> get adapterStates => _adapterStates.stream;
  @override
  Stream<NearbyDiscoveredPeer> get discoveredPeers => _discoveredPeers.stream;
  @override
  Stream<NearbyConnectionEvent> get connectionEvents =>
      _connectionEvents.stream;
  @override
  Stream<NearbyChannelReadyEvent> get channelReadyEvents =>
      _notifyReadyEvents.stream;
  @override
  Stream<NearbyInboundFrame> get inboundFrames => _inboundFrames.stream;

  void emitAdapterState(NearbyAdapterState state) {
    adapterState = state;
    _adapterStates.add(state);
  }

  void emitDiscovered(NearbyDiscoveredPeer peer) {
    listenerCount++;
    _discoveredPeers.add(peer);
  }

  void emitConnection(
    String peerId,
    NearbyLinkDirection direction,
    bool connected,
  ) {
    if (connected) {
      _connected.add(peerId);
    } else {
      _connected.remove(peerId);
    }
    _connectionEvents.add(
      NearbyConnectionEvent(
        peerId: peerId,
        direction: direction,
        connected: connected,
      ),
    );
  }

  void emitNotifyReady(String peerId, bool ready) {
    if (ready) {
      _notified.add(peerId);
    } else {
      _notified.remove(peerId);
    }
    _notifyReadyEvents.add(
      NearbyChannelReadyEvent(peerId: peerId, ready: ready),
    );
  }

  @override
  Future<void> startDiscovery(List<String> serviceUuids) async {
    discoveryStartCount++;
    _discovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    discoveryStopCount++;
    _discovering = false;
  }

  @override
  Future<void> startAdvertising(NearbyAdvertisementSpec spec) async {
    _advertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
  }

  @override
  Future<void> connect(String peerId) async {
    emitConnection(peerId, NearbyLinkDirection.outgoing, true);
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    emitConnection(peerId, NearbyLinkDirection.outgoing, false);
    emitConnection(peerId, NearbyLinkDirection.incoming, false);
  }

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    if (failNextSend) {
      failNextSend = false;
      throw StateError('injected send failure');
    }
    _sentFrames++;
    if (dropEveryNthFrame > 0 && _sentFrames % dropEveryNthFrame == 0) return;
    final other = peer;
    if (other == null || !_connected.contains(peerId)) {
      throw StateError('Peer disconnected');
    }
    other._inboundFrames.add(NearbyInboundFrame(peerId: peerId, bytes: frame));
  }

  @override
  Future<int> maxFrameBytes(String peerId) async => mtu;

  @override
  Future<List<String>> connectedPeerIds() async => _connected.toList();

  @override
  Future<void> dispose() async {
    await _adapterStates.close();
    await _discoveredPeers.close();
    await _connectionEvents.close();
    await _notifyReadyEvents.close();
    await _inboundFrames.close();
  }

  bool get isDiscovering => _discovering;
  bool get isAdvertising => _advertising;
  int get sentFrameCount => _sentFrames;
}
