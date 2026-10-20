// Isolates the third-party nearby plugin behind small app-owned types so the
// Wi-Fi Direct transport can be tested without platform channels.

import 'dart:async';

import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';

enum WifiDirectPeerState { disconnected, connecting, connected }

class WifiDirectPeer {
  const WifiDirectPeer({
    required this.id,
    required this.name,
    required this.state,
  });

  final String id;
  final String name;
  final WifiDirectPeerState state;
}

class WifiDirectData {
  const WifiDirectData(this.peerId, this.message);

  final String peerId;
  final String message;
}

abstract class WifiDirectClient {
  Stream<List<WifiDirectPeer>> get peers;
  Stream<WifiDirectData> get data;

  Future<void> initialize({required String deviceName});
  Future<void> startAdvertising(String deviceName);
  Future<void> stopAdvertising();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> connect(String peerId, String deviceName);
  Future<void> disconnect(String peerId);
  Future<void> send(String peerId, String message);
  Future<void> dispose();
}

class PluginWifiDirectClient implements WifiDirectClient {
  final NearbyService _service = NearbyService();
  final _peers = StreamController<List<WifiDirectPeer>>.broadcast();
  final _data = StreamController<WifiDirectData>.broadcast();
  StreamSubscription<dynamic>? _peerSubscription;
  StreamSubscription<dynamic>? _dataSubscription;
  bool _initialized = false;

  @override
  Stream<List<WifiDirectPeer>> get peers => _peers.stream;
  @override
  Stream<WifiDirectData> get data => _data.stream;

  @override
  Future<void> initialize({required String deviceName}) async {
    if (_initialized) return;
    final ready = Completer<void>();
    await _service.init(
      serviceType: 'lims-invoice',
      deviceName: deviceName,
      strategy: Strategy.Wi_Fi_P2P,
      callback: (bool running) {
        if (running && !ready.isCompleted) ready.complete();
      },
    );
    _peerSubscription = _service.stateChangedSubscription(
      callback: (devices) => _peers.add([
        for (final device in devices)
          WifiDirectPeer(
            id: device.deviceId,
            name: device.deviceName,
            state: switch (device.state) {
              SessionState.connected => WifiDirectPeerState.connected,
              SessionState.connecting => WifiDirectPeerState.connecting,
              SessionState.notConnected => WifiDirectPeerState.disconnected,
            },
          ),
      ]),
    );
    _dataSubscription = _service.dataReceivedSubscription(
      callback: (value) {
        if (value is! Map) return;
        final peerId = value['deviceId'];
        final message = value['message'];
        if (peerId is String && message is String) {
          _data.add(WifiDirectData(peerId, message));
        }
      },
    );
    await ready.future.timeout(const Duration(seconds: 15));
    _initialized = true;
  }

  @override
  Future<void> startAdvertising(String deviceName) async {
    await _service.startAdvertisingPeer(deviceName: deviceName);
  }

  @override
  Future<void> stopAdvertising() async {
    await _service.stopAdvertisingPeer();
  }

  @override
  Future<void> startDiscovery() async {
    await _service.startBrowsingForPeers();
  }

  @override
  Future<void> stopDiscovery() async {
    await _service.stopBrowsingForPeers();
  }

  @override
  Future<void> connect(String peerId, String deviceName) async {
    await _service.invitePeer(deviceID: peerId, deviceName: deviceName);
  }

  @override
  Future<void> disconnect(String peerId) async {
    await _service.disconnectPeer(deviceID: peerId);
  }

  @override
  Future<void> send(String peerId, String message) async {
    await _service.sendMessage(peerId, message);
  }

  @override
  Future<void> dispose() async {
    await _peerSubscription?.cancel();
    await _dataSubscription?.cancel();
    if (_initialized) await _service.dispose();
    await _peers.close();
    await _data.close();
  }
}
