import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../billing/billing_page.dart';
import '../invoices/invoices_page.dart';
import '../orders/shop_orders_page.dart';
import '../../shared/ui.dart';
import '../../shared/help.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onNewInvoice;
  final VoidCallback onAddProduct;
  final VoidCallback onTemplate;
  final VoidCallback onChanged;
  final VoidCallback onInvoices;
  final VoidCallback? onOrders;
  final ValueChanged<LocalOrderRecord>? onOpenOrder;
  final ShopkeeperMode mode;

  const DashboardPage({
    super.key,
    required this.onNewInvoice,
    required this.onAddProduct,
    required this.onTemplate,
    required this.onChanged,
    required this.onInvoices,
    this.mode = ShopkeeperMode.counterBilling,
    this.onOrders,
    this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    final stats = AppDatabase.instance.dashboardStats();
    final profile = AppDatabase.instance.activeProfile();
    final orders = profile == null
        ? const <LocalOrderRecord>[]
        : AppDatabase.instance.ordersForProfile(profile.id);
    final shop = profile == null
        ? null
        : AppDatabase.instance.shopForProfile(profile.id);
    final landscape = Breakpoints.landscapeMobile(context);
    final bodyChildren = [
      _MetricsSection(stats: stats, mode: mode),
      const SizedBox(height: 16),
      GlassContainer(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              mode == ShopkeeperMode.counterBilling
                  ? Icons.percent
                  : shop?.visible == true
                  ? Icons.wifi_find
                  : Icons.wifi_off_outlined,
              color: const Color(0xFF7DEBFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomText(
                mode == ShopkeeperMode.counterBilling
                    ? 'Estimated profit margin'
                    : 'Shop visibility',
                variant: CustomTextStyle.label,
                color: Colors.white.withValues(alpha: .72),
              ),
            ),
            CustomText(
              mode == ShopkeeperMode.counterBilling
                  ? '${stats.profitMargin.toStringAsFixed(1)}%'
                  : shop?.visible == true
                  ? 'Visible'
                  : 'Hidden',
              variant: CustomTextStyle.title,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 900;
          final recent = mode == ShopkeeperMode.counterBilling
              ? _RecentInvoices(
                  stats: stats,
                  onChanged: onChanged,
                  onInvoices: onInvoices,
                )
              : RecentOrdersPanel(
                  profile: profile!,
                  orders: orders,
                  onOrders: onOrders,
                  onChanged: onChanged,
                  onOpenOrder: onOpenOrder,
                );
          final actions = _QuickActions(
            onNewInvoice: onNewInvoice,
            onAddProduct: onAddProduct,
            onTemplate: onTemplate,
            onOrders: onOrders,
            mode: mode,
          );
          if (!twoColumns) {
            return Column(
              children: [recent, const SizedBox(height: 16), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: recent),
              const SizedBox(width: 16),
              Expanded(child: actions),
            ],
          );
        },
      ),
    ];
    return PageFrame(
      title: mode == ShopkeeperMode.counterBilling
          ? 'Counter Billing'
          : 'Nearby Orders',
      subtitle: mode == ShopkeeperMode.counterBilling
          ? 'Create invoices and manage walk-in customer payments.'
          : 'Receive, prepare, and manage orders from nearby customers.',
      actions: [
        IconButton.filledTonal(
          tooltip: 'How to use this app',
          onPressed: () => showRoleHelp(context, AppRole.shopkeeper),
          icon: const Icon(Icons.help_outline),
        ),
        FilledButton.icon(
          onPressed: mode == ShopkeeperMode.counterBilling
              ? onNewInvoice
              : onOrders,
          icon: Icon(
            mode == ShopkeeperMode.counterBilling
                ? Icons.receipt_long
                : Icons.room_service_outlined,
          ),
          label: CustomText(
            mode == ShopkeeperMode.counterBilling
                ? 'New invoice'
                : 'View orders',
            color: Color(0xFF062026),
            variant: CustomTextStyle.label,
          ),
        ),
        OutlinedButton.icon(
          onPressed: onAddProduct,
          icon: const Icon(Icons.add_box_outlined),
          label: const CustomText(
            'Product',
            variant: CustomTextStyle.label,
            color: Color(0xFFB8F4FF),
          ),
        ),
      ],
      scrollable: landscape,
      child: landscape
          ? Column(children: bodyChildren)
          : ListView(children: bodyChildren),
    );
  }
}

