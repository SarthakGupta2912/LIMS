// Implements the app transport contract over pure Wi-Fi Direct and hides the
// binary GATT-like envelope from session and synchronization code.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'gatt_message.dart';
import 'gatt_router.dart';
import 'nearby_endpoint_metadata.dart';
import 'nearby_transport.dart';
import 'wifi_direct_client.dart';

part 'wifi_direct_transport_events.dart';

class WifiDirectTransport implements NearbyTransport {
  WifiDirectTransport({WifiDirectClient? client})
    : _client = client ?? PluginWifiDirectClient();

  static const serviceId = 'invoice_service';
  static const dataCharacteristicId = 'invoice_data';
  static const syncStatusCharacteristicId = 'sync_status';
  static const ackCharacteristicId = 'ack';

  final WifiDirectClient _client;
  final _adapterStates = StreamController<NearbyAdapterState>.broadcast();
  final _discoveredPeers = StreamController<NearbyDiscoveredPeer>.broadcast();
  final _connectionEvents = StreamController<NearbyConnectionEvent>.broadcast();
  final _channelReadyEvents =
      StreamController<NearbyChannelReadyEvent>.broadcast();
  final _inboundFrames = StreamController<NearbyInboundFrame>.broadcast();
  final _routers = <String, GattRouter>{};
  final _peerNames = <String, String>{};
  final _peerStates = <String, WifiDirectPeerState>{};
  final _outgoingPeers = <String>{};
  final _connected = <String>{};
  StreamSubscription<List<WifiDirectPeer>>? _peerSubscription;
  StreamSubscription<WifiDirectData>? _dataSubscription;
  String? _serviceDiscoveryId;
  String? _desiredPeerName;
  bool _initialized = false;
  bool _discovering = false;
  bool _allowReconnect = false;
  bool _connecting = false;
  bool _disposed = false;

  @override
  Stream<NearbyAdapterState> get adapterStates => _adapterStates.stream;
  @override
  Stream<NearbyDiscoveredPeer> get discoveredPeers => _discoveredPeers.stream;
  @override
  Stream<NearbyConnectionEvent> get connectionEvents =>
      _connectionEvents.stream;
  @override
  Stream<NearbyChannelReadyEvent> get channelReadyEvents =>
      _channelReadyEvents.stream;
  @override
  Stream<NearbyInboundFrame> get inboundFrames => _inboundFrames.stream;

  Stream<Uint8List> subscribe(
    String service,
    String characteristic,
    String peerId,
  ) => _router(peerId).subscribe(service, characteristic);

  Future<void> _initialize(String deviceName) async {
    if (_initialized) return;
    _peerSubscription = _client.peers.listen(_peersChanged);
    _dataSubscription = _client.data.listen(_dataReceived);
    try {
      await _client.initialize(deviceName: deviceName);
      _initialized = true;
    } catch (error) {
      _adapterStates.add(NearbyAdapterState.unauthorized);
      rethrow;
    }
  }

  @override
  Future<void> startAdvertising(NearbyAdvertisementSpec spec) async {
    final metadata = spec.serviceData.values.firstOrNull ?? Uint8List(0);
    await _initialize(spec.name ?? 'LIMS shop');
    await _client.startAdvertising(encodeNearbyEndpointName(metadata));
  }

  @override
  Future<void> startDiscovery(List<String> serviceIds) async {
    if (serviceIds.isEmpty) throw ArgumentError('A service ID is required');
    _serviceDiscoveryId = serviceIds.first;
    await _initialize('LIMS customer');
    _allowReconnect = true;
    _discovering = true;
    await _client.startDiscovery();
  }

  @override
  Future<void> connect(String peerId) async {
    if (_connected.contains(peerId) || _connecting) return;
    _discovering = false;
    final name = _peerNames[peerId];
    if (name == null) throw StateError('Unknown peer $peerId');
    _desiredPeerName = name;
    _allowReconnect = true;
    _outgoingPeers.add(peerId);
    _connecting = true;
    try {
      await _client.connect(peerId, 'LIMS customer');
    } catch (_) {
      _outgoingPeers.remove(peerId);
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    final envelope = GattMessage(
      serviceId: serviceId,
      characteristicId: dataCharacteristicId,
      payload: frame,
      messageId: const Uuid().v4(),
    );
    await _client.send(peerId, base64Url.encode(envelope.encode()));
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    _allowReconnect = false;
    if (!_initialized) return;
    await _client.stopDiscovery();
  }

  @override
  Future<void> stopAdvertising() async {
    if (_initialized) await _client.stopAdvertising();
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    _allowReconnect = false;
    _desiredPeerName = null;
    _outgoingPeers.remove(peerId);
    _connected.remove(peerId);
    await _client.disconnect(peerId);
  }

  @override
  Future<int> maxFrameBytes(String peerId) async => 24 * 1024;
  @override
  Future<List<String>> connectedPeerIds() async => _connected.toList();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _peerSubscription?.cancel();
    await _dataSubscription?.cancel();
    await Future.wait(_routers.values.map((router) => router.dispose()));
    await _client.dispose();
    await Future.wait([
      _adapterStates.close(),
      _discoveredPeers.close(),
      _connectionEvents.close(),
      _channelReadyEvents.close(),
      _inboundFrames.close(),
    ]);
  }
}
