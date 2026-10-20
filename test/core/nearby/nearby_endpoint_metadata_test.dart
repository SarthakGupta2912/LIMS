import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/nearby/nearby_endpoint_metadata.dart';

void main() {
  test('round-trips advertisement metadata through an endpoint name', () {
    final metadata = Uint8List.fromList(List.generate(20, (index) => index));
    final name = encodeNearbyEndpointName(metadata);

    expect(name, startsWith(nearbyEndpointPrefix));
    expect(decodeNearbyEndpointMetadata(name), metadata);
  });

  test('rejects unrelated and malformed endpoint names', () {
    expect(decodeNearbyEndpointMetadata('Other app'), isNull);
    expect(decodeNearbyEndpointMetadata('$nearbyEndpointPrefix!'), isNull);
  });
}
