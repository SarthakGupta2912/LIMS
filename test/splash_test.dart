import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/splash.dart';

void main() {
  testWidgets('shows splash until initialization completes', (tester) async {
    var initialized = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          minimumDuration: Duration.zero,
          initialize: () async {
            initialized = true;
          },
          child: const Scaffold(body: Text('Application ready')),
        ),
      ),
    );

    expect(find.text('LIMS'), findsOneWidget);
    expect(find.text('Application ready'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));

    expect(initialized, isTrue);
    expect(find.text('Application ready'), findsOneWidget);
  });

  testWidgets('shows a database error when initialization fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          minimumDuration: Duration.zero,
          initialize: () => Future<void>.error('database unavailable'),
          child: const SizedBox(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));

    expect(find.text('Could not open local database'), findsOneWidget);
    expect(find.text('database unavailable'), findsOneWidget);
  });
}
