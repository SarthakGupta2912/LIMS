// Prefer faster transports among peers observed in the current scan, without
// replacing an endpoint that is already carrying an active shop session.
bool shouldReplaceDiscoveredEndpoint({
  required String? existingEndpoint,
  required String incomingEndpoint,
  required String? connectedEndpoint,
  required bool sameConnectedShop,
}) {
  if (existingEndpoint == null || existingEndpoint == incomingEndpoint) {
    return true;
  }
  if (sameConnectedShop && existingEndpoint == connectedEndpoint) {
    return false;
  }
  return _transportPriority(incomingEndpoint) >=
      _transportPriority(existingEndpoint);
}

int _transportPriority(String endpoint) {
  if (endpoint.startsWith('lan:')) return 3;
  if (endpoint.startsWith('mesh:')) return 2;
  return 1;
}
