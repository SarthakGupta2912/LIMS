import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/lan_transport.dart';
import 'package:lims/core/nearby/nearby_transport.dart';

void main() {
  test(
    'one LAN shop accepts multiple independent customers',
    () async {
      final server = LanTransport(discoveryPort: 39986, dataPort: 39988);
      final customerA = LanTransport(discoveryPort: 39986, dataPort: 39989);
      final customerB = LanTransport(discoveryPort: 39986, dataPort: 39990);
      final advertisement = NearbyAdvertisementSpec(
        name: 'Test shop',
        serviceIds: ['ffb0'],
        serviceData: {
          'ffb0': Uint8List.fromList([1, 2, 3]),
        },
      );

      addTearDown(() async {
        await customerB.dispose();
        await customerA.dispose();
        await server.dispose();
      });

      await Future.wait([
        customerA.startDiscovery(['ffb0']),
        customerB.startDiscovery(['ffb0']),
        server.startAdvertising(advertisement),
      ]);

      final discovered = await Future.wait([
        customerA.discoveredPeers.first.timeout(const Duration(seconds: 3)),
        customerB.discoveredPeers.first.timeout(const Duration(seconds: 3)),
      ]);
      final connectedA = customerA.connectionEvents.firstWhere(
        (event) => event.connected,
      );
      final connectedB = customerB.connectionEvents.firstWhere(
        (event) => event.connected,
      );
      await Future.wait([
        customerA.connect(discovered[0].peerId),
        customerB.connect(discovered[1].peerId),
      ]);

      await Future.wait([connectedA, connectedB]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await server.connectedPeerIds(), hasLength(2));
    },
    timeout: const Timeout(Duration(seconds: 8)),
  );
}
