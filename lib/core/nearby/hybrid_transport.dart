import 'dart:async';
import 'dart:typed_data';

import 'lan_transport.dart';
import 'nearby_transport.dart';
import 'wifi_direct_transport.dart';
import 'custom_mesh_transport.dart';

/// Runs LAN and Wi-Fi Direct together. LAN is preferred for many customers;
/// Wi-Fi Direct remains available when no local network is present.
class HybridTransport implements NearbyTransport {
  HybridTransport({
    NearbyTransport? lan,
    NearbyTransport? wifiDirect,
    NearbyTransport? mesh,
  }) : _lan = lan ?? LanTransport(),
       _wifiDirect = wifiDirect ?? WifiDirectTransport(),
       _mesh = mesh ?? CustomMeshTransport();

  final NearbyTransport _lan;
  final NearbyTransport _wifiDirect;
  final NearbyTransport _mesh;
  final _adapter = StreamController<NearbyAdapterState>.broadcast();
  final _discovered = StreamController<NearbyDiscoveredPeer>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _ready = StreamController<NearbyChannelReadyEvent>.broadcast();
  final _inbound = StreamController<NearbyInboundFrame>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _started = false;

  @override
  Stream<NearbyAdapterState> get adapterStates => _adapter.stream;
  @override
  Stream<NearbyDiscoveredPeer> get discoveredPeers => _discovered.stream;
  @override
  Stream<NearbyConnectionEvent> get connectionEvents => _connections.stream;
  @override
  Stream<NearbyChannelReadyEvent> get channelReadyEvents => _ready.stream;
  @override
  Stream<NearbyInboundFrame> get inboundFrames => _inbound.stream;

  void _listen() {
    if (_started) return;
    _started = true;
    _subscriptions.addAll([
      _lan.adapterStates.listen(_adapter.add),
      _wifiDirect.adapterStates.listen(_adapter.add),
      _mesh.adapterStates.listen(_adapter.add),
      _lan.discoveredPeers.listen(_discovered.add),
      _wifiDirect.discoveredPeers.listen(_discovered.add),
      _mesh.discoveredPeers.listen(_discovered.add),
      _lan.connectionEvents.listen(_connections.add),
      _wifiDirect.connectionEvents.listen(_connections.add),
      _mesh.connectionEvents.listen(_connections.add),
      _lan.channelReadyEvents.listen(_ready.add),
      _wifiDirect.channelReadyEvents.listen(_ready.add),
      _mesh.channelReadyEvents.listen(_ready.add),
      _lan.inboundFrames.listen(_inbound.add),
      _wifiDirect.inboundFrames.listen(_inbound.add),
      _mesh.inboundFrames.listen(_inbound.add),
    ]);
  }

  @override
  Future<void> startDiscovery(List<String> serviceIds) async {
    _listen();
    final results = await Future.wait([
      _attempt(() => _lan.startDiscovery(serviceIds)),
      _attempt(() => _wifiDirect.startDiscovery(serviceIds)),
      _attempt(() => _mesh.startDiscovery(serviceIds)),
    ]);
    if (!results.any((success) => success)) {
      throw StateError('No nearby transport is available');
    }
  }

  @override
  Future<void> stopDiscovery() async {
    await Future.wait([
      _ignoreFailure(_lan.stopDiscovery()),
      _ignoreFailure(_wifiDirect.stopDiscovery()),
      _ignoreFailure(_mesh.stopDiscovery()),
    ]);
  }

  @override
  Future<void> startAdvertising(NearbyAdvertisementSpec spec) async {
    _listen();
    final results = await Future.wait([
      _attempt(() => _lan.startAdvertising(spec)),
      _attempt(() => _wifiDirect.startAdvertising(spec)),
      _attempt(() => _mesh.startAdvertising(spec)),
    ]);
    if (!results.any((success) => success)) {
      throw StateError('No nearby transport is available');
    }
  }

  @override
  Future<void> stopAdvertising() async {
    await Future.wait([
      _ignoreFailure(_lan.stopAdvertising()),
      _ignoreFailure(_wifiDirect.stopAdvertising()),
      _ignoreFailure(_mesh.stopAdvertising()),
    ]);
  }

  @override
  Future<void> connect(String peerId) => _transportFor(peerId).connect(peerId);

  @override
  Future<void> disconnectPeer(String peerId) =>
      _transportFor(peerId).disconnectPeer(peerId);

  @override
  Future<void> send(String peerId, Uint8List frame) =>
      _transportFor(peerId).send(peerId, frame);

  @override
  Future<int> maxFrameBytes(String peerId) =>
      _transportFor(peerId).maxFrameBytes(peerId);

  @override
  Future<List<String>> connectedPeerIds() async => [
    ...await _lan.connectedPeerIds(),
    ...await _wifiDirect.connectedPeerIds(),
    ...await _mesh.connectedPeerIds(),
  ];

  NearbyTransport _transportFor(String peerId) => peerId.startsWith('lan:')
      ? _lan
      : peerId.startsWith('mesh:')
      ? _mesh
      : _wifiDirect;

  Future<bool> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ignoreFailure(Future<void> action) async {
    try {
      await action;
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _lan.dispose(),
      _wifiDirect.dispose(),
      _mesh.dispose(),
      ..._subscriptions.map((subscription) => subscription.cancel()),
    ]);
    await Future.wait([
      _adapter.close(),
      _discovered.close(),
      _connections.close(),
      _ready.close(),
      _inbound.close(),
    ]);
  }
}
