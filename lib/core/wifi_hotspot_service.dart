import 'package:flutter/services.dart';

class WifiHotspotCredentials {
  final String ssid;
  final String password;
  final String? shopId;

  const WifiHotspotCredentials({
    required this.ssid,
    required this.password,
    this.shopId,
  });

  String get qrPayload {
    final shopField = shopId == null ? '' : 'LIMS:${_escape(shopId!)};';
    return 'WIFI:T:WPA;S:${_escape(ssid)};P:${_escape(password)};$shopField;';
  }

  bool matchesShopId(String candidate) {
    final expected = shopId?.replaceAll('-', '').toLowerCase();
    final actual = candidate.replaceAll('-', '').toLowerCase();
    return expected != null &&
        expected.length >= 8 &&
        actual.length >= 8 &&
        expected.substring(0, 8) == actual.substring(0, 8);
  }

  static WifiHotspotCredentials? fromQrPayload(String payload) {
    if (!payload.startsWith('WIFI:')) return null;
    final values = <String, String>{};
    for (final field in _splitEscaped(payload.substring(5), ';')) {
      final separator = _firstUnescaped(field, ':');
      if (separator < 1) continue;
      values[field.substring(0, separator)] = _unescape(
        field.substring(separator + 1),
      );
    }
    final ssid = values['S']?.trim() ?? '';
    final password = values['P'] ?? '';
    final type = values['T']?.toUpperCase() ?? 'WPA';
    if (ssid.isEmpty || password.isEmpty || !type.startsWith('WPA')) {
      return null;
    }
    final shopId = values['LIMS']?.trim();
    return WifiHotspotCredentials(
      ssid: ssid,
      password: password,
      shopId: shopId?.isEmpty == true ? null : shopId,
    );
  }

  static String _escape(String value) =>
      value.replaceAllMapped(RegExp(r'([\\;,:"])'), (match) => '\\${match[0]}');

  static String _unescape(String value) {
    final output = StringBuffer();
    var escaped = false;
    for (final unit in value.codeUnits) {
      final character = String.fromCharCode(unit);
      if (escaped) {
        output.write(character);
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else {
        output.write(character);
      }
    }
    if (escaped) output.write('\\');
    return output.toString();
  }

  static List<String> _splitEscaped(String value, String separator) {
    final parts = <String>[];
    final current = StringBuffer();
    var escaped = false;
    for (final unit in value.codeUnits) {
      final character = String.fromCharCode(unit);
      if (!escaped && character == separator) {
        parts.add(current.toString());
        current.clear();
      } else {
        current.write(character);
      }
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      }
    }
    parts.add(current.toString());
    return parts;
  }

  static int _firstUnescaped(String value, String character) {
    var escaped = false;
    for (var index = 0; index < value.length; index++) {
      if (!escaped && value[index] == character) return index;
      if (escaped) {
        escaped = false;
      } else if (value[index] == '\\') {
        escaped = true;
      }
    }
    return -1;
  }
}

class WifiHotspotService {
  WifiHotspotService._();

  static const _channel = MethodChannel('lims/wifi');

  static Future<WifiHotspotCredentials> startShopHotspot() async {
    final values = Map<Object?, Object?>.from(
      await _channel.invokeMethod<Object?>('startShopHotspot') as Map,
    );
    return WifiHotspotCredentials(
      ssid: values['ssid'] as String? ?? '',
      password: values['password'] as String? ?? '',
    );
  }

  static Future<void> stopShopHotspot() =>
      _channel.invokeMethod('stopShopHotspot');

  static String friendlyHotspotError(PlatformException error) {
    if (error.code == 'WIFI_DISABLED') {
      return error.message ?? 'Wi-Fi is turned off. Turn on Wi-Fi and try again.';
    }
    if (error.code == 'WIFI_UNAVAILABLE' || error.code == 'WIFI_TIMEOUT') {
      return error.message ?? 'Could not connect to the shop Wi-Fi hotspot.';
    }
    if (error.code == 'HOTSPOT_FAILED') {
      return '${error.message ?? 'This phone could not start an in-app hotspot.'} '
          'Use the phone\'s normal hotspot or connect all devices to the same '
          'Wi-Fi network, then keep Shop visibility enabled.';
    }
    return error.message ?? 'Could not change hotspot';
  }

  static Future<void> connect({
    required String ssid,
    required String password,
  }) => _channel.invokeMethod('connectToShopHotspot', {
    'ssid': ssid,
    'password': password,
  });

  static Future<void> disconnect() =>
      _channel.invokeMethod('disconnectFromShopHotspot');
}
