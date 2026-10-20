import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart' as ids;

import 'app_database.dart';
import 'buzz_vibration_service.dart';
import 'nearby/discovered_endpoint_selection.dart';
import 'nearby/link_state.dart';
import 'nearby/hybrid_transport.dart';
import 'nearby/nearby_transport.dart';
import 'nearby/session_engine.dart';
import 'nearby/sync_protocol.dart';
import 'nearby/transfer_codec.dart';
import 'notification_service.dart';

/// UI-facing activity, derived from the authoritative [LinkSnapshot].
enum NearbyActivity {
  idle,
  discovering,
  advertising,
  connecting,
  connected,
  syncing,
  reconnecting,
  error,
}

enum CustomerBuzzResult {
  delivered,
  deliveryUnconfirmed,
  unavailable,
  cooldown,
  invalidOrder,
  sendFailed,
}

enum CustomerBuzzStopResult { delivered, customerUnavailable, alreadyEnded }

class CustomerBuzzEvent {
  final String eventId;
  final String orderId;
  final String shopId;
  final String shopName;
  final DateTime sentAt;
  final DateTime endsAt;

  const CustomerBuzzEvent({
    required this.eventId,
    required this.orderId,
    required this.shopId,
    required this.shopName,
    required this.sentAt,
    required this.endsAt,
  });
}

bool isBuzzEligibleStatus(String status) =>
    const {'accepted', 'preparing', 'ready_for_pickup'}.contains(status);

bool isBuzzMessageCurrent({
  required DateTime now,
  required DateTime sentAt,
  required DateTime endsAt,
}) =>
    !sentAt.isAfter(now.add(const Duration(seconds: 30))) &&
    endsAt.isAfter(now) &&
    !endsAt.isAfter(sentAt.add(const Duration(minutes: 5)));

class DiscoveredShop {
  final String endpointId;
  final NearbyShopRecord shop;

  const DiscoveredShop({required this.endpointId, required this.shop});
}

class _LegacyIncomingTransfer {
  final int chunkCount;
  final Map<int, Uint8List> chunks = {};

  _LegacyIncomingTransfer(this.chunkCount);
}

/// UI facade over the Nearby Connections stack.
///
/// Transport, framing, session state, and retry policy live in
/// `lib/core/nearby/`; SQLite remains the single source of truth and Nearby is
/// only a transport. All local mutations mark rows `pending`; rows become
/// `synced` only after a matching ACK.
class NearbyConnectionService extends ChangeNotifier {
  NearbyConnectionService._({NearbyTransport? transport})
    : _transport = transport ?? HybridTransport(),
      _engine = SessionEngine();

  static final instance = NearbyConnectionService._();

  /// Test/production composition root with an injected transport.
  factory NearbyConnectionService.withTransport(NearbyTransport transport) =>
      NearbyConnectionService._(transport: transport);

  static const _discoveryUuid = 'ffb0';
  static const _protocolVersion = 2;

  final NearbyTransport _transport;
  final SessionEngine _engine;
  final BleTransferCodec _codec = const BleTransferCodec();
  final TransferReassembler _reassembler = TransferReassembler();
  final Map<String, _LegacyIncomingTransfer> _legacyIncoming = {};
  final Map<String, Future<void>> _sendTails = {};
  final Map<String, DiscoveredShop> _shopsByShopId = {};
  final Map<String, String> _shopTokenByFullId = {};
  final Set<String> _shopConnectedPeers = {};
  String? _activePeerId;
  final Map<String, String> _customerIdByEndpoint = {};
  final Map<String, String> _endpointByCustomerId = {};
  final Map<String, bool> _notifyReadyByEndpoint = {};
  final Map<String, Completer<bool>> _pendingBuzzAcks = {};
  final StreamController<CustomerBuzzEvent> _buzzController =
      StreamController<CustomerBuzzEvent>.broadcast();
  final StreamController<String> _buzzStopController =
      StreamController<String>.broadcast();
  CustomerBuzzEvent? _activeCustomerBuzz;
  String? _activeCustomerBuzzEndpoint;
  Timer? _customerBuzzExpiryTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _transportReady = false;
  bool _manualStop = false;
  bool _discoveryPaused = false;
  bool _foreground = true;
  bool _backgroundActive = false;
  bool _reconciling = false;
  int _transferId = 0;
  Timer? _scanWindowTimer;
  Timer? _connectionTimer;
  Timer? _reconnectTimer;
  Timer? _advertisingRecoveryTimer;
  Timer? _reconcileTimer;
  int _reconnectAttempt = 0;
  int _discoveryOperation = 0;
  int _connectionIntent = 0;
  Future<bool>? _advertisingOperation;
  LocalProfile? _customer;
  String? _targetShopId;
  String? _targetShopName;
  String? _qrMeshEndpoint;

  NearbyActivity activity = NearbyActivity.idle;
  String? errorMessage;
  String? connectedEndpoint;
  String? connectedShopId;
  String? connectedShopName;
  int currentCatalogRevision = 0;
  List<ProductRecord> currentCatalog = const [];
  DateTime? lastSyncedAt;

  void Function(String shopId, String shopName, List<ProductRecord> products)?
  onCatalog;

  List<DiscoveredShop> get shops {
    final fullId = connectedShopId;
    final connectedKey = fullId == null ? null : _shopKey(fullId);
    return _shopsByShopId.entries
        .where((entry) => entry.key != connectedKey)
        .map((entry) => entry.value)
        .toList()
      ..sort((a, b) {
        final byName = a.shop.name.toLowerCase().compareTo(
          b.shop.name.toLowerCase(),
        );
        return byName != 0
            ? byName
            : _shopKey(a.shop.shopId).compareTo(_shopKey(b.shop.shopId));
      });
  }

  List<CachedShopRecord> get cachedShops {
    final customer = _customer;
    if (customer == null) return const [];
    final activeId = connectedShopId;
    return AppDatabase.instance
        .cachedShops(customer.id)
        .where(
          (cached) =>
              activeId == null ||
              _shopKey(cached.shop.shopId) != _shopKey(activeId),
        )
        .where(
          (cached) => !_shopsByShopId.values.any(
            (live) =>
                _shopKey(live.shop.shopId) == _shopKey(cached.shop.shopId),
          ),
        )
        .toList();
  }

  bool get supported => !kIsWeb && Platform.isAndroid;
  bool get connected => connectedEndpoint != null;
  bool get reconnecting => activity == NearbyActivity.reconnecting;
  bool get discoveryPaused => _discoveryPaused;
  bool get foreground => _foreground;
  List<CustomerRecord> get connectedMeshCustomers {
    final ids = _customerIdByEndpoint.entries
        .where(
          (entry) =>
              entry.key.startsWith('mesh:') &&
              _shopConnectedPeers.contains(entry.key),
        )
        .map((entry) => entry.value)
        .toSet();
    if (ids.isEmpty) return const [];
    return AppDatabase.instance
        .customers()
        .where(
          (customer) => ids.contains(customer.sourceProfileId ?? customer.uuid),
        )
        .toList();
  }

  Future<void> connectToScannedMeshShop(
    LocalProfile customer,
    String address,
  ) async {
    await disconnect();
    _customer = customer;
    _qrMeshEndpoint = 'mesh:$address';
    _discoveryPaused = false;
    _manualStop = false;
    await startDiscovery(customer);
  }

  Stream<CustomerBuzzEvent> get customerBuzzEvents => _buzzController.stream;
  Stream<String> get customerBuzzStops => _buzzStopController.stream;

  bool customerIsReachable(String customerId) =>
      _readyEndpointForCustomer(customerId) != null;

  LinkSnapshot get linkSnapshot => _engine.snapshot;

