// Handles peer, payload, and reconnect events for WifiDirectTransport, keeping
// platform lifecycle operations separate from event translation.

part of 'wifi_direct_transport.dart';

extension _WifiDirectTransportEvents on WifiDirectTransport {
  void _peersChanged(List<WifiDirectPeer> peers) {
    for (final peer in peers) {
      _peerNames[peer.id] = peer.name;
      final previous = _peerStates[peer.id];
      _peerStates[peer.id] = peer.state;
      if (peer.state == WifiDirectPeerState.disconnected) {
        if (previous == WifiDirectPeerState.connected ||
            previous == WifiDirectPeerState.connecting ||
            _outgoingPeers.contains(peer.id)) {
          _disconnected(peer.id);
        }
        _publishDiscovered(peer);
      } else if (peer.state == WifiDirectPeerState.connected) {
        if (previous != WifiDirectPeerState.connected) _connectedPeer(peer.id);
      } else {
        _publishDiscovered(peer);
      }
    }
  }

  void _publishDiscovered(WifiDirectPeer peer) {
    final metadata = decodeNearbyEndpointMetadata(peer.name);
    if (metadata == null || !_discovering || _serviceDiscoveryId == null) {
      return;
    }
    _discoveredPeers.add(
      NearbyDiscoveredPeer(
        peerId: peer.id,
        name: peer.name,
        serviceData: {_serviceDiscoveryId!: metadata},
        rssi: 0,
      ),
    );
    if (_allowReconnect && peer.name == _desiredPeerName) {
      unawaited(connect(peer.id));
    }
  }

  void _connectedPeer(String peerId) {
    _connecting = false;
    if (_serviceDiscoveryId != null) _outgoingPeers.add(peerId);
    _connected.add(peerId);
    _connectionEvents.add(
      NearbyConnectionEvent(
        peerId: peerId,
        direction: _direction(peerId),
        connected: true,
      ),
    );
    _channelReadyEvents.add(
      NearbyChannelReadyEvent(peerId: peerId, ready: true),
    );
  }

  void _disconnected(String peerId) {
    _connecting = false;
    final wasConnected = _connected.remove(peerId);
    final wasOutgoing = _outgoingPeers.contains(peerId);
    _channelReadyEvents.add(
      NearbyChannelReadyEvent(peerId: peerId, ready: false),
    );
    if (wasConnected || wasOutgoing) {
      _connectionEvents.add(
        NearbyConnectionEvent(
          peerId: peerId,
          direction: wasOutgoing
              ? NearbyLinkDirection.outgoing
              : NearbyLinkDirection.incoming,
          connected: false,
        ),
      );
    }
    _outgoingPeers.remove(peerId);
  }

  NearbyLinkDirection _direction(String peerId) =>
      _outgoingPeers.contains(peerId)
      ? NearbyLinkDirection.outgoing
      : NearbyLinkDirection.incoming;

  void _dataReceived(WifiDirectData data) {
    try {
      _router(
        data.peerId,
      ).addBytes(base64Url.decode(base64Url.normalize(data.message)));
    } on FormatException catch (_) {}
  }

  GattRouter _router(String peerId) => _routers.putIfAbsent(peerId, () {
    final router = GattRouter();
    router.registerHandler(
      WifiDirectTransport.serviceId,
      WifiDirectTransport.dataCharacteristicId,
      (message) {
        _inboundFrames.add(
          NearbyInboundFrame(peerId: peerId, bytes: message.payload),
        );
      },
    );
    return router;
  });
}
