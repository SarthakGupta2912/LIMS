// Defines the hardware-neutral boundary between nearby session logic and a
// concrete peer-to-peer transport implementation.

import 'dart:typed_data';

enum NearbyAdapterState { unknown, unsupported, unauthorized, off, on }

enum NearbyLinkDirection { outgoing, incoming }

class NearbyDiscoveredPeer {
  NearbyDiscoveredPeer({
    required this.peerId,
    required this.name,
    required this.serviceData,
    required this.rssi,
  });

  final String peerId;
  final String? name;
  final Map<String, Uint8List> serviceData;
  final int rssi;
}

class NearbyConnectionEvent {
  NearbyConnectionEvent({
    required this.peerId,
    required this.direction,
    required this.connected,
  });

  final String peerId;
  final NearbyLinkDirection direction;
  final bool connected;
}

class NearbyChannelReadyEvent {
  NearbyChannelReadyEvent({required this.peerId, required this.ready});

  final String peerId;
  final bool ready;
}

class NearbyInboundFrame {
  NearbyInboundFrame({required this.peerId, required this.bytes});

  final String peerId;
  final Uint8List bytes;
}

class NearbyAdvertisementSpec {
  NearbyAdvertisementSpec({
    this.name,
    required this.serviceIds,
    required this.serviceData,
  });

  final String? name;
  final List<String> serviceIds;
  final Map<String, Uint8List> serviceData;
}

abstract class NearbyTransport {
  Stream<NearbyAdapterState> get adapterStates;
  Stream<NearbyDiscoveredPeer> get discoveredPeers;
  Stream<NearbyConnectionEvent> get connectionEvents;
  Stream<NearbyChannelReadyEvent> get channelReadyEvents;
  Stream<NearbyInboundFrame> get inboundFrames;

  Future<void> startDiscovery(List<String> serviceIds);
  Future<void> stopDiscovery();
  Future<void> startAdvertising(NearbyAdvertisementSpec spec);
  Future<void> stopAdvertising();
  Future<void> connect(String peerId);
  Future<void> disconnectPeer(String peerId);
  Future<void> send(String peerId, Uint8List frame);
  Future<int> maxFrameBytes(String peerId);
  Future<List<String>> connectedPeerIds();
  Future<void> dispose();
}
