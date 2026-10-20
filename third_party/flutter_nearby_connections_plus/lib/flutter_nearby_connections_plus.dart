// Exposes the package's peer discovery and messaging API while requiring its
// Wi-Fi Direct strategy. The Android implementation uses only WifiP2pManager.

library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

// ignore_for_file: constant_identifier_names

enum Strategy { P2P_CLUSTER, P2P_STAR, P2P_POINT_TO_POINT, Wi_Fi_P2P }

enum SessionState { notConnected, connecting, connected }

class Device {
  Device(this.deviceId, this.deviceName, int state)
      : state = SessionState.values[state.clamp(0, 2)];

  factory Device.fromJson(Map<Object?, Object?> json) => Device(
        json['deviceId']! as String,
        json['deviceName']! as String,
        json['state']! as int,
      );

  final String deviceId;
  final String deviceName;
  final SessionState state;
}

class NearbyService {
  static const _channel = MethodChannel('flutter_nearby_connections');
  final _states = StreamController<List<Device>>.broadcast();
  final _data = StreamController<dynamic>.broadcast();
  String? _deviceName;

  Future<void> init({
    required String serviceType,
    required Strategy strategy,
    String? deviceName,
    required Function callback,
  }) async {
    if (strategy != Strategy.Wi_Fi_P2P) {
      throw ArgumentError('Only Strategy.Wi_Fi_P2P is supported');
    }
    _deviceName = deviceName;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'invoke_change_state_method':
          final decoded = jsonDecode(call.arguments as String) as List;
          _states.add([
            for (final item in decoded)
              Device.fromJson(Map<Object?, Object?>.from(item as Map)),
          ]);
        case 'invoke_message_receive_method':
          _data.add(call.arguments);
        case 'nearby_running':
          callback(call.arguments as bool);
      }
    });
    await _channel.invokeMethod<void>('init_nearby_service', {
      'deviceName': deviceName ?? '',
      'serviceType': serviceType,
      'strategy': 3,
    });
  }

  Future<void> startAdvertisingPeer({String? deviceName}) =>
      _invoke('start_advertising_peer', {'deviceName': deviceName ?? ''});
  Future<void> stopAdvertisingPeer() => _invoke('stop_advertising_peer');
  Future<void> startBrowsingForPeers() => _invoke('start_browsing_for_peers');
  Future<void> stopBrowsingForPeers() => _invoke('stop_browsing_for_peers');
  Future<void> invitePeer({required String deviceID, String? deviceName}) =>
      _invoke('invite_peer', {'deviceId': deviceID, 'deviceName': deviceName});
  Future<void> disconnectPeer({required String? deviceID}) =>
      _invoke('disconnect_peer', {'deviceId': deviceID});
  Future<void> sendMessage(String deviceID, String message) => _invoke(
        'send_message',
        {
          'deviceId': deviceID,
          'senderDeviceId': _deviceName,
          'message': message
        },
      );
  Future<void> dispose() => _invoke('close_nearby_service');

  StreamSubscription<List<Device>> stateChangedSubscription({
    required void Function(List<Device>) callback,
  }) =>
      _states.stream.listen(callback);

  StreamSubscription<dynamic> dataReceivedSubscription({
    required void Function(dynamic) callback,
  }) =>
      _data.stream.listen(callback);

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    await _channel.invokeMethod<void>(method, arguments);
  }
}