  // ---------------------------------------------------------------------------
  // Transport lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _ensureTransport() async {
    if (_transportReady || !supported) return;
    _subscriptions.addAll([
      _transport.adapterStates.listen(_onAdapterState),
      _transport.discoveredPeers.listen(_onDiscoveredPeer),
      _transport.connectionEvents.listen(_onConnectionEvent),
      _transport.channelReadyEvents.listen(_onChannelReady),
      _transport.inboundFrames.listen(
        (frame) => _receiveFrame(frame.peerId, frame.bytes),
      ),
    ]);
    _transportReady = true;
  }

  Future<void> disposeTransport() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _transportReady = false;
    for (final completer in _pendingBuzzAcks.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingBuzzAcks.clear();
    await _transport.dispose();
  }

  void _onAdapterState(NearbyAdapterState state) {
    switch (state) {
      case NearbyAdapterState.off:
        _engine.adapterChanged(powered: false);
        unawaited(_handleWifiUnavailable());
      case NearbyAdapterState.on:
        _engine.adapterChanged(powered: true);
        _applyLinkSnapshot();
        final profile = AppDatabase.instance.activeProfile();
        if (profile != null &&
            profile.role == AppRole.shopkeeper &&
            activity != NearbyActivity.advertising) {
          unawaited(resumeForForeground(profile));
        }
      case NearbyAdapterState.unauthorized:
      case NearbyAdapterState.unsupported:
      case NearbyAdapterState.unknown:
        _applyLinkSnapshot();
    }
  }

  void _applyLinkSnapshot() {
    final snapshot = _engine.snapshot;
    activity = switch (snapshot.state) {
      LinkState.adapterOff => NearbyActivity.idle,
      LinkState.scanning =>
        _targetShopId != null
            ? NearbyActivity.reconnecting
            : NearbyActivity.discovering,
      LinkState.connecting => NearbyActivity.connecting,
      LinkState.connected => NearbyActivity.connected,
      LinkState.syncing => NearbyActivity.syncing,
      LinkState.idle => NearbyActivity.idle,
    };
    if (snapshot.state == LinkState.adapterOff) {
      errorMessage = 'Wi-Fi is off. Turn it on to use nearby features.';
    }
    notifyListeners();
  }

  Future<bool> _requestPermissions() async {
    if (!supported) {
      _setError('Nearby shops are currently available on Android only.');
      return false;
    }
    final sdkInt = await const MethodChannel(
      'lims/platform',
    ).invokeMethod<int>('sdkInt');
    final permission = (sdkInt ?? 33) >= 33
        ? Permission.nearbyWifiDevices
        : Permission.locationWhenInUse;
    if (!await permission.request().isGranted) {
      _setError('Nearby device permission is needed to find nearby shops.');
      return false;
    }
    await _ensureTransport();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Discovery (customer)
  // ---------------------------------------------------------------------------

  Future<void> startDiscovery(
    LocalProfile customer, {
    bool reconnect = false,
  }) async {
    if (_discoveryPaused) return;
    if (connected) return;
    if (_engine.snapshot.state == LinkState.scanning && !reconnect) {
      return;
    }
    _foreground = true;
    _manualStop = false;
    _customer = customer;
    final generation = _engine.snapshot.sessionEpoch;
    final operation = ++_discoveryOperation;
    _scanWindowTimer?.cancel();
    try {
      await _transport.stopDiscovery();
      if (generation != _engine.snapshot.sessionEpoch ||
          operation != _discoveryOperation ||
          _discoveryPaused ||
          !await _requestPermissions()) {
        return;
      }
      errorMessage = null;
      _engine.scanRequested(LinkRole.customer);
      // Old endpoints describe the previous network. Only peers actually
      // advertised in this discovery window may be used for a reconnect.
      if (!connected) _shopsByShopId.clear();
      if (reconnect && _targetShopId != null) {
        activity = NearbyActivity.reconnecting;
      } else {
        activity = NearbyActivity.discovering;
      }
      notifyListeners();
      await _transport.startDiscovery([_discoveryUuid]);
      if (operation != _discoveryOperation || _discoveryPaused) {
        await _transport.stopDiscovery();
        return;
      }
      if (reconnect) _reconnectAttempt++;
      _scanWindowTimer = Timer(const Duration(seconds: 10), () async {
        if (generation != _engine.snapshot.sessionEpoch ||
            operation != _discoveryOperation ||
            _discoveryPaused) {
          return;
        }
        await _transport.stopDiscovery();
        if (connected || _discoveryPaused) return;
        final staleBefore = DateTime.now().subtract(
          const Duration(seconds: 15),
        );
        final previousShopCount = _shopsByShopId.length;
        _shopsByShopId.removeWhere(
          (_, shop) => shop.shop.lastSeen.isBefore(staleBefore),
        );
        if (_shopsByShopId.length != previousShopCount) notifyListeners();
        if (reconnect && _targetShopId != null && !_manualStop) {
          _scheduleReconnect();
        } else if (!_manualStop) {
          await _transport.stopDiscovery();
          _engine.manualStop();
          activity = NearbyActivity.idle;
          notifyListeners();
        }
      });
    } catch (error) {
      debugPrint('Nearby discovery failed: $error');
      _setError('Could not scan for nearby shops. Check device radios.');
      if (reconnect) _scheduleReconnect();
    }
  }

  void _onDiscoveredPeer(NearbyDiscoveredPeer peer) {
    try {
      String? token;
      int revision = 1;
      int flags = 7;
      String? advertisedName;
      peer.serviceData.forEach((uuid, data) {
        if (data.length < 9) return;
        final bytes = ByteData.sublistView(data);
        token = data
            .sublist(0, 4)
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join();
        revision = bytes.getUint32(4, Endian.big);
        flags = data[8];
        if (data.length >= 10) {
          final nameLength = data[9].clamp(0, data.length - 10);
          if (nameLength > 0) {
            advertisedName = utf8.decode(
              data.sublist(10, 10 + nameLength),
              allowMalformed: true,
            );
          }
        }
      });
      final shopId = token;
      if (shopId == null) return;
      final qrEndpoint = _qrMeshEndpoint;
      if (qrEndpoint != null && peer.peerId != qrEndpoint) return;
      final name = advertisedName?.trim().isNotEmpty == true
          ? advertisedName!.trim()
          : peer.name?.trim();
      final shop = NearbyShopRecord(
        shopId: shopId,
        name: name == null || name.isEmpty
            ? 'Nearby shop ${shopId.substring(shopId.length - 4).toUpperCase()}'
            : name,
        category: 'Nearby shop',
        orderingEnabled: flags & 1 != 0,
        statusEnabled: flags & 2 != 0,
        chatEnabled: flags & 4 != 0,
        catalogRevision: revision,
        lastSeen: DateTime.now(),
      );
      final shopKey = _shopKey(shopId);
      final existing = _shopsByShopId[shopKey];
      final existingEndpoint = existing?.endpointId;
      final incomingEndpoint = peer.peerId;
      if (!shouldReplaceDiscoveredEndpoint(
        existingEndpoint: existingEndpoint,
        incomingEndpoint: incomingEndpoint,
        connectedEndpoint: connectedEndpoint,
        sameConnectedShop:
            connectedShopId != null && _shopIdsMatch(connectedShopId!, shopId),
      )) {
        return;
      }
      _shopsByShopId[shopKey] = DiscoveredShop(
        endpointId: peer.peerId,
        shop: shop,
      );
      notifyListeners();
      if (qrEndpoint == peer.peerId && !connected && _activePeerId == null) {
        _qrMeshEndpoint = null;
        _targetShopId = shopId;
        _targetShopName = shop.name;
        currentCatalogRevision = 0;
        currentCatalog = const [];
        unawaited(_connectEndpoint(peer.peerId));
        return;
      }
      if (_targetShopId != null &&
          _shopIdsMatch(_targetShopId!, shopId) &&
          !connected &&
          _activePeerId == null) {
        final target = _shopsByShopId[shopKey];
        if (target != null) unawaited(_connectEndpoint(target.endpointId));
      }
    } catch (error) {
      debugPrint('Ignored invalid LIMS advertisement: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Advertising (shopkeeper)
  // ---------------------------------------------------------------------------

  Future<bool> startAdvertising(LocalProfile owner, ShopProfileRecord shop) {
    final running = _advertisingOperation;
    if (running != null) return running;
    late final Future<bool> operation;
    operation = _startAdvertising(owner, shop);
    _advertisingOperation = operation;
    return operation.whenComplete(() {
      if (identical(_advertisingOperation, operation)) {
        _advertisingOperation = null;
      }
    });
  }

  Future<bool> _startAdvertising(
    LocalProfile owner,
    ShopProfileRecord shop,
  ) async {
    try {
      if (!await _requestPermissions()) return false;
      final nameBytes = _compactUtf8(shop.name, 96);
      final serviceData = Uint8List(10 + nameBytes.length)
        ..setRange(0, 4, _tokenBytes(_shopToken(shop.id)))
        ..[9] = nameBytes.length
        ..setRange(10, 10 + nameBytes.length, nameBytes);
      final view = ByteData.sublistView(serviceData);
      view.setUint32(4, shop.catalogRevision, Endian.big);
      serviceData[8] =
          (shop.orderingEnabled ? 1 : 0) |
          (shop.statusEnabled ? 2 : 0) |
          (shop.chatEnabled ? 4 : 0);
      await _transport.startAdvertising(
        NearbyAdvertisementSpec(
          name: shop.name,
          serviceIds: [_discoveryUuid],
          serviceData: {_discoveryUuid: serviceData},
        ),
      );
      activity = connected
          ? NearbyActivity.connected
          : NearbyActivity.advertising;
      errorMessage = null;
      notifyListeners();
      unawaited(
        NotificationService.instance.startNearbyService(
          'Receiving nearby orders',
        ),
      );
      return true;
    } catch (error) {
      debugPrint('Nearby advertising failed: $error');
      _setError('Could not advertise this shop with Nearby: $error');
      return false;
    }
  }

  Future<void> refreshAdvertisingAndCatalog() async {
    final profile = AppDatabase.instance.activeProfile();
    final shop = profile == null
        ? null
        : AppDatabase.instance.shopForProfile(profile.id);
    if (profile == null || shop == null) return;
    final message = {
      'type': 'catalog_changed',
      'shopId': shop.id,
      'revision': shop.catalogRevision,
    };
    for (final endpoint in _shopConnectedPeers.toList()) {
      unawaited(_send(endpoint, message));
    }
    if (shop.visible && _shopConnectedPeers.isEmpty) {
      await startAdvertising(profile, shop);
    }
  }

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  Future<void> connect(LocalProfile customer, DiscoveredShop endpoint) async {
    final intent = ++_connectionIntent;
    _discoveryPaused = false;
    _manualStop = true;
    _reconnectTimer?.cancel();
    _connectionTimer?.cancel();
    ++_discoveryOperation;
    _scanWindowTimer?.cancel();
    await _stopDiscoveryForSwitch();
    if (intent != _connectionIntent) return;
    _customer = customer;
    _targetShopId = endpoint.shop.shopId;
    _targetShopName = endpoint.shop.name;
    final previousEndpoint = connectedEndpoint;
    if (previousEndpoint != null && previousEndpoint != endpoint.endpointId) {
      _activePeerId = null;
      connectedEndpoint = null;
      connectedShopId = null;
      connectedShopName = null;
      activity = NearbyActivity.reconnecting;
      notifyListeners();
      try {
        await _transport
            .disconnectPeer(previousEndpoint)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      if (intent != _connectionIntent) return;
    }
    if (intent != _connectionIntent) return;
    _manualStop = false;
    final latest = _shopsByShopId[_shopKey(endpoint.shop.shopId)];
    if (latest == null ||
        latest.endpointId != endpoint.endpointId ||
        DateTime.now().difference(latest.shop.lastSeen) >
            const Duration(seconds: 15)) {
      await startDiscovery(customer, reconnect: true);
      return;
    }
    await _connectEndpoint(latest.endpointId);
  }

  Future<void> connectToShopId({
    required LocalProfile customer,
    required String shopId,
    String shopName = 'shop',
  }) async {
    final intent = ++_connectionIntent;
    _customer = customer;
    _targetShopId = shopId;
    _targetShopName = shopName;
    _manualStop = true;
    _reconnectTimer?.cancel();
    _connectionTimer?.cancel();
    ++_discoveryOperation;
    _scanWindowTimer?.cancel();
    await _stopDiscoveryForSwitch();
    if (intent != _connectionIntent) return;
    final previousEndpoint = connectedEndpoint;
    if (previousEndpoint != null) {
      _activePeerId = null;
      connectedEndpoint = null;
      connectedShopId = null;
      connectedShopName = null;
      activity = NearbyActivity.reconnecting;
      notifyListeners();
      try {
        await _transport
            .disconnectPeer(previousEndpoint)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      if (intent != _connectionIntent) return;
    }
    // Do not connect a cached endpoint directly. The shop may have switched
    // between LAN, mesh, and Wi-Fi Direct since it was last seen. A fresh
    // advertisement is the only authoritative endpoint for this session.
    _manualStop = false;
    await startDiscovery(customer, reconnect: true);
  }

  Future<void> _connectEndpoint(String endpointId) async {
    if (connected || _activePeerId == endpointId) return;
    _activePeerId = endpointId;
    _engine.connectionRequested(endpointId, LinkRole.customer);
    _applyLinkSnapshot();
    errorMessage = null;
    notifyListeners();
    _scanWindowTimer?.cancel();
    final generation = _engine.snapshot.sessionEpoch;
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 15), () async {
      if (!connected && generation == _engine.snapshot.sessionEpoch) {
        _activePeerId = null;
        _forgetDiscoveredEndpoint(endpointId);
        errorMessage = 'Connection timed out. Retrying nearby...';
        try {
          await _transport.disconnectPeer(endpointId);
        } catch (_) {}
        _scheduleReconnect(immediate: true);
      }
    });
    try {
      // Transport resolves once the Nearby connection request is accepted.
      await _transport.connect(endpointId);
    } catch (error) {
      if (generation != _engine.snapshot.sessionEpoch) return;
      _connectionTimer?.cancel();
      _activePeerId = null;
      _forgetDiscoveredEndpoint(endpointId);
      debugPrint('Nearby connection failed: $error');
      errorMessage = 'Connection interrupted. Reconnecting nearby...';
      _scheduleReconnect();
    }
  }

  Future<void> _stopDiscoveryForSwitch() async {
    try {
      await _transport.stopDiscovery().timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Nearby discovery stop timed out during shop switch: $error');
    }
  }

  void _forgetDiscoveredEndpoint(String endpointId) {
    final previousCount = _shopsByShopId.length;
    _shopsByShopId.removeWhere((_, shop) => shop.endpointId == endpointId);
    if (_shopsByShopId.length != previousCount) notifyListeners();
  }

  void _onConnectionEvent(NearbyConnectionEvent event) {
    if (event.direction == NearbyLinkDirection.outgoing) {
      _onPeripheralConnection(event);
    } else {
      _onCentralConnection(event);
    }
  }

  Future<void> _onPeripheralConnection(NearbyConnectionEvent event) async {
    final generation = _engine.snapshot.sessionEpoch;
    if (!event.connected) {
      // Ignore disconnects for peers that are not the active attempt.
      if (_activePeerId == null || _activePeerId != event.peerId) return;
      _activePeerId = null;
      _forgetDiscoveredEndpoint(event.peerId);
      _onCustomerDisconnected();
      return;
    }
    // A late or unsolicited callback must never become the active session.
    if (_activePeerId == null) {
      try {
        await _transport.disconnectPeer(event.peerId);
      } catch (_) {}
      return;
    }
    if (_activePeerId != null && _activePeerId != event.peerId) {
      try {
        await _transport.disconnectPeer(event.peerId);
      } catch (_) {}
      return;
    }
    // Ignore duplicate connects for an already-established session.
    if (connected && connectedEndpoint == event.peerId) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _activePeerId = event.peerId;
    _engine.physicalConnected(event.peerId, generation);
    _applyLinkSnapshot();
    try {
      _connectionTimer?.cancel();
      _engine.sessionReady(event.peerId, generation);
      connectedEndpoint = event.peerId;
      connectedShopId = _targetShopId;
      connectedShopName = _targetShopName;
      _applyLinkSnapshot();
      notifyListeners();
      final customer = _customer;
      if (customer != null) {
        await _send(connectedEndpoint!, {
          'type': 'hello',
          'protocolVersion': _protocolVersion,
          'profileId': customer.id,
          'customerName': customer.displayName,
          'role': customer.role.name,
          'targetShopId': _targetShopId,
          'cursor': _cursorFor(customer.id, 'orders'),
        });
        await _requestCatalog(connectedEndpoint!);
        await requestStatusSync();
        await _pullStatusDeltas();
      }
    } catch (error) {
      debugPrint('Nearby session handshake failed: $error');
      _activePeerId = null;
      _onCustomerDisconnected();
    }
  }

  void _onCentralConnection(NearbyConnectionEvent event) {
    if (event.connected) {
      _shopConnectedPeers.add(event.peerId);
      connectedEndpoint = event.peerId;
      activity = NearbyActivity.advertising;
      errorMessage = null;
    } else {
      _shopConnectedPeers.remove(event.peerId);
      _customerIdByEndpoint.remove(event.peerId);
      _notifyReadyByEndpoint.remove(event.peerId);
      _endpointByCustomerId.removeWhere(
        (customerId, endpoint) => endpoint == event.peerId,
      );
      if (connectedEndpoint == event.peerId) {
        connectedEndpoint = _shopConnectedPeers.isEmpty
            ? null
            : _shopConnectedPeers.first;
      }
      if (_shopConnectedPeers.isEmpty) {
        activity = NearbyActivity.advertising;
        unawaited(_recoverShopAdvertising());
      }
    }
    notifyListeners();
  }

  void _onChannelReady(NearbyChannelReadyEvent event) {
    _notifyReadyByEndpoint[event.peerId] = event.ready;
    debugPrint(
      'Nearby payload channel ${event.ready ? 'ready' : 'closed'}: ${event.peerId}',
    );
    if (event.ready) {
      final customerId = _customerIdByEndpoint[event.peerId];
      if (customerId != null) {
        unawaited(_sendQueuedForPeer(event.peerId, customerId));
      }
    }
    notifyListeners();
  }

  void _onCustomerDisconnected() {
    _connectionTimer?.cancel();
    _reconnectTimer?.cancel();
    _activePeerId = null;
    final disconnectedEndpoint = connectedEndpoint;
    if (disconnectedEndpoint != null) {
      _forgetDiscoveredEndpoint(disconnectedEndpoint);
    }
    connectedEndpoint = null;
    final profile = AppDatabase.instance.activeProfile();
    if (profile?.role == AppRole.customer &&
        _targetShopId != null &&
        !_manualStop &&
        (_foreground || _backgroundActive)) {
      errorMessage = 'Connection lost. Reconnecting nearby...';
      _scheduleReconnect();
    } else {
      activity = NearbyActivity.idle;
      notifyListeners();
    }
  }

  bool _shopIdsMatch(String left, String right) {
    final a = left.replaceAll('-', '').toLowerCase();
    final b = right.replaceAll('-', '').toLowerCase();
    return a.length >= 8 &&
        b.length >= 8 &&
        a.substring(0, 8) == b.substring(0, 8);
  }

  void _scheduleReconnect({bool immediate = false}) {
    final customer = _customer;
    if (_manualStop ||
        (!_foreground && !_backgroundActive) ||
        customer == null ||
        _targetShopId == null ||
        connected) {
      return;
    }
    activity = NearbyActivity.reconnecting;
    errorMessage = 'Reconnecting nearby...';
    notifyListeners();
    _reconnectTimer?.cancel();
    final delay = immediate
        ? Duration.zero
        : Duration(seconds: (1 << _reconnectAttempt.clamp(0, 4)).clamp(1, 15));
    _reconnectTimer = Timer(delay, () {
      if (_manualStop || connected || _targetShopId == null) return;
      unawaited(startDiscovery(customer, reconnect: true));
    });
  }

  Future<void> reconnectNow() async {
    if (_customer == null || _targetShopId == null) return;
    _discoveryPaused = false;
    _manualStop = false;
    _foreground = true;
    await startDiscovery(_customer!, reconnect: true);
  }

  Future<void> resumeDiscovery(LocalProfile customer) async {
    if (_customer?.id == customer.id &&
        !_discoveryPaused &&
        (activity == NearbyActivity.discovering ||
            activity == NearbyActivity.reconnecting ||
            activity == NearbyActivity.connecting ||
            activity == NearbyActivity.syncing ||
            activity == NearbyActivity.connected)) {
      return;
    }
    _discoveryPaused = false;
    _manualStop = false;
    _foreground = true;
    activity = NearbyActivity.discovering;
    errorMessage = null;
    notifyListeners();
    await startDiscovery(customer);
  }

  // ---------------------------------------------------------------------------
  // Framed transport
  // ---------------------------------------------------------------------------

  Future<void> _requestCatalog(String endpoint) async {
    activity = NearbyActivity.syncing;
    notifyListeners();
    await _send(endpoint, {
      'type': 'catalog_request',
      'shopId': _targetShopId,
      'revision': currentCatalogRevision,
    });
  }

  void _receiveFrame(String peerId, Uint8List frame) {
    if (frame.isEmpty) return;
    if (frame[0] == 0x4d) {
      final result = _reassembler.addFrame(peerId, frame, DateTime.now());
      if (result == null) return;
      try {
        final message =
            jsonDecode(utf8.decode(result.payload)) as Map<String, dynamic>;
        _handleMessage(peerId, message);
      } catch (error) {
        debugPrint('Ignored invalid Nearby message: $error');
      }
      return;
    }
    _receiveLegacyFrame(peerId, frame);
  }

  void _receiveLegacyFrame(String peerId, Uint8List frame) {
    if (frame.length < 7 || frame[0] != 0x4c) return;
    final data = ByteData.sublistView(frame);
    final transferId = data.getUint16(1, Endian.big);
    final chunkIndex = data.getUint16(3, Endian.big);
    final chunkCount = data.getUint16(5, Endian.big);
    if (chunkCount == 0 || chunkCount > 512 || chunkIndex >= chunkCount) return;
    final key = '$peerId:$transferId';
    final incoming = _legacyIncoming.putIfAbsent(
      key,
      () => _LegacyIncomingTransfer(chunkCount),
    );
    if (incoming.chunkCount != chunkCount) {
      _legacyIncoming.remove(key);
      return;
    }
    incoming.chunks[chunkIndex] = frame.sublist(7);
    if (incoming.chunks.length != chunkCount) return;
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < chunkCount; i++) {
      final chunk = incoming.chunks[i];
      if (chunk == null) return;
      builder.add(chunk);
    }
    _legacyIncoming.remove(key);
    try {
      final message =
          jsonDecode(utf8.decode(builder.takeBytes())) as Map<String, dynamic>;
      _handleMessage(peerId, message);
    } catch (error) {
      debugPrint('Ignored invalid Nearby message: $error');
    }
  }

  Future<void> _send(String endpoint, Map<String, dynamic> message) {
    final pending = _sendTails[endpoint] ?? Future.value();
    final completer = Completer<void>();
    _sendTails[endpoint] = pending.catchError((_) {}).then((_) async {
      try {
        await _sendNow(
          endpoint,
          utf8.encode(jsonEncode(message)),
        ).timeout(const Duration(seconds: 10));
        completer.complete();
      } catch (error, stackTrace) {
        debugPrint('Nearby send failed: $error');
        completer.completeError(error, stackTrace);
        final profile = AppDatabase.instance.activeProfile();
        if (profile?.role == AppRole.customer &&
            endpoint == connectedEndpoint) {
          _onCustomerDisconnected();
        } else if (profile?.role == AppRole.shopkeeper) {
          // Drop only the failed shop-side mapping; queued events remain
          // pending and are retried by reconciliation.
          _shopConnectedPeers.remove(endpoint);
          _customerIdByEndpoint.remove(endpoint);
          _notifyReadyByEndpoint.remove(endpoint);
          _endpointByCustomerId.removeWhere(
            (customerId, mapped) => mapped == endpoint,
          );
          if (connectedEndpoint == endpoint) {
            connectedEndpoint = _shopConnectedPeers.isEmpty
                ? null
                : _shopConnectedPeers.first;
          }
          notifyListeners();
        }
      }
    });
    return completer.future;
  }

  Future<void> _sendNow(String endpoint, List<int> payload) async {
    final maximum = await _transport.maxFrameBytes(endpoint);
    final chunkSize = (maximum - 16).clamp(1, 505);
    final frames = _codec.encode(
      transferId: _transferId++ & 0xffff,
      payload: Uint8List.fromList(payload),
      maxChunkPayloadBytes: chunkSize,
    );
    for (final frame in frames) {
      await _transport.send(endpoint, frame);
    }
  }

  // ---------------------------------------------------------------------------
  // Sync protocol
  // ---------------------------------------------------------------------------

  Map<String, Object?> _cursorFor(String profileId, String stream) {
    return AppDatabase.instance.peerCursor(
          profileId,
          _targetShopId ?? '',
          stream,
        ) ??
        const {'updatedAt': 0, 'version': 0, 'recordId': ''};
  }

  void _handleMessage(String endpoint, Map<String, dynamic> message) {
    if (isSyncEnvelope(Map<String, Object?>.from(message))) {
      _handleEnvelope(endpoint, message);
      return;
    }
    switch (message['type']) {
      case 'hello':
        final customerId = message['profileId'] as String?;
        if (customerId != null) {
          _replaceCustomerEndpoint(customerId, endpoint);
          debugPrint('Nearby hello from customer $customerId on $endpoint');
          final profile = AppDatabase.instance.activeProfile();
          if (profile?.role == AppRole.shopkeeper) {
            AppDatabase.instance.upsertCustomerReplica(
              ownerProfileId: profile!.id,
              uuid: customerId,
              sourceProfileId: customerId,
              name: (message['customerName'] as String?)?.trim().isEmpty == true
                  ? 'Customer'
                  : (message['customerName'] as String? ?? 'Customer'),
              version: 1,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
            notifyListeners();
          }
          if (_notifyReadyByEndpoint[endpoint] == true) {
            unawaited(_sendQueuedForPeer(endpoint, customerId));
          }
        }
        break;
      case 'catalog_request':
        unawaited(_sendCatalog(endpoint));
        break;
      case 'catalog_changed':
        final revision = message['revision'] as int? ?? 0;
        if (revision > currentCatalogRevision) {
          unawaited(_requestCatalog(endpoint));
        }
        break;
      case 'catalog':
        _receiveCatalog(message);
        unawaited(_sendPendingOrders(endpoint));
        break;
      case 'order_create':
        unawaited(_receiveOrder(endpoint, message));
        break;
      case 'order_ack':
        _receiveOrderAck(message);
        break;
      case 'order_status':
        unawaited(_receiveOrderStatus(endpoint, message));
        break;
      case 'status_ack':
        final eventId = message['eventId'] as String?;
        if (eventId != null) {
          AppDatabase.instance.removeSyncPayload(eventId);
          _scheduleStatusReconcile();
        }
        break;
      case 'customer_buzz':
        unawaited(_receiveCustomerBuzz(endpoint, message));
        break;
      case 'customer_buzz_ack':
        final eventId = message['eventId'] as String?;
        if (eventId != null) {
          _pendingBuzzAcks
              .remove(eventId)
              ?.complete(message['accepted'] == true);
        }
        break;
      case 'customer_buzz_stop':
        unawaited(_receiveCustomerBuzzStop(message));
        break;
      case 'customer_buzz_response':
        _receiveCustomerBuzzResponse(message);
        break;
      case 'sync_request':
        final customerId = message['customerId'] as String?;
        if (customerId != null) {
          _replaceCustomerEndpoint(customerId, endpoint);
          if (_notifyReadyByEndpoint[endpoint] == true) {
            unawaited(_sendQueuedForPeer(endpoint, customerId));
          }
          unawaited(_sendOrderSnapshots(endpoint, customerId));
        }
        break;
      case 'delta_pull':
        unawaited(_serveDeltaPull(endpoint, message));
        break;
      case 'delta':
        unawaited(_applyDelta(endpoint, message));
        break;
      case 'delta_ack':
        _applyDeltaAck(message);
        break;
    }
  }

  /// Serves a pull-based delta for `statuses` (shop side) and `orders`
  /// (customer side). Responses are ordered, bounded, and idempotent.
  Future<void> _serveDeltaPull(
    String endpoint,
    Map<String, dynamic> message,
  ) async {
    final profile = AppDatabase.instance.activeProfile();
    if (profile == null) return;
    final stream = message['stream'] as String? ?? '';
    final afterUpdatedAt = message['afterUpdatedAt'] as int? ?? 0;
    final afterVersion = message['afterVersion'] as int? ?? 0;
    final afterRecordId = message['afterRecordId'] as String? ?? '';
    if (stream == 'statuses' && profile.role == AppRole.shopkeeper) {
      final customerId = message['customerId'] as String? ?? '';
      final rows = AppDatabase.instance.statusDeltas(
        ownerProfileId: profile.id,
        customerId: customerId,
        afterUpdatedAt: afterUpdatedAt,
        afterVersion: afterVersion,
        afterRecordId: afterRecordId,
      );
      await _sendDeltaBatch(
        endpoint,
        stream: stream,
        rows: rows,
        toRecord: (row) => {
          'eventId': 'status-${row['id']}',
          'orderId': row['order_id'],
          'customerId': row['customer_id'],
          'shopId': row['shop_id'],
          'status': row['status'],
          'pickupAt': row['pickup_at'],
          'shareStatus': (row['share_status'] as int) == 1,
          'chatEnabled': (row['chat_enabled'] as int) == 1,
          'version': row['version'],
          'updatedAt': row['updated_at'],
        },
      );
    } else if (stream == 'orders' && profile.role == AppRole.customer) {
      final shopId = message['shopId'] as String? ?? '';
      final rows = AppDatabase.instance.orderDeltas(
        ownerProfileId: profile.id,
        shopId: shopId,
        afterUpdatedAt: afterUpdatedAt,
        afterVersion: afterVersion,
        afterRecordId: afterRecordId,
      );
      await _sendDeltaBatch(
        endpoint,
        stream: stream,
        rows: rows,
        toRecord: (row) => {
          'eventId': 'order-${row['id']}',
          'orderId': row['id'],
          'customerId': row['customer_id'],
          'shopId': row['shop_id'],
          'status': row['status'],
          'total': row['total'],
          'version': row['version'],
          'updatedAt': row['updated_at'],
        },
      );
    }
  }

  Future<void> _sendDeltaBatch(
    String endpoint, {
    required String stream,
    required List<Map<String, Object?>> rows,
    required Map<String, Object?> Function(Map<String, Object?> row) toRecord,
  }) async {
    const limit = 50;
    final page = rows.take(limit).toList();
    final records = page.map(toRecord).toList();
    final hasMore = rows.length > page.length;
    final highWater = page.isEmpty
        ? {'updatedAt': 0, 'version': 0, 'recordId': ''}
        : {
            'updatedAt': page.last['updated_at'],
            'version': page.last['version'],
            'recordId': page.last['id'],
          };
    await _send(endpoint, {
      'type': 'delta',
      'stream': stream,
      'records': records,
      'highWater': highWater,
      'hasMore': hasMore,
    });
  }

  /// Applies a delta batch transactionally, advances the peer cursor, and
  /// ACKs the committed high-water mark. Retries resend the same range.
  Future<void> _applyDelta(
    String endpoint,
    Map<String, dynamic> message,
  ) async {
    final profile = AppDatabase.instance.activeProfile();
    if (profile == null) return;
    final stream = message['stream'] as String? ?? '';
    final records = (message['records'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList();
    final highWater =
        (message['highWater'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        <String, dynamic>{};
    var applied = 0;
    for (final record in records) {
      if (stream == 'statuses' && profile.role == AppRole.customer) {
        final ok = AppDatabase.instance.applyRemoteStatusEvent(
          ownerProfileId: profile.id,
          peerId: endpoint,
          eventId: 'delta-${record['eventId']}',
          orderId: record['orderId'] as String,
          status: record['status'] as String,
          version: record['version'] as int? ?? 0,
          pickupAt: record['pickupAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(record['pickupAt'] as int),
          shareStatus: record['shareStatus'] as bool? ?? true,
          chatEnabled: record['chatEnabled'] as bool? ?? true,
          updatedAt: record['updatedAt'] as int? ?? 0,
          payloadHash: AppDatabase.syncPayloadHash(jsonEncode(record)),
        );
        if (ok) applied++;
      }
    }
    final peerKey = stream == 'statuses'
        ? (records.isEmpty ? null : records.first['customerId'] as String?)
        : null;
    AppDatabase.instance.setPeerCursor(
      localProfileId: profile.id,
      peerId: (peerKey ?? _customerIdByEndpoint[endpoint] ?? endpoint)
          .toString(),
      stream: stream,
      updatedAt: (highWater['updatedAt'] as int?) ?? 0,
      version:
          (highWater['updatedAt'] as int?) != null &&
              ((highWater['updatedAt'] as int?) ?? 0) > 0
          ? ((highWater['version'] as int?) ?? 0)
          : 0,
      recordId: (highWater['recordId'] as String?) ?? '',
    );
    lastSyncedAt = DateTime.now();
    notifyListeners();
    await _send(endpoint, {
      'type': 'delta_ack',
      'stream': stream,
      'applied': applied,
      'highWater': highWater,
      'hasMore': message['hasMore'] == true,
    });
    if (message['hasMore'] == true) {
      await _send(endpoint, {
        'type': 'delta_pull',
        'stream': stream,
        'afterUpdatedAt': highWater['updatedAt'] ?? 0,
        'afterVersion': highWater['version'] ?? 0,
        'afterRecordId': highWater['recordId'] ?? '',
      });
    }
  }

  void _applyDeltaAck(Map<String, dynamic> message) {
    final profile = AppDatabase.instance.activeProfile();
    if (profile == null) return;
    final highWater =
        (message['highWater'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        <String, dynamic>{};
    AppDatabase.instance.setPeerCursor(
      localProfileId: profile.id,
      peerId: _targetShopId ?? connectedShopId ?? '',
      stream: (message['stream'] as String?) ?? '',
      updatedAt: (highWater['updatedAt'] as int?) ?? 0,
      version: (highWater['version'] as int?) ?? 0,
      recordId: (highWater['recordId'] as String?) ?? '',
    );
    notifyListeners();
  }

  void _handleEnvelope(String endpoint, Map<String, dynamic> json) {
    try {
      final envelope = SyncEnvelope.fromJson(Map<String, Object?>.from(json));
      if (envelope.protocolVersion != _protocolVersion) return;
      final payload = Map<String, dynamic>.from(envelope.payload);
      payload['eventId'] = envelope.messageId;
      payload['version'] = envelope.entityVersion;
      payload['type'] = envelope.kind;
      _handleMessage(endpoint, payload);
    } catch (error) {
      debugPrint('Ignored invalid sync envelope: $error');
    }
  }

  void _replaceCustomerEndpoint(String customerId, String endpoint) {
    final previous = _endpointByCustomerId[customerId];
    if (previous != null && previous != endpoint) {
      _customerIdByEndpoint.remove(previous);
      _notifyReadyByEndpoint.remove(previous);
      if (connectedEndpoint == previous) connectedEndpoint = endpoint;
      unawaited(_transport.disconnectPeer(previous).catchError((_) {}));
      debugPrint('Nearby replaced stale endpoint $previous with $endpoint');
    }
    _endpointByCustomerId[customerId] = endpoint;
    _customerIdByEndpoint[endpoint] = customerId;
  }

  Future<void> _sendCatalog(String endpoint) async {
    final profile = AppDatabase.instance.activeProfile();
    final shop = profile == null
        ? null
        : AppDatabase.instance.shopForProfile(profile.id);
    if (shop == null) return;
    await _send(endpoint, {
      'type': 'catalog',
      'shopId': shop.id,
      'shopName': shop.name,
      'revision': shop.catalogRevision,
      'products': AppDatabase.instance
          .publishedProducts()
          .map(
            (product) => {
              'id': product.id,
              'uuid': product.uuid,
              'name': product.name,
              'description': product.description,
              'category': product.category,
              'price': product.price,
              'available': product.isAvailable,
              'version': product.version,
            },
          )
          .toList(),
    });
  }

  void _receiveCatalog(Map<String, dynamic> message) {
    final incomingShopId = message['shopId'] as String?;
    if (incomingShopId == null ||
        (_targetShopId != null &&
            !_shopIdsMatch(_targetShopId!, incomingShopId))) {
      debugPrint('Ignored catalog for a shop that is no longer targeted');
      return;
    }
    final revision = message['revision'] as int? ?? 1;
    if (revision < currentCatalogRevision) return;
    final products = (message['products'] as List<dynamic>? ?? []).map((item) {
      final map = item as Map<String, dynamic>;
      return ProductRecord(
        id: map['id'] as int?,
        uuid: map['uuid'] as String? ?? '',
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        category: map['category'] as String? ?? 'General',
        price: (map['price'] as num).toDouble(),
        isAvailable: map['available'] as bool? ?? true,
        isPublished: true,
        version: map['version'] as int? ?? 1,
      );
    }).toList();
    connectedShopId = incomingShopId;
    connectedShopName = message['shopName'] as String;
    if (_targetShopId != null) {
      _shopTokenByFullId[connectedShopId!] = _targetShopId!;
      _targetShopId = _shopTokenByFullId[connectedShopId!];
    }
    currentCatalogRevision = revision;
    currentCatalog = products;
    lastSyncedAt = DateTime.now();
    activity = NearbyActivity.connected;
    errorMessage = null;
    final customer = _customer;
    if (customer != null) {
      AppDatabase.instance.saveCatalogCache(
        ownerProfileId: customer.id,
        shopId: connectedShopId!,
        shopName: connectedShopName!,
        revision: revision,
        payload: jsonEncode(message),
      );
    }
    onCatalog?.call(connectedShopId!, connectedShopName!, products);
    notifyListeners();
  }

  Future<String> submitOrder({
    required LocalProfile customer,
    required String shopId,
    required String shopName,
    required List<CartLine> lines,
    String note = '',
  }) async {
    const uuid = ids.Uuid();
    final now = DateTime.now();
    final orderId = uuid.v4();
    final total = lines.fold<double>(0, (sum, line) => sum + line.total);
    final order = LocalOrderRecord(
      id: orderId,
      ownerProfileId: customer.id,
      sourceProfileId: customer.id,
      shopId: shopId,
      shopName: shopName,
      customerId: customer.id,
      customerName: customer.displayName,
      status: 'waiting_to_send',
      total: total,
      createdAt: now,
      updatedAt: now,
      shareStatus: true,
      chatEnabled: true,
      note: note,
      // Delivery is tracked by status; sync_status is reserved for delta sync.
      syncStatus: 'pending',
    );
    final items = lines
        .map(
          (line) => LocalOrderItemRecord(
            id: uuid.v4(),
            orderId: orderId,
            ownerProfileId: customer.id,
            productId: line.product.id?.toString(),
            productName: line.product.name,
            quantity: line.quantity,
            unitPrice: line.product.price,
            total: line.total,
          ),
        )
        .toList();
    AppDatabase.instance.saveLocalOrder(order, items);
    unawaited(
      NotificationService.instance.startNearbyService(
        'Keeping your active order connected',
      ),
    );
    if (connected && connectedShopId == shopId) {
      await _sendOrder(connectedEndpoint!, order, items);
    } else {
      // Cached shops may outlive this process, so rebuild the advertised token
      // when the full shop id has not been seen in the current session.
      _targetShopId = _shopTokenByFullId[shopId] ?? _shopToken(shopId);
      _targetShopName = shopName;
      _customer = customer;
      _scheduleReconnect(immediate: true);
    }
    notifyListeners();
    return orderId;
  }

  Future<void> _sendPendingOrders(String endpoint) async {
    final customer = _customer;
    if (customer == null) return;
    for (final order
        in AppDatabase.instance
            .unsentOrdersForProfile(customer.id)
            .where((order) => order.shopId == connectedShopId)) {
      await _sendOrder(
        endpoint,
        order,
        AppDatabase.instance.orderItems(customer.id, order.id),
      );
    }
  }

  Future<void> _sendOrder(
    String endpoint,
    LocalOrderRecord order,
    List<LocalOrderItemRecord> items,
  ) => _send(endpoint, {
    'type': 'order_create',
    'eventId': order.id,
    'orderId': order.id,
    'shopId': order.shopId,
    'shopName': order.shopName,
    'customerId': order.customerId,
    'customerName': order.customerName,
    'total': order.total,
    'note': order.note,
    'version': order.version,
    'createdAt': order.createdAt.millisecondsSinceEpoch,
    'items': items
        .map(
          (item) => {
            'id': item.id,
            'productId': item.productId,
            'name': item.productName,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'total': item.total,
          },
        )
        .toList(),
  });

  Future<void> _receiveOrder(
    String endpoint,
    Map<String, dynamic> message,
  ) async {
    final profile = AppDatabase.instance.activeProfile();
    final shop = profile == null
        ? null
        : AppDatabase.instance.shopForProfile(profile.id);
    if (profile == null || shop == null || message['shopId'] != shop.id) return;
    final orderId = message['orderId'] as String;
    final customerId = message['customerId'] as String;
    _replaceCustomerEndpoint(customerId, endpoint);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      message['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
    final order = LocalOrderRecord(
      id: orderId,
      ownerProfileId: profile.id,
      sourceProfileId: customerId,
      version: 1,
      shopId: shop.id,
      shopName: shop.name,
      customerId: customerId,
      customerName: message['customerName'] as String,
      status: 'pending',
      total: (message['total'] as num).toDouble(),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      shareStatus: shop.statusEnabled,
      chatEnabled: shop.chatEnabled,
      note: message['note'] as String? ?? '',
    );
    final items = (message['items'] as List<dynamic>).map((value) {
      final item = value as Map<String, dynamic>;
      return LocalOrderItemRecord(
        id: item['id'] as String,
        orderId: orderId,
        ownerProfileId: profile.id,
        productId: item['productId'] as String?,
        productName: item['name'] as String,
        quantity: item['quantity'] as int,
        unitPrice: (item['unitPrice'] as num).toDouble(),
        total: (item['total'] as num).toDouble(),
      );
    }).toList();
    final applied = AppDatabase.instance.recordRemoteOrderCreate(
      ownerProfileId: profile.id,
      peerId: customerId,
      eventId: orderId,
      order: order,
      items: items,
      payloadHash: AppDatabase.syncPayloadHash(jsonEncode(message)),
    );
    if (applied) {
      unawaited(NotificationService.instance.showNewOrder(order));
      notifyListeners();
    }
    await _send(endpoint, {
      'type': 'order_ack',
      'orderId': orderId,
      'status': 'pending',
    });
  }

  void _receiveOrderAck(Map<String, dynamic> message) {
    final customer = _customer;
    if (customer == null) return;
    final existing = AppDatabase.instance.orderForProfile(
      customer.id,
      message['orderId'] as String,
    );
    if (existing == null || existing.status != 'waiting_to_send') return;
    AppDatabase.instance.acknowledgeLocalOrder(
      profileId: customer.id,
      orderId: message['orderId'] as String,
      status: message['status'] as String? ?? 'pending',
    );
    final order = AppDatabase.instance.orderForProfile(
      customer.id,
      message['orderId'] as String,
    );
    if (order != null) {
      unawaited(NotificationService.instance.showOrderUpdate(order));
    }
    notifyListeners();
  }

  Future<void> updateOrderStatus({
    required LocalOrderRecord order,
    required String status,
    DateTime? pickupAt,
    required bool shareStatus,
    required bool chatEnabled,
  }) async {
    if (!isBuzzEligibleStatus(status) &&
        order.buzzEventId != null &&
        order.buzzStoppedAt == null &&
        order.buzzEndsAt?.isAfter(DateTime.now()) == true) {
      await stopCustomerBuzz(order);
    }
    final profile = AppDatabase.instance.activeProfile();
    if (profile?.role != AppRole.shopkeeper) return;
    const uuid = ids.Uuid();
    final eventId = uuid.v4();
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    final message = AppDatabase.instance.recordOrderStatusEvent(
      ownerProfileId: profile!.id,
      orderId: order.id,
      eventId: eventId,
      peerId: order.customerId,
      status: status,
      pickupAt: pickupAt,
      shareStatus: shareStatus,
      chatEnabled: chatEnabled,
      updatedAt: updatedAt,
    );
    notifyListeners();
    final endpoint = _readyEndpointForCustomer(order.customerId);
    if (endpoint != null) {
      try {
        debugPrint('Nearby sending status $status for order ${order.id}');
        await _send(endpoint, Map<String, dynamic>.from(message));
      } catch (error) {
        debugPrint('Nearby status send failed for order ${order.id}: $error');
        AppDatabase.instance.markSyncAttempt(eventId, '$error');
        _scheduleStatusReconcile();
      }
    } else {
      debugPrint('Nearby status queued for order ${order.id}');
      _scheduleStatusReconcile();
    }
    _scheduleStatusReconcile();
  }

  Future<CustomerBuzzResult> buzzCustomer(LocalOrderRecord order) async {
    final profile = AppDatabase.instance.activeProfile();
    if (profile?.role != AppRole.shopkeeper ||
        order.ownerProfileId != profile!.id ||
        !isBuzzEligibleStatus(order.status)) {
      return CustomerBuzzResult.invalidOrder;
    }
    final endpoint = _readyEndpointForCustomer(order.customerId);
    if (endpoint == null) return CustomerBuzzResult.unavailable;

    final reservedAt = DateTime.now();
    final eventId = const ids.Uuid().v4();
    final reserved = AppDatabase.instance.reserveOrderBuzz(
      profileId: profile.id,
      orderId: order.id,
      eventId: eventId,
      now: reservedAt,
    );
    if (!reserved) return CustomerBuzzResult.cooldown;

    final completer = Completer<bool>();
    _pendingBuzzAcks[eventId] = completer;
    try {
      await _send(endpoint, {
        'type': 'customer_buzz',
        'eventId': eventId,
        'orderId': order.id,
        'customerId': order.customerId,
        'shopId': order.shopId,
        'shopName': order.shopName,
        'sentAt': reservedAt.millisecondsSinceEpoch,
        'endsAt': reservedAt
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
    } catch (error) {
      _pendingBuzzAcks.remove(eventId);
      AppDatabase.instance.releaseOrderBuzz(
        profileId: profile.id,
        orderId: order.id,
        eventId: eventId,
      );
      debugPrint('Customer buzz send failed for order ${order.id}: $error');
      notifyListeners();
      return CustomerBuzzResult.sendFailed;
    }
    notifyListeners();
    try {
      final accepted = await completer.future.timeout(
        const Duration(seconds: 5),
      );
      return accepted
          ? CustomerBuzzResult.delivered
          : CustomerBuzzResult.deliveryUnconfirmed;
    } on TimeoutException {
      return CustomerBuzzResult.deliveryUnconfirmed;
    } finally {
      _pendingBuzzAcks.remove(eventId);
    }
  }

  Future<CustomerBuzzStopResult> stopCustomerBuzz(
    LocalOrderRecord order,
  ) async {
    final profile = AppDatabase.instance.activeProfile();
    final eventId = order.buzzEventId;
    if (profile?.role != AppRole.shopkeeper || eventId == null) {
      return CustomerBuzzStopResult.alreadyEnded;
    }
    final stoppedAt = DateTime.now();
    final stopped = AppDatabase.instance.stopOrderBuzz(
      profileId: profile!.id,
      orderId: order.id,
      eventId: eventId,
      stoppedAt: stoppedAt,
    );
    if (!stopped) return CustomerBuzzStopResult.alreadyEnded;
    notifyListeners();
    final endpoint = _readyEndpointForCustomer(order.customerId);
    if (endpoint == null) return CustomerBuzzStopResult.customerUnavailable;
    try {
      await _send(endpoint, {
        'type': 'customer_buzz_stop',
        'eventId': eventId,
        'orderId': order.id,
      });
      return CustomerBuzzStopResult.delivered;
    } catch (error) {
      debugPrint('Customer buzz stop failed for order ${order.id}: $error');
      return CustomerBuzzStopResult.customerUnavailable;
    }
  }

  Future<void> respondToCustomerBuzz(String eventId) async {
    final event = _activeCustomerBuzz;
    await BuzzVibrationService.instance.stop(eventId: eventId);
    await NotificationService.instance.cancelCustomerBuzz(eventId);
    if (event == null || event.eventId != eventId) return;
    _customerBuzzExpiryTimer?.cancel();
    _customerBuzzExpiryTimer = null;
    final endpoint = _activeCustomerBuzzEndpoint;
    _activeCustomerBuzz = null;
    _activeCustomerBuzzEndpoint = null;
    _buzzStopController.add(eventId);
    if (endpoint != null) {
      try {
        await _send(endpoint, {
          'type': 'customer_buzz_response',
          'eventId': eventId,
          'orderId': event.orderId,
        });
      } catch (error) {
        debugPrint('Customer buzz response failed: $error');
      }
    }
  }

  Future<void> _receiveCustomerBuzz(
    String endpoint,
    Map<String, dynamic> message,
  ) async {
    final customer = _customer;
    final eventId = message['eventId'] as String?;
    final orderId = message['orderId'] as String?;
    var accepted = false;
    if (customer != null &&
        eventId != null &&
        orderId != null &&
        message['customerId'] == customer.id) {
      final order = AppDatabase.instance.orderForProfile(customer.id, orderId);
      if (order != null &&
          order.shopId == message['shopId'] &&
          isBuzzEligibleStatus(order.status)) {
        final sentAt = DateTime.fromMillisecondsSinceEpoch(
          message['sentAt'] as int? ?? 0,
        );
        final endsAt = DateTime.fromMillisecondsSinceEpoch(
          message['endsAt'] as int? ?? 0,
        );
        if (isBuzzMessageCurrent(
          now: DateTime.now(),
          sentAt: sentAt,
          endsAt: endsAt,
        )) {
          accepted = true;
          final firstDelivery = AppDatabase.instance.claimIncomingBuzz(
            eventId: eventId,
            peerId: connectedShopId ?? endpoint,
            orderId: orderId,
            payloadHash: AppDatabase.syncPayloadHash(jsonEncode(message)),
          );
          if (!firstDelivery) {
            await _sendCustomerBuzzAck(endpoint, eventId, orderId, true);
            return;
          }
          final event = CustomerBuzzEvent(
            eventId: eventId,
            orderId: orderId,
            shopId: order.shopId,
            shopName: order.shopName,
            sentAt: sentAt,
            endsAt: endsAt,
          );
          final previous = _activeCustomerBuzz;
          if (previous != null && previous.eventId != eventId) {
            await BuzzVibrationService.instance.stop(eventId: previous.eventId);
            await NotificationService.instance.cancelCustomerBuzz(
              previous.eventId,
            );
            _buzzStopController.add(previous.eventId);
          }
          _activeCustomerBuzz = event;
          _activeCustomerBuzzEndpoint = endpoint;
          _customerBuzzExpiryTimer?.cancel();
          _customerBuzzExpiryTimer = Timer(
            event.endsAt.difference(DateTime.now()),
            () => unawaited(_expireCustomerBuzz(eventId)),
          );
          unawaited(BuzzVibrationService.instance.start(eventId: eventId));
          unawaited(NotificationService.instance.showCustomerBuzz(event));
          if (_foreground) _buzzController.add(event);
        }
      }
    }
    if (eventId != null) {
      await _sendCustomerBuzzAck(endpoint, eventId, orderId, accepted);
    }
  }

  Future<void> _sendCustomerBuzzAck(
    String endpoint,
    String eventId,
    String? orderId,
    bool accepted,
  ) => _send(endpoint, {
    'type': 'customer_buzz_ack',
    'eventId': eventId,
    'orderId': orderId,
    'accepted': accepted,
  });

  Future<void> _receiveCustomerBuzzStop(Map<String, dynamic> message) async {
    final eventId = message['eventId'] as String?;
    final event = _activeCustomerBuzz;
    if (eventId == null || event == null || event.eventId != eventId) return;
    await BuzzVibrationService.instance.stop(eventId: eventId);
    await NotificationService.instance.cancelCustomerBuzz(eventId);
    _customerBuzzExpiryTimer?.cancel();
    _customerBuzzExpiryTimer = null;
    _activeCustomerBuzz = null;
    _activeCustomerBuzzEndpoint = null;
    _buzzStopController.add(eventId);
  }

  Future<void> _expireCustomerBuzz(String eventId) async {
    final event = _activeCustomerBuzz;
    if (event == null || event.eventId != eventId) return;
    await BuzzVibrationService.instance.stop(eventId: eventId);
    await NotificationService.instance.cancelCustomerBuzz(eventId);
    _activeCustomerBuzz = null;
    _activeCustomerBuzzEndpoint = null;
    _customerBuzzExpiryTimer = null;
    _buzzStopController.add(eventId);
  }

  void _receiveCustomerBuzzResponse(Map<String, dynamic> message) {
    final profile = AppDatabase.instance.activeProfile();
    final eventId = message['eventId'] as String?;
    final orderId = message['orderId'] as String?;
    if (profile?.role != AppRole.shopkeeper ||
        eventId == null ||
        orderId == null) {
      return;
    }
    AppDatabase.instance.stopOrderBuzz(
      profileId: profile!.id,
      orderId: orderId,
      eventId: eventId,
      stoppedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> _receiveOrderStatus(
    String endpoint,
    Map<String, dynamic> message,
  ) async {
    final customer = _customer;
    if (customer == null || message['customerId'] != customer.id) return;
    final applied = AppDatabase.instance.applyRemoteStatusEvent(
      ownerProfileId: customer.id,
      peerId: connectedShopId ?? endpoint,
      eventId: message['eventId'] as String,
      orderId: message['orderId'] as String,
      status: message['status'] as String,
      version: message['version'] as int? ?? 0,
      pickupAt: message['pickupAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(message['pickupAt'] as int),
      shareStatus: message['shareStatus'] as bool? ?? true,
      chatEnabled: message['chatEnabled'] as bool? ?? true,
      updatedAt: message['updatedAt'] as int? ?? 0,
      payloadHash: AppDatabase.syncPayloadHash(jsonEncode(message)),
    );
    if (applied) {
      lastSyncedAt = DateTime.now();
      final updated = AppDatabase.instance.orderForProfile(
        customer.id,
        message['orderId'] as String,
      );
      if (updated != null && updated.shareStatus) {
        unawaited(NotificationService.instance.showOrderUpdate(updated));
      }
      notifyListeners();
    }
    await _send(endpoint, {
      'type': 'status_ack',
      'eventId': message['eventId'],
      'orderId': message['orderId'] as String,
      'version': message['version'],
    });
  }

  Future<void> _sendQueuedForPeer(String endpoint, String peerId) async {
    if (_notifyReadyByEndpoint[endpoint] != true) return;
    await _sendLatestQueuedStatuses(endpoint, peerId);
    _scheduleStatusReconcile();
  }

  String? _readyEndpointForCustomer(String customerId) {
    final endpoint = _endpointByCustomerId[customerId];
    if (endpoint == null) return null;
    if (!_connectedPeer(endpoint)) return null;
    if (_notifyReadyByEndpoint[endpoint] != true) return null;
    return endpoint;
  }

  bool _connectedPeer(String endpoint) => true;

  Future<void> _sendOrderSnapshots(String endpoint, String customerId) async {
    final profile = AppDatabase.instance.activeProfile();
    if (profile?.role != AppRole.shopkeeper) return;
    for (final order in AppDatabase.instance.ordersForProfile(profile!.id)) {
      if (order.customerId != customerId) continue;
      await _send(endpoint, {
        'type': 'order_status',
        'eventId': 'snapshot-${order.id}-${order.version}',
        'orderId': order.id,
        'customerId': order.customerId,
        'shopId': order.shopId,
        'status': order.status,
        'pickupAt': order.pickupAt?.millisecondsSinceEpoch,
        'shareStatus': order.shareStatus,
        'chatEnabled': order.chatEnabled,
        'version': order.version,
        'updatedAt': order.updatedAt.millisecondsSinceEpoch,
      });
    }
  }

  void _scheduleStatusReconcile() {
    if (!supported || _reconciling) return;
    _reconcileTimer?.cancel();
    _reconcileTimer = Timer(const Duration(seconds: 20), () async {
      if (_reconciling || !supported) return;
      _reconciling = true;
      try {
        final profile = AppDatabase.instance.activeProfile();
        if (profile?.role != AppRole.shopkeeper) return;
        for (final customerId in _endpointByCustomerId.keys.toSet()) {
          final endpoint = _readyEndpointForCustomer(customerId);
          if (endpoint != null) {
            await _sendLatestQueuedStatuses(endpoint, customerId);
          }
        }
      } finally {
        _reconciling = false;
        final hasPending = _endpointByCustomerId.keys.any(
          (customerId) =>
              AppDatabase.instance.queuedSyncPayloads(customerId).isNotEmpty,
        );
        if (hasPending) _scheduleStatusReconcile();
      }
    });
  }

  Future<void> _sendLatestQueuedStatuses(
    String endpoint,
    String customerId,
  ) async {
    final queued = AppDatabase.instance.queuedSyncPayloads(customerId);
    final latestByOrder = <String, Map<String, dynamic>>{};
    for (final item in queued) {
      try {
        final decoded = jsonDecode(item['payload']! as String);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['type'] != 'order_status') {
          await _send(endpoint, decoded);
          continue;
        }
        final orderId = decoded['orderId'] as String;
        final updatedAt = decoded['updatedAt'] as int? ?? 0;
        final current = latestByOrder[orderId];
        final currentUpdated = current?['updatedAt'] as int? ?? -1;
        if (updatedAt >= currentUpdated) {
          if (current != null) {
            AppDatabase.instance.removeSyncPayload(
              current['eventId'] as String,
            );
          }
          latestByOrder[orderId] = decoded;
        } else {
          AppDatabase.instance.removeSyncPayload(decoded['eventId'] as String);
        }
      } catch (error) {
        AppDatabase.instance.markSyncAttempt(item['id']! as String, '$error');
      }
    }
    for (final message in latestByOrder.values) {
      try {
        debugPrint(
          'Nearby retrying status ${message['status']} for order ${message['orderId']}',
        );
        await _send(endpoint, message);
      } catch (error) {
        debugPrint(
          'Nearby status retry failed for order ${message['orderId']}: $error',
        );
        AppDatabase.instance.markSyncAttempt(
          message['eventId'] as String,
          '$error',
        );
      }
    }
  }

  Future<void> resendPendingStatuses(String customerId) async {
    final endpoint = _readyEndpointForCustomer(customerId);
    if (endpoint == null) {
      _scheduleStatusReconcile();
      return;
    }
    await _sendLatestQueuedStatuses(endpoint, customerId);
    _scheduleStatusReconcile();
  }

  bool hasPendingStatusForCustomer(String customerId) =>
      AppDatabase.instance.queuedSyncPayloads(customerId).isNotEmpty;

  Future<void> _pullStatusDeltas() async {
    final customer = _customer;
    final endpoint = connectedEndpoint;
    if (customer == null || endpoint == null || !connected) return;
    final cursor =
        AppDatabase.instance.peerCursor(
          customer.id,
          connectedShopId ?? '',
          'statuses',
        ) ??
        const {'updatedAt': 0, 'version': 0, 'recordId': ''};
    try {
      await _send(endpoint, {
        'type': 'delta_pull',
        'stream': 'statuses',
        'customerId': customer.id,
        'afterUpdatedAt': cursor['updatedAt'] ?? 0,
        'afterVersion': cursor['version'] ?? 0,
        'afterRecordId': cursor['recordId'] ?? '',
      });
    } catch (error) {
      debugPrint('Status delta pull failed: $error');
    }
  }

  Future<void> requestStatusSync() async {
    final customer = _customer;
    final endpoint = connectedEndpoint;
    if (customer == null || endpoint == null || !connected) return;
    final orderIds = AppDatabase.instance
        .ordersForProfile(customer.id)
        .where((order) => order.shopId == connectedShopId)
        .map((order) => order.id)
        .toList();
    if (orderIds.isEmpty) return;
    try {
      await _send(endpoint, {
        'type': 'sync_request',
        'customerId': customer.id,
        'orderIds': orderIds,
      });
    } catch (error) {
      debugPrint('Status sync request failed: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> stopDiscovery({bool manual = true}) async {
    if (manual) {
      _manualStop = true;
      _discoveryPaused = true;
    }
    ++_discoveryOperation;
    _engine.manualStop();
    _scanWindowTimer?.cancel();
    _reconnectTimer?.cancel();
    if (!connected) {
      activity = NearbyActivity.idle;
      notifyListeners();
    } else {
      // A connected customer can keep the session alive without continuing
      // discovery. The UI must be able to pause scanning independently.
      activity = NearbyActivity.connected;
      notifyListeners();
    }
    await _transport.stopDiscovery();
  }

  Future<void> stopAdvertising() async {
    _advertisingRecoveryTimer?.cancel();
    await _transport.stopAdvertising();
    if (_customerIdByEndpoint.isEmpty) {
      activity = NearbyActivity.idle;
      notifyListeners();
      await NotificationService.instance.stopNearbyService();
    }
  }

  Future<void> _handleWifiUnavailable() async {
    _manualStop = true;
    _engine.adapterChanged(powered: false);
    _cancelTransportTimers();
    await _shutdownTransport();
    _clearTransientPeers();
    activity = NearbyActivity.idle;
    errorMessage = 'Wi-Fi is off. Turn it on to use nearby features.';
    notifyListeners();
    await NotificationService.instance.stopNearbyService();
  }

  Future<void> pauseForBackground() async {
    _foreground = false;
    if (await _hasActiveBackgroundWork()) {
      _backgroundActive = true;
      final profile = AppDatabase.instance.activeProfile();
      await NotificationService.instance.startNearbyService(
        profile?.role == AppRole.shopkeeper
            ? 'Receiving nearby orders'
            : 'Keeping your active order connected',
      );
      return;
    }
    _backgroundActive = false;
    _engine.manualStop();
    _cancelTransportTimers();
    await _shutdownTransport();
    _clearTransientPeers();
    activity = NearbyActivity.idle;
    notifyListeners();
    await NotificationService.instance.stopNearbyService();
  }

  Future<void> resumeForForeground(LocalProfile profile) async {
    _foreground = true;
    _backgroundActive = false;
    await NotificationService.instance.stopNearbyService();
    if (profile.role == AppRole.customer &&
        _targetShopId != null &&
        !connected &&
        !_discoveryPaused) {
      _manualStop = false;
      await reconnectNow();
    } else if (profile.role == AppRole.customer &&
        _customer?.id == profile.id &&
        !_discoveryPaused &&
        (activity == NearbyActivity.discovering ||
            activity == NearbyActivity.connecting ||
            activity == NearbyActivity.syncing ||
            activity == NearbyActivity.connected)) {
      return;
    } else if (profile.role == AppRole.shopkeeper) {
      await _recoverShopAdvertising(profile: profile, immediate: true);
    }
  }

  Future<void> disconnect() async {
    _manualStop = true;
    _backgroundActive = false;
    _engine.manualStop();
    _targetShopId = null;
    _targetShopName = null;
    _customer = null;
    _cancelTransportTimers();
    await _shutdownTransport();
    _clearTransientPeers();
    connectedShopId = null;
    connectedShopName = null;
    activity = NearbyActivity.idle;
    notifyListeners();
    await NotificationService.instance.stopNearbyService();
  }

  Future<void> _shutdownTransport() async {
    try {
      await _transport.stopDiscovery().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _transport.stopAdvertising().timeout(const Duration(seconds: 2));
    } catch (_) {}
    final peers = <String>{
      ..._customerIdByEndpoint.keys,
      ..._shopConnectedPeers,
    };
    final activePeerId = _activePeerId;
    if (activePeerId != null) peers.add(activePeerId);
    for (final peer in peers) {
      try {
        await _transport
            .disconnectPeer(peer)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _activePeerId = null;
  }

  void _clearTransientPeers() {
    _qrMeshEndpoint = null;
    _customerIdByEndpoint.clear();
    _notifyReadyByEndpoint.clear();
    _endpointByCustomerId.clear();
    _shopsByShopId.clear();
    _legacyIncoming.clear();
    connectedEndpoint = null;
  }

  void _cancelTransportTimers() {
    _scanWindowTimer?.cancel();
    _connectionTimer?.cancel();
    _reconnectTimer?.cancel();
    _advertisingRecoveryTimer?.cancel();
    _reconcileTimer?.cancel();
    _reconciling = false;
  }

  Future<void> _recoverShopAdvertising({
    LocalProfile? profile,
    bool immediate = false,
  }) async {
    final activeProfile = profile ?? AppDatabase.instance.activeProfile();
    if (activeProfile?.role != AppRole.shopkeeper ||
        _shopConnectedPeers.isNotEmpty) {
      return;
    }
    final shop = AppDatabase.instance.shopForProfile(activeProfile!.id);
    if (shop?.visible != true) return;

    _advertisingRecoveryTimer?.cancel();
    if (immediate) {
      await startAdvertising(activeProfile, shop!);
      return;
    }

    final completer = Completer<void>();
    _advertisingRecoveryTimer = Timer(const Duration(milliseconds: 750), () {
      unawaited(() async {
        try {
          if (_shopConnectedPeers.isEmpty) {
            final currentProfile = AppDatabase.instance.activeProfile();
            final currentShop = currentProfile == null
                ? null
                : AppDatabase.instance.shopForProfile(currentProfile.id);
            if (currentProfile != null &&
                currentProfile.role == AppRole.shopkeeper &&
                currentShop?.visible == true) {
              await startAdvertising(currentProfile, currentShop!);
            }
          }
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      }());
    });
    await completer.future;
  }

  Future<bool> _hasActiveBackgroundWork() async {
    try {
      if (connectedEndpoint != null) return true;
      if (_targetShopId != null) return true;
      final profile = AppDatabase.instance.activeProfile();
      if (profile == null) return false;
      if (profile.role == AppRole.shopkeeper) {
        return AppDatabase.instance.shopForProfile(profile.id)?.visible == true;
      }
      return AppDatabase.instance.unsentOrdersForProfile(profile.id).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _setError(String message) {
    activity = NearbyActivity.error;
    errorMessage = message;
    notifyListeners();
  }

  String _shopToken(String shopId) =>
      shopId.replaceAll('-', '').substring(0, 8);

  String _shopKey(String shopId) => _shopToken(shopId).toLowerCase();

  List<int> _tokenBytes(String token) => List.generate(
    4,
    (index) => int.parse(token.substring(index * 2, index * 2 + 2), radix: 16),
  );

  List<int> _compactUtf8(String value, int maxBytes) {
    final result = <int>[];
    for (final rune in value.trim().runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (result.length + bytes.length > maxBytes) break;
      result.addAll(bytes);
    }
    return result;
  }
}
