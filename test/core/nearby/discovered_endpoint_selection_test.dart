import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/discovered_endpoint_selection.dart';

void main() {
  test('switching transports replaces a previous disconnected endpoint', () {
    for (final oldEndpoint in ['lan:old', 'mesh:old', 'wifi:old']) {
      for (final newEndpoint in ['lan:new', 'mesh:new', 'wifi:new']) {
        // A reconnect scan discards the old endpoint before considering a
        // newly advertised peer, even when its transport has lower priority.
        expect(
          shouldReplaceDiscoveredEndpoint(
            existingEndpoint: null,
            incomingEndpoint: newEndpoint,
            connectedEndpoint: null,
            sameConnectedShop: false,
          ),
          isTrue,
          reason: '$oldEndpoint -> $newEndpoint',
        );
      }
    }
  });

  test('prefers LAN then mesh then Wi-Fi Direct within a scan', () {
    expect(
      shouldReplaceDiscoveredEndpoint(
        existingEndpoint: 'wifi:peer',
        incomingEndpoint: 'mesh:peer',
        connectedEndpoint: null,
        sameConnectedShop: false,
      ),
      isTrue,
    );
    expect(
      shouldReplaceDiscoveredEndpoint(
        existingEndpoint: 'mesh:peer',
        incomingEndpoint: 'lan:peer',
        connectedEndpoint: null,
        sameConnectedShop: false,
      ),
      isTrue,
    );
    expect(
      shouldReplaceDiscoveredEndpoint(
        existingEndpoint: 'lan:peer',
        incomingEndpoint: 'mesh:peer',
        connectedEndpoint: null,
        sameConnectedShop: false,
      ),
      isFalse,
    );
  });

  test('never replaces the active endpoint for its connected shop', () {
    expect(
      shouldReplaceDiscoveredEndpoint(
        existingEndpoint: 'wifi:connected',
        incomingEndpoint: 'lan:other',
        connectedEndpoint: 'wifi:connected',
        sameConnectedShop: true,
      ),
      isFalse,
    );
    expect(
      shouldReplaceDiscoveredEndpoint(
        existingEndpoint: 'wifi:connected',
        incomingEndpoint: 'lan:other',
        connectedEndpoint: null,
        sameConnectedShop: true,
      ),
      isTrue,
    );
  });
}
