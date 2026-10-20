import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'nearby_transport.dart';

/// Offline local-network transport. One shop server can serve many customers.
class LanTransport implements NearbyTransport {
  LanTransport({this._discoveryPort = 39886, this._dataPort = 39888});

  final int _discoveryPort;
  final int _dataPort;
  static const _prefix = 'lims-lan-v1';

  final _adapter = StreamController<NearbyAdapterState>.broadcast();
  final _discovered = StreamController<NearbyDiscoveredPeer>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _ready = StreamController<NearbyChannelReadyEvent>.broadcast();
  final _inbound = StreamController<NearbyInboundFrame>.broadcast();
  final _peers = <String, InternetAddress>{};
  final _peerPorts = <String, int>{};
  final _sockets = <String, Socket>{};
  final _buffers = <String, BytesBuilder>{};
  final _directions = <String, NearbyLinkDirection>{};
  final _localId = _randomId();
  RawDatagramSocket? _udp;
  ServerSocket? _server;
  Timer? _beacon;
  Timer? _discoveryRequests;
  NearbyAdvertisementSpec? _advertisement;
  bool _discovering = false;
  bool _advertising = false;

  @override
  Stream<NearbyAdapterState> get adapterStates => _adapter.stream;
  @override
  Stream<NearbyDiscoveredPeer> get discoveredPeers => _discovered.stream;
  @override
  Stream<NearbyConnectionEvent> get connectionEvents => _connections.stream;
  @override
  Stream<NearbyChannelReadyEvent> get channelReadyEvents => _ready.stream;
  @override
  Stream<NearbyInboundFrame> get inboundFrames => _inbound.stream;

