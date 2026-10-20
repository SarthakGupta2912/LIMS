import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class CustomMeshState {
  const CustomMeshState({
    this.address,
    this.connectUri,
    this.hotspotEnabled = false,
    this.connectionState = 'disconnected',
    this.started = false,
    this.nodes = const [],
  });

  final String? address;
  final String? connectUri;
  final bool hotspotEnabled;
  final String connectionState;
  final bool started;
  final List<MeshNode> nodes;

  factory CustomMeshState.fromMap(Map<Object?, Object?> values) {
    return CustomMeshState(
      address: values['address'] as String?,
      connectUri: values['connectUri'] as String?,
      hotspotEnabled: values['hotspotEnabled'] as bool? ?? false,
      connectionState: values['connectionState'] as String? ?? 'disconnected',
      started: true,
      nodes: ((values['nodes'] as List?) ?? const [])
          .whereType<Map>()
          .map((node) => MeshNode.fromMap(Map<Object?, Object?>.from(node)))
          .toList(growable: false),
    );
  }
}

class MeshNode {
  const MeshNode({
    required this.address,
    required this.ping,
    required this.hops,
  });

  final int address;
  final int ping;
  final int hops;

  factory MeshNode.fromMap(Map<Object?, Object?> values) => MeshNode(
    address: values['address'] as int? ?? 0,
    ping: values['ping'] as int? ?? 0,
    hops: values['hops'] as int? ?? 0,
  );

  String get dottedAddress => [
    (address >>> 24) & 255,
    (address >>> 16) & 255,
    (address >>> 8) & 255,
    address & 255,
  ].join('.');
}

/// Controls manual QR/bootstrap setup for the Android mesh node.
class CustomMeshService extends ChangeNotifier {
  CustomMeshService._();

  static final instance = CustomMeshService._();
  static const _channel = MethodChannel('lims/custom_mesh');
  static const _events = EventChannel('lims/custom_mesh/events');
  static const _platform = MethodChannel('lims/platform');

  StreamSubscription<Object?>? _stateSubscription;
  CustomMeshState _state = const CustomMeshState();

  CustomMeshState get state => _state;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isWifiEnabled() async {
    if (!supported) return false;
    return await _platform.invokeMethod<bool>('isWifiEnabled') ?? false;
  }

  Future<bool> openWifiSettings() async {
    if (!supported) return false;
    return await _platform.invokeMethod<bool>('openWifiSettings') ?? false;
  }

  Future<CustomMeshState> start() async {
    if (!supported) {
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'Custom Mesh is currently available on Android only.',
      );
    }
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
    final sdkInt = await const MethodChannel(
      'lims/platform',
    ).invokeMethod<int>('sdkInt');
    if ((sdkInt ?? 33) >= 33) {
      permissions.add(Permission.nearbyWifiDevices);
    } else {
      permissions.add(Permission.locationWhenInUse);
    }
    final results = await permissions.request();
    final denied = results.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();
    if (denied.isNotEmpty) {
      final names = denied.map(_permissionName).join(', ');
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: '$names permission is required to start Custom Mesh.',
      );
    }
    _stateSubscription ??= _events.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        _update(Map<Object?, Object?>.from(event));
      }
    });
    final values = await _invoke('start');
    _update(values);
    return _state;
  }

  /// Requests the permissions needed by Meshrabiya's Wi-Fi bootstrap APIs.
  Future<bool> requestPermissions() async {
    if (!supported) return false;
    final sdkInt = await const MethodChannel(
      'lims/platform',
    ).invokeMethod<int>('sdkInt');
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if ((sdkInt ?? 33) >= 33)
        Permission.nearbyWifiDevices
      else
        Permission.locationWhenInUse,
    ];
    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }

  Future<List<Permission>> deniedPermissions() async {
    if (!supported) return const [];
    final sdkInt = await _platform.invokeMethod<int>('sdkInt');
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if ((sdkInt ?? 33) >= 33)
        Permission.nearbyWifiDevices
      else
        Permission.locationWhenInUse,
    ];
    final denied = <Permission>[];
    for (final permission in permissions) {
      if (!await permission.isGranted) denied.add(permission);
    }
    return denied;
  }

  Future<CustomMeshState> enableHotspot({
    String band = 'BAND_5GHZ',
    String hotspotType = 'AUTO',
  }) => _operation('enableHotspot', {'band': band, 'hotspotType': hotspotType});
  Future<CustomMeshState> disableHotspot() => _operation('disableHotspot');
  Future<CustomMeshState> disconnect() => _operation('disconnect');

  Future<String> qrNodeAddress(String uri) async {
    final address = await _channel.invokeMethod<String>('qrNodeAddress', {
      'uri': uri,
    });
    if (address == null) throw ArgumentError('The mesh QR has no node address');
    return address;
  }

  Future<CustomMeshState> connect(String uri) async {
    if (uri.trim().isEmpty) {
      throw ArgumentError('A mesh connect URI is required');
    }
    return _operation('connect', {'uri': uri.trim()});
  }

  Future<Map<Object?, Object?>> _invoke(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _channel.invokeMethod<Object?>(method, arguments);
    return result is Map
        ? Map<Object?, Object?>.from(result)
        : <Object?, Object?>{};
  }

  Future<CustomMeshState> _operation(String method, [Object? arguments]) async {
    final values = await _invoke(method, arguments);
    _update(values);
    return _state;
  }

  void _update(Map<Object?, Object?> values) {
    _state = CustomMeshState.fromMap(values);
    notifyListeners();
  }

  String _permissionName(Permission permission) {
    if (permission == Permission.bluetoothScan ||
        permission == Permission.bluetoothConnect) {
      return 'Bluetooth';
    }
    if (permission == Permission.nearbyWifiDevices) return 'Nearby Wi-Fi';
    if (permission == Permission.locationWhenInUse) return 'Location';
    return 'Device';
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    super.dispose();
  }
}