class _RecentInvoices extends StatelessWidget {
  final DashboardStats stats;
  final VoidCallback onChanged;
  final VoidCallback onInvoices;
  const _RecentInvoices({
    required this.stats,
    required this.onChanged,
    required this.onInvoices,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: CustomText(
                  'Recent invoices',
                  variant: CustomTextStyle.title,
                ),
              ),
              TextButton.icon(
                onPressed: onInvoices,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.recentInvoices.isEmpty)
            const EmptyPanel(
              icon: Icons.receipt_long_outlined,
              title: 'No invoices yet',
              message:
                  'Create your first invoice to start building billing history.',
            )
          else
            ...stats.recentInvoices.map(
              (invoice) => ListTile(
                onTap: () => openInvoicePdf(context, invoice),
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_long, size: 20),
                ),
                title: CustomText(
                  invoice.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: CustomText(
                  '${invoice.createdAt.day}/${invoice.createdAt.month}/${invoice.createdAt.year} - ${invoice.status}${invoice.paymentNote.isEmpty ? '' : '\n${invoice.paymentNote}'}',
                  variant: CustomTextStyle.caption,
                  color: Colors.white.withValues(alpha: .72),
                  maxLines: 2,
                ),
                trailing: invoice.status == 'payment_pending'
                    ? TextButton(
                        onPressed: () async {
                          await showPaymentCollectionDialog(
                            context,
                            invoiceNumber: invoice.number,
                            amount: invoice.total,
                            payeeName: invoice.upiPayeeName,
                            upiId: invoice.upiId,
                            method: invoice.paymentMethod,
                          );
                          onChanged();
                        },
                        child: const Text('Collect'),
                      )
                    : CustomText(
                        money(invoice.total),
                        variant: CustomTextStyle.label,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class RecentOrdersPanel extends StatelessWidget {
  final LocalProfile profile;
  final List<LocalOrderRecord> orders;
  final VoidCallback? onOrders;
  final VoidCallback onChanged;
  final ValueChanged<LocalOrderRecord>? onOpenOrder;

  const RecentOrdersPanel({
    super.key,
    required this.profile,
    required this.orders,
    required this.onOrders,
    required this.onChanged,
    this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    final recent = orders.take(5).toList();
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: CustomText(
                  'Recent orders',
                  variant: CustomTextStyle.title,
                ),
              ),
              TextButton.icon(
                onPressed: onOrders,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const EmptyPanel(
              icon: Icons.room_service_outlined,
              title: 'No nearby orders yet',
              message: 'New customer orders will appear here automatically.',
            )
          else
            ...recent.map(
              (order) => ListTile(
                onTap: () {
                  final openOrder = onOpenOrder;
                  if (openOrder != null) {
                    openOrder(order);
                  } else {
                    showShopOrderDialog(
                      context,
                      profile: profile,
                      initialOrder: order,
                      onChanged: onChanged,
                    );
                  }
                },
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Icon(_orderIcon(order.status))),
                title: CustomText(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: CustomText(
                  _orderStatus(order.status),
                  variant: CustomTextStyle.caption,
                  color: Colors.white.withValues(alpha: .72),
                ),
                trailing: CustomText(
                  money(order.total),
                  variant: CustomTextStyle.label,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _orderStatus(String status) => switch (status) {
  'pending' => 'New',
  'accepted' => 'Accepted',
  'preparing' => 'Preparing',
  'ready_for_pickup' => 'Ready for pickup',
  'completed' => 'Completed',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => status,
};

IconData _orderIcon(String status) => switch (status) {
  'pending' => Icons.notifications_active_outlined,
  'accepted' || 'preparing' => Icons.restaurant_outlined,
  'ready_for_pickup' => Icons.shopping_bag_outlined,
  'completed' => Icons.task_alt,
  'rejected' || 'cancelled' => Icons.cancel_outlined,
  _ => Icons.receipt_long_outlined,
};

class _QuickActions extends StatelessWidget {
  final VoidCallback onNewInvoice;
  final VoidCallback onAddProduct;
  final VoidCallback onTemplate;
  final VoidCallback? onOrders;
  final ShopkeeperMode mode;

  const _QuickActions({
    required this.onNewInvoice,
    required this.onAddProduct,
    required this.onTemplate,
    this.onOrders,
    this.mode = ShopkeeperMode.counterBilling,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback?)>[
      (
        mode == ShopkeeperMode.counterBilling
            ? Icons.point_of_sale
            : Icons.room_service_outlined,
        mode == ShopkeeperMode.counterBilling
            ? 'Start counter billing'
            : 'Open nearby orders',
        mode == ShopkeeperMode.counterBilling ? onNewInvoice : onOrders,
      ),
      (Icons.inventory_2_outlined, 'Add product', onAddProduct),
      if (mode == ShopkeeperMode.counterBilling)
        (Icons.dashboard_customize_outlined, 'Invoice templates', onTemplate),
      if (mode == ShopkeeperMode.counterBilling && onOrders != null)
        (Icons.room_service_outlined, 'Nearby orders', onOrders!),
    ];
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CustomText('Quick actions', variant: CustomTextStyle.title),
          const SizedBox(height: 12),
          ...actions.indexed.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.$1 == actions.length - 1 ? 0 : 10,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: entry.$2.$3,
                  icon: Icon(entry.$2.$1),
                  label: CustomText(
                    entry.$2.$2,
                    variant: CustomTextStyle.label,
                    color: const Color(0xFFB8F4FF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsSection extends StatelessWidget {
  final DashboardStats stats;
  final ShopkeeperMode mode;

  const _MetricsSection({required this.stats, required this.mode});

  @override
  Widget build(BuildContext context) {
    final profile = AppDatabase.instance.activeProfile();
    final orders = profile == null
        ? const <LocalOrderRecord>[]
        : AppDatabase.instance.ordersForProfile(profile.id);
    final metrics = mode == ShopkeeperMode.counterBilling
        ? [
            (
              'Revenue',
              money(stats.revenue),
              Icons.trending_up,
              const Color(0xFF059669),
            ),
            (
              'Profit',
              money(stats.profit),
              Icons.account_balance_wallet_outlined,
              const Color(0xFF0EA5E9),
            ),
            (
              'Pending',
              money(stats.pending),
              Icons.schedule,
              const Color(0xFFD97706),
            ),
            (
              'Invoices',
              '${stats.invoices}',
              Icons.description_outlined,
              const Color(0xFF2563EB),
            ),
            (
              'Products',
              '${stats.products}',
              Icons.inventory_2_outlined,
              const Color(0xFF7C3AED),
            ),
          ]
        : [
            (
              'New orders',
              '${orders.where((order) => order.status == 'pending').length}',
              Icons.notifications_active_outlined,
              const Color(0xFFD97706),
            ),
            (
              'Active',
              '${orders.where((order) => const ['accepted', 'preparing'].contains(order.status)).length}',
              Icons.restaurant_outlined,
              const Color(0xFF0EA5E9),
            ),
            (
              'Ready',
              '${orders.where((order) => order.status == 'ready_for_pickup').length}',
              Icons.shopping_bag_outlined,
              const Color(0xFF059669),
            ),
            (
              'Completed',
              '${orders.where((order) => order.status == 'completed').length}',
              Icons.task_alt,
              const Color(0xFF2563EB),
            ),
            (
              'Products',
              '${stats.products}',
              Icons.inventory_2_outlined,
              const Color(0xFF7C3AED),
            ),
          ];

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = Breakpoints.mobileOrTablet;
          final columns = mobile
              ? 2
              : constraints.maxWidth >= 1120
              ? 4
              : 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                mode == ShopkeeperMode.counterBilling
                    ? 'Billing overview'
                    : 'Shop overview',
                variant: CustomTextStyle.title,
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: mobile ? 104 : 116,
                ),
                itemBuilder: (context, index) {
                  final metric = metrics[index];
                  return MetricCard(
                    label: metric.$1,
                    value: metric.$2,
                    icon: metric.$3,
                    color: metric.$4,
                    compact: mobile,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
