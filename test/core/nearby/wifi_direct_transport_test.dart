import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/gatt_message.dart';
import 'package:lims/core/nearby/nearby_endpoint_metadata.dart';
import 'package:lims/core/nearby/nearby_transport.dart';
import 'package:lims/core/nearby/wifi_direct_client.dart';
import 'package:lims/core/nearby/wifi_direct_transport.dart';

void main() {
  test('discovers metadata and reports an outgoing connection', () async {
    final client = _FakeWifiDirectClient();
    final transport = WifiDirectTransport(client: client);
    final discovered = transport.discoveredPeers.first;
    final connection = transport.connectionEvents.first;

    await transport.startDiscovery(['ffb0']);
    client.emitPeers([
      WifiDirectPeer(
        id: 'shop',
        name: encodeNearbyEndpointName(Uint8List.fromList([1, 2, 3])),
        state: WifiDirectPeerState.disconnected,
      ),
    ]);
    expect((await discovered).serviceData['ffb0'], [1, 2, 3]);

    await transport.connect('shop');
    client.emitPeers(const [
      WifiDirectPeer(
        id: 'shop',
        name: 'shop',
        state: WifiDirectPeerState.connected,
      ),
    ]);
    final event = await connection;
    expect(event.direction, NearbyLinkDirection.outgoing);
    expect(event.connected, isTrue);
    await transport.dispose();
  });

  test('wraps outgoing frames and unwraps incoming frames', () async {
    final client = _FakeWifiDirectClient();
    final transport = WifiDirectTransport(client: client);
    await transport.startDiscovery(['ffb0']);

    await transport.send('peer', Uint8List.fromList([7, 8, 9]));
    final envelope = GattMessage.decode(
      base64Url.decode(base64Url.normalize(client.sent.single.$2)),
    );
    expect(envelope.serviceId, WifiDirectTransport.serviceId);
    expect(envelope.characteristicId, WifiDirectTransport.dataCharacteristicId);
    expect(envelope.payload, [7, 8, 9]);

    final incoming = transport.inboundFrames.first;
    client.emitData('peer', client.sent.single.$2);
    expect((await incoming).bytes, [7, 8, 9]);
    await transport.dispose();
  });

  test('reports an outgoing disconnect after a connected session', () {
    fakeAsync((async) {
      final client = _FakeWifiDirectClient();
      final transport = WifiDirectTransport(client: client);
      final events = <NearbyConnectionEvent>[];
      transport.connectionEvents.listen(events.add);
      transport.startDiscovery(['ffb0']);
      async.flushMicrotasks();
      final name = encodeNearbyEndpointName(Uint8List.fromList([1]));
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.disconnected,
        ),
      ]);
      async.flushMicrotasks();
      transport.connect('shop');
      async.flushMicrotasks();
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.connected,
        ),
      ]);
      async.flushMicrotasks();
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.disconnected,
        ),
      ]);
      async.flushMicrotasks();
      expect(events.map((event) => event.connected), [true, false]);
      expect(events.last.direction, NearbyLinkDirection.outgoing);
      transport.dispose();
      async.flushMicrotasks();
    });
  });

  test('reports an outgoing connection attempt failure', () {
    fakeAsync((async) {
      final client = _FakeWifiDirectClient();
      final transport = WifiDirectTransport(client: client);
      final events = <NearbyConnectionEvent>[];
      transport.connectionEvents.listen(events.add);
      transport.startDiscovery(['ffb0']);
      async.flushMicrotasks();
      final name = encodeNearbyEndpointName(Uint8List.fromList([1]));
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.disconnected,
        ),
      ]);
      async.flushMicrotasks();
      transport.connect('shop');
      async.flushMicrotasks();
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.connecting,
        ),
      ]);
      async.flushMicrotasks();
      client.emitPeers([
        WifiDirectPeer(
          id: 'shop',
          name: name,
          state: WifiDirectPeerState.disconnected,
        ),
      ]);
      async.flushMicrotasks();
      expect(events, hasLength(1));
      expect(events.single.connected, isFalse);
      expect(events.single.direction, NearbyLinkDirection.outgoing);
      transport.dispose();
      async.flushMicrotasks();
    });
  });
}

class _FakeWifiDirectClient implements WifiDirectClient {
  final peerController = StreamController<List<WifiDirectPeer>>.broadcast();
  final dataController = StreamController<WifiDirectData>.broadcast();
  final sent = <(String, String)>[];
  int discoveryStarts = 0;

  @override
  Stream<List<WifiDirectPeer>> get peers => peerController.stream;
  @override
  Stream<WifiDirectData> get data => dataController.stream;

  void emitPeers(List<WifiDirectPeer> peers) => peerController.add(peers);
  void emitData(String peerId, String message) =>
      dataController.add(WifiDirectData(peerId, message));

  @override
  Future<void> initialize({required String deviceName}) async {}
  @override
  Future<void> startAdvertising(String deviceName) async {}
  @override
  Future<void> stopAdvertising() async {}
  @override
  Future<void> startDiscovery() async => discoveryStarts++;
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> connect(String peerId, String deviceName) async {}
  @override
  Future<void> disconnect(String peerId) async {}
  @override
  Future<void> send(String peerId, String message) async =>
      sent.add((peerId, message));
  @override
  Future<void> dispose() async {
    await peerController.close();
    await dataController.close();
  }
}