  @override
  Future<void> startAdvertising(NearbyAdvertisementSpec spec) async {
    _advertisement = spec;
    _advertising = true;
    await _startServer();
    _beacon?.cancel();
    await _ensureUdp(bindPort: _discoveryPort);
    await _sendBeacon();
    _beacon = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_sendBeacon());
    });
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
    _advertisement = null;
    _beacon?.cancel();
    _beacon = null;
  }

  @override
  Future<void> startDiscovery(List<String> serviceIds) async {
    if (serviceIds.isEmpty) throw ArgumentError('A service ID is required');
    _discovering = true;
    await _ensureUdp(bindPort: 0);
    _sendDiscoveryRequest();
    _discoveryRequests?.cancel();
    _discoveryRequests = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendDiscoveryRequest();
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    _discoveryRequests?.cancel();
    _discoveryRequests = null;
    if (!_advertising) {
      _udp?.close();
      _udp = null;
    }
  }

  @override
  Future<void> connect(String peerId) async {
    final address = _peers[peerId];
    if (address == null) throw StateError('Unknown LAN peer $peerId');
    if (_sockets.containsKey(peerId)) return;
    final socket = await Socket.connect(
      address,
      _peerPorts[peerId] ?? _dataPort,
      timeout: const Duration(seconds: 8),
    );
    _attach(peerId, socket, outgoing: true);
  }

  @override
  Future<void> disconnectPeer(String peerId) async => _closePeer(peerId);

  @override
  Future<void> send(String peerId, Uint8List frame) async {
    final socket = _sockets[peerId];
    if (socket == null) throw StateError('LAN peer disconnected');
    final packet = BytesBuilder()
      ..add(_u32(frame.length))
      ..add(frame);
    socket.add(packet.takeBytes());
    await socket.flush();
  }

  @override
  Future<int> maxFrameBytes(String peerId) async => 1024 * 1024;

  @override
  Future<List<String>> connectedPeerIds() async => _sockets.keys.toList();

  Future<void> _ensureUdp({required int bindPort}) async {
    if (_udp != null) return;
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, bindPort);
    udp.broadcastEnabled = true;
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = udp.receive();
      if (datagram == null) return;
      final text = utf8.decode(datagram.data, allowMalformed: true);
      if (_advertising && text == '$_prefix:discover') {
        unawaited(_sendBeacon(to: datagram.address, port: datagram.port));
      } else if (_discovering) {
        _readBeacon(datagram.data, datagram.address);
      }
    });
    _udp = udp;
  }

  Future<void> _sendDiscoveryRequest() async {
    final udp = _udp;
    if (udp == null) return;
    final packet = utf8.encode('$_prefix:discover');
    final targets = <String>{'255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final address in interface.addresses) {
          final octets = address.address.split('.');
          if (octets.length == 4 && address.address != '127.0.0.1') {
            targets.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
          }
        }
      }
    } catch (_) {}
    for (final target in targets) {
      udp.send(packet, InternetAddress(target), _discoveryPort);
    }
  }

  Future<void> _sendBeacon({InternetAddress? to, int? port}) async {
    final udp = _udp;
    final spec = _advertisement;
    if (udp == null || spec == null || !_advertising) return;
    final data = spec.serviceData.values.firstOrNull ?? Uint8List(0);
    final message = jsonEncode({
      'v': 1,
      'id': _localId,
      'name': spec.name ?? 'LIMS shop',
      'port': _dataPort,
      'data': base64UrlEncode(data),
    });
    udp.send(
      utf8.encode('$_prefix:$message'),
      to ?? InternetAddress('255.255.255.255'),
      port ?? _discoveryPort,
    );
  }

  void _readBeacon(Uint8List bytes, InternetAddress address) {
    try {
      final text = utf8.decode(bytes);
      if (!text.startsWith('$_prefix:')) return;
      final json = jsonDecode(text.substring(_prefix.length + 1));
      if (json is! Map || json['id'] == _localId) return;
      final id = 'lan:${json['id']}';
      final data = base64Url.decode(json['data'] as String);
      final port = json['port'];
      if (port is! int || port < 1 || port > 65535) return;
      _peers[id] = address;
      _peerPorts[id] = port;
      _discovered.add(
        NearbyDiscoveredPeer(
          peerId: id,
          name: json['name'] as String?,
          serviceData: {'ffb0': Uint8List.fromList(data)},
          rssi: 0,
        ),
      );
    } catch (_) {}
  }

  Future<void> _startServer() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      _dataPort,
      shared: true,
    );
    _server!.listen((socket) {
      final peerId = 'lan:${socket.remoteAddress.address}:${socket.remotePort}';
      _attach(peerId, socket, outgoing: false);
    });
  }

  void _attach(String peerId, Socket socket, {required bool outgoing}) {
    _sockets[peerId]?.destroy();
    _sockets[peerId] = socket;
    _buffers[peerId] = BytesBuilder();
    final direction = outgoing
        ? NearbyLinkDirection.outgoing
        : NearbyLinkDirection.incoming;
    _directions[peerId] = direction;
    _connections.add(
      NearbyConnectionEvent(
        peerId: peerId,
        direction: direction,
        connected: true,
      ),
    );
    _ready.add(NearbyChannelReadyEvent(peerId: peerId, ready: true));
    socket.listen(
      (bytes) => _readFrames(peerId, bytes),
      onDone: () => _closePeer(peerId),
      onError: (_) => _closePeer(peerId),
      cancelOnError: true,
    );
  }

  void _readFrames(String peerId, List<int> bytes) {
    final buffer = _buffers[peerId];
    if (buffer == null) return;
    buffer.add(bytes);
    final data = buffer.takeBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      final length = _readU32(data, offset);
      if (length > 1024 * 1024 || data.length - offset - 4 < length) {
        break;
      }
      _inbound.add(
        NearbyInboundFrame(
          peerId: peerId,
          bytes: Uint8List.fromList(
            data.sublist(offset + 4, offset + 4 + length),
          ),
        ),
      );
      offset += 4 + length;
    }
    _buffers[peerId] = BytesBuilder()..add(data.sublist(offset));
  }

  Future<void> _closePeer(String peerId) async {
    final socket = _sockets.remove(peerId);
    _buffers.remove(peerId);
    final direction = _directions.remove(peerId);
    socket?.destroy();
    if (socket != null && direction != null) {
      _ready.add(NearbyChannelReadyEvent(peerId: peerId, ready: false));
      _connections.add(
        NearbyConnectionEvent(
          peerId: peerId,
          direction: direction,
          connected: false,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    _beacon?.cancel();
    _discoveryRequests?.cancel();
    await _server?.close();
    _udp?.close();
    for (final socket in List<Socket>.of(_sockets.values)) {
      socket.destroy();
    }
    await Future.wait([
      _adapter.close(),
      _discovered.close(),
      _connections.close(),
      _ready.close(),
      _inbound.close(),
    ]);
  }

  static String _randomId() =>
      Random.secure().nextInt(1 << 32).toRadixString(16);
  static Uint8List _u32(int value) => Uint8List.fromList([
    value >> 24,
    value >> 16 & 255,
    value >> 8 & 255,
    value & 255,
  ]);
  static int _readU32(List<int> bytes, int offset) =>
      bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}
