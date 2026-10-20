import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/custom_mesh_transport.dart';
import 'package:lims/core/nearby/nearby_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lims/custom_mesh/transport');
  const events = MethodChannel('lims/custom_mesh/transport_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Future<void> emit(Map<String, Object?> event) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) => done.complete(),
    );
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  test('mesh discovery retries until stopped', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final transport = CustomMeshTransport();
    await transport.startDiscovery(['ffb0']);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(
      calls.where((call) => call == 'discover').length,
      greaterThanOrEqualTo(2),
    );
    await transport.stopDiscovery();
    final afterStop = calls.length;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(calls.length, afterStop);
    await transport.dispose();
  });

  test(
    'mesh discovery supplies address and incoming disconnect keeps its direction',
    () async {
      final transport = CustomMeshTransport();
      final connections = <NearbyConnectionEvent>[];
      final discovered = <NearbyDiscoveredPeer>[];
      final subscriptions = [
        transport.connectionEvents.listen(connections.add),
        transport.discoveredPeers.listen(discovered.add),
      ];
      await transport.startDiscovery(['ffb0']);
      await emit({
        'type': 'discovered',
        'peerId': 'mesh:169.254.1.2',
        'address': '169.254.1.2',
        'port': 39888,
        'advertisement': Uint8List.fromList([1, 2, 3]),
      });
      expect(discovered.single.peerId, 'mesh:169.254.1.2');
      await emit({
        'type': 'connected',
        'peerId': 'mesh:customer',
        'direction': 'incoming',
      });
      expect(await transport.connectedPeerIds(), ['mesh:customer']);
      await emit({'type': 'disconnected', 'peerId': 'mesh:customer'});
      expect(connections.last.direction, NearbyLinkDirection.incoming);
      expect(connections.last.connected, isFalse);
      expect(await transport.connectedPeerIds(), isEmpty);
      await transport.dispose();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
}
