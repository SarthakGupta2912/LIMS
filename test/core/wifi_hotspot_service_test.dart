import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lims/core/wifi_hotspot_service.dart';

void main() {
  test('explains the system hotspot fallback after an Android failure', () {
    final message = WifiHotspotService.friendlyHotspotError(
      PlatformException(
        code: 'HOTSPOT_FAILED',
        message: 'Android could not start the in-app hotspot (code 2)',
      ),
    );

    expect(message, contains('normal hotspot'));
    expect(message, contains('same Wi-Fi network'));
    expect(message, contains('Shop visibility'));
  });

  test('round-trips standard Wi-Fi QR credentials', () {
    const credentials = WifiHotspotCredentials(
      ssid: r'Shop; Wi-Fi',
      password: r'p:a,ss\\word',
      shopId: '01234567-89ab-cdef-0123-456789abcdef',
    );

    final parsed = WifiHotspotCredentials.fromQrPayload(credentials.qrPayload);

    expect(parsed?.ssid, credentials.ssid);
    expect(parsed?.password, credentials.password);
    expect(parsed?.shopId, credentials.shopId);
    expect(parsed?.matchesShopId('01234567'), isTrue);
    expect(parsed?.matchesShopId('89abcdef'), isFalse);
  });

  test('parses standard Wi-Fi QR without LIMS shop identity', () {
    final parsed = WifiHotspotCredentials.fromQrPayload(
      'WIFI:T:WPA;S:Shop;P:password;;',
    );

    expect(parsed?.shopId, isNull);
    expect(parsed?.matchesShopId('01234567'), isFalse);
  });

  test('rejects malformed, open, and unrelated QR payloads', () {
    expect(WifiHotspotCredentials.fromQrPayload('https://example.com'), isNull);
    expect(
      WifiHotspotCredentials.fromQrPayload('WIFI:T:nopass;S:Shop;;'),
      isNull,
    );
    expect(WifiHotspotCredentials.fromQrPayload('WIFI:T:WPA;S:Shop;;'), isNull);
  });
}
