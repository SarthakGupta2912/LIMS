import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/pages/meshrabiya/meshrabiya_page.dart';

void main() {
  testWidgets('settings node route has a back button and no file tabs', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MeshrabiyaPage.thisNode(),
                ),
              ),
              child: const Text('Meshrabiya hotspot'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Meshrabiya hotspot'));
    await tester.pumpAndSettle();
    expect(find.text('This node'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Meshrabiya hotspot'), findsOneWidget);
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  testWidgets('inactive tab does not initialize Android networking', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MeshrabiyaPage(active: false)),
    );
    expect(find.text('Virtual mesh address'), findsOneWidget);
    expect(find.text('Network'), findsNothing);
    expect(find.text('Info'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send File'), findsOneWidget);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.text('Send File'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact node controls wrap without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: MeshrabiyaPage(active: false)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('BAND_2GHZ'), 150);
    expect(find.text('BAND_2GHZ'), findsOneWidget);
    expect(find.text('Hotspot Type'), findsNothing);
    expect(find.text('LOCALONLY_HOTSPOT'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Connect via QR Code Scan'), 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported platform displays a recoverable error', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
    await tester.pumpWidget(
      const MaterialApp(home: MeshrabiyaPage(active: true)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('requires an Android device'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = previousPlatform;
  });
}
