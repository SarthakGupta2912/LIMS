import 'dart:async';
import 'package:flutter/services.dart';

import 'nearby_transport.dart';

/// LIMS transport over Meshrabiya's virtual UDP and chained TCP sockets.
class CustomMeshTransport implements NearbyTransport {
  CustomMeshTransport();

  static const _channel = MethodChannel('lims/custom_mesh/transport');
  static const _events = EventChannel('lims/custom_mesh/transport_events');
  static const _serviceId = 'ffb0';

  final _adapter = StreamController<NearbyAdapterState>.broadcast();
  final _discovered = StreamController<NearbyDiscoveredPeer>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _ready = StreamController<NearbyChannelReadyEvent>.broadcast();
  final _inbound = StreamController<NearbyInboundFrame>.broadcast();
  final _addresses = <String, ({String address, int port})>{};
  final _connected = <String>{};
  final _directions = <String, NearbyLinkDirection>{};
  StreamSubscription<Object?>? _eventsSubscription;
  bool _started = false;
  bool _advertising = false;
  Timer? _discoveryTimer;

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
    _eventsSubscription = _events.receiveBroadcastStream().listen(_onEvent);
    _adapter.add(NearbyAdapterState.on);
  }

  @override
  Future<void> startAdvertising(NearbyAdvertisementSpec spec) async {
    _listen();
    _advertising = true;
    final data = spec.serviceData.values.firstOrNull ?? Uint8List(0);
    await _channel.invokeMethod<void>('start', {'advertisement': data});
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
    await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> startDiscovery(List<String> serviceIds) async {
    if (serviceIds.isEmpty) throw ArgumentError('A service ID is required');
    _listen();
    await _channel.invokeMethod<void>('start');
    await _channel.invokeMethod<void>('discover');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(
        _channel.invokeMethod<void>('discover').catchError((Object _) {}),
      );
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    if (!_advertising) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> connect(String peerId) async {
    final target = _addresses[peerId];
    if (target == null) throw StateError('Unknown mesh peer $peerId');
    await _channel.invokeMethod<void>('connect', {
      'address': target.address,
      'port': target.port,
      'peerId': peerId,
    });
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    await _channel.invokeMethod<void>('disconnect', {'peerId': peerId});
  }

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    await _channel.invokeMethod<void>('send', {
      'peerId': peerId,
      'bytes': frame,
    });
  }

  @override
  Future<int> maxFrameBytes(String peerId) async => 1024 * 1024;

  @override
  Future<List<String>> connectedPeerIds() async => _connected.toList();

  void _onEvent(Object? value) {
    if (value is! Map) return;
    final event = Map<Object?, Object?>.from(value);
    final type = event['type'];
    final peerId = event['peerId'] as String?;
    if (type == 'discovered') {
      final id = peerId;
      final address = event['address'] as String?;
      final port = event['port'];
      final raw = event['advertisement'];
      if (id == null || address == null || port is! int || raw is! Uint8List) {
        return;
      }
      _addresses[id] = (address: address, port: port);
      _discovered.add(
        NearbyDiscoveredPeer(
          peerId: id,
          name: event['name'] as String?,
          serviceData: {_serviceId: raw},
          rssi: 0,
        ),
      );
    } else if (type == 'connected' && peerId != null) {
      final direction = event['direction'] == 'incoming'
          ? NearbyLinkDirection.incoming
          : NearbyLinkDirection.outgoing;
      _connections.add(
        NearbyConnectionEvent(
          peerId: peerId,
          direction: direction,
          connected: true,
        ),
      );
      _connected.add(peerId);
      _directions[peerId] = direction;
      _ready.add(NearbyChannelReadyEvent(peerId: peerId, ready: true));
    } else if (type == 'disconnected' && peerId != null) {
      _ready.add(NearbyChannelReadyEvent(peerId: peerId, ready: false));
      _connections.add(
        NearbyConnectionEvent(
          peerId: peerId,
          direction: _directions.remove(peerId) ?? NearbyLinkDirection.outgoing,
          connected: false,
        ),
      );
      _connected.remove(peerId);
    } else if (type == 'frame' && peerId != null) {
      final bytes = event['bytes'];
      if (bytes is Uint8List) {
        _inbound.add(NearbyInboundFrame(peerId: peerId, bytes: bytes));
      }
    }
  }

  @override
  Future<void> dispose() async {
    _discoveryTimer?.cancel();
    await _eventsSubscription?.cancel();
    await _channel.invokeMethod<void>('stop');
    await Future.wait([
      _adapter.close(),
      _discovered.close(),
      _connections.close(),
      _ready.close(),
      _inbound.close(),
    ]);
  }
}
