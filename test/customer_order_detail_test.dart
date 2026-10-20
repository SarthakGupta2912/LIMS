import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/Pages/customer/customer_order_detail_page.dart';
import 'package:lims/app/app.dart';
import 'package:lims/core/app_database.dart';
import 'package:lims/core/nearby_connection_service.dart';

void main() {
  testWidgets('shows reached pickup milestones and their times', (
    tester,
  ) async {
    final created = DateTime(2026, 9, 20, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: OrderMilestoneProgress(
              status: 'preparing',
              createdAt: created,
              updates: [
                OrderStatusUpdateRecord(
                  id: 'accepted',
                  orderId: 'order-1',
                  ownerProfileId: 'customer-1',
                  status: 'accepted',
                  updatedAt: created.add(const Duration(minutes: 2)),
                  version: 2,
                  syncStatus: 'synced',
                ),
                OrderStatusUpdateRecord(
                  id: 'preparing',
                  orderId: 'order-1',
                  ownerProfileId: 'customer-1',
                  status: 'preparing',
                  updatedAt: created.add(const Duration(minutes: 5)),
                  version: 3,
                  syncStatus: 'synced',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Placed'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('10:02 AM'), findsOneWidget);
    expect(find.text('10:05 AM'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('order-progress-preparing')),
      findsOneWidget,
    );
  });

  testWidgets('cancelled order remains at the placed milestone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderMilestoneProgress(
          status: 'cancelled',
          createdAt: DateTime(2026, 9, 20, 10),
          updates: const [],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('order-progress-cancelled')),
      findsOneWidget,
    );
  });

  testWidgets('customer buzz dialog identifies the shop and order', (
    tester,
  ) async {
    final event = CustomerBuzzEvent(
      eventId: 'buzz-1',
      orderId: '067df341-0000',
      shopId: 'shop-1',
      shopName: 'Sarthak Shop',
      sentAt: DateTime(2026, 9, 20, 17, 46),
      endsAt: DateTime(2026, 9, 20, 17, 51),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CustomerBuzzDialog(event: event),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Sarthak Shop needs your attention'), findsOneWidget);
    expect(find.textContaining('067DF341'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('View order'), findsOneWidget);
  });
}
