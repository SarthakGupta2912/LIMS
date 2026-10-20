import 'dart:convert';
import 'dart:typed_data';

const nearbyEndpointPrefix = 'LIMS:';

String encodeNearbyEndpointName(Uint8List metadata) =>
    '$nearbyEndpointPrefix${base64Url.encode(metadata).replaceAll('=', '')}';

Uint8List? decodeNearbyEndpointMetadata(String endpointName) {
  if (!endpointName.startsWith(nearbyEndpointPrefix)) return null;
  final encoded = endpointName.substring(nearbyEndpointPrefix.length);
  try {
    return base64Url.decode(base64Url.normalize(encoded));
  } on FormatException {
    return null;
  }
}
