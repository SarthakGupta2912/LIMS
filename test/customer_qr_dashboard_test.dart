import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/Pages/customer/customer_pages.dart';
import 'package:lims/core/app_database.dart';

void main() {
  for (final width in [320.0, 900.0]) {
    testWidgets('QR-only dashboard does not start discovery at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      const channel = MethodChannel('lims/custom_mesh/transport');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyShopsPage(
            profile: LocalProfile(
              id: 'qr-customer',
              role: AppRole.customer,
              displayName: 'QR Customer',
              createdAt: DateTime(2026),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shop menu'), findsOneWidget);
      expect(find.text('Scan shop QR'), findsOneWidget);
      expect(find.text('Scan again'), findsNothing);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
