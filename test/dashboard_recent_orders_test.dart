import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lims/Pages/dashboard/dashboard_page.dart';
import 'package:lims/core/app_database.dart';

void main() {
  testWidgets('recent order card opens the selected order', (tester) async {
    final now = DateTime(2026, 9, 20, 10);
    final profile = LocalProfile(
      id: 'shop-1',
      role: AppRole.shopkeeper,
      displayName: 'Shopkeeper',
      createdAt: now,
    );
    final orders = List.generate(
      6,
      (index) => LocalOrderRecord(
        id: 'order-$index',
        ownerProfileId: profile.id,
        shopId: 'shop-1',
        shopName: 'Shop',
        customerId: 'customer-$index',
        customerName: 'Customer $index',
        status: 'accepted',
        total: 10.0 + index,
        createdAt: now.subtract(Duration(minutes: index)),
        updatedAt: now.subtract(Duration(minutes: index)),
        shareStatus: true,
        chatEnabled: true,
      ),
    );
    LocalOrderRecord? selected;
    var viewAll = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: RecentOrdersPanel(
            profile: profile,
            orders: orders,
            onOrders: () => viewAll = true,
            onChanged: () {},
            onOpenOrder: (order) => selected = order,
          ),
        ),
      ),
    );

    expect(find.text('Customer 0'), findsOneWidget);
    expect(find.text('Customer 4'), findsOneWidget);
    expect(find.text('Customer 5'), findsNothing);

    await tester.tap(find.text('Customer 2'));
    expect(selected?.id, 'order-2');

    await tester.tap(find.text('View all'));
    expect(viewAll, isTrue);
  });
}
