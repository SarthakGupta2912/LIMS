import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BuzzVibrationService {
  BuzzVibrationService._();

  static final instance = BuzzVibrationService._();
  static const _channel = MethodChannel('lims/buzz');

  Future<void> start({required String eventId}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('start', {'eventId': eventId});
    } on PlatformException catch (error) {
      debugPrint('Could not start customer buzz vibration: $error');
    }
  }

  Future<void> stop({String? eventId}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stop', {'eventId': eventId});
    } on PlatformException catch (error) {
      debugPrint('Could not stop customer buzz vibration: $error');
    }
  }
}
