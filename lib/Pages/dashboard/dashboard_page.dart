import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import '../billing/billing_page.dart';
import '../../shared/ui.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onNewInvoice;
  final VoidCallback onAddProduct;
  final VoidCallback onTemplate;
  final VoidCallback onChanged;
  final VoidCallback onInvoices;

  const DashboardPage({
    super.key,
    required this.onNewInvoice,
    required this.onAddProduct,
    required this.onTemplate,
    required this.onChanged,
    required this.onInvoices,
  });

  @override
  Widget build(BuildContext context) {
    final stats = AppDatabase.instance.dashboardStats();
    return PageFrame(
      title: 'Business Dashboard',
      subtitle:
          'Track products, invoices, revenue, and daily billing activity.',
      actions: [
        FilledButton.icon(
          onPressed: onNewInvoice,
          icon: const Icon(Icons.receipt_long),
          label: const CustomText(
            'New invoice',
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
      child: ListView(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1120
                  ? 4
                  : constraints.maxWidth >= 640
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - (12 * (columns - 1))) / columns;
              final metrics = [
                MetricCard(
                  label: 'Revenue',
                  value: money(stats.revenue),
                  icon: Icons.trending_up,
                  color: const Color(0xFF059669),
                ),
                MetricCard(
                  label: 'Profit',
                  value: money(stats.profit),
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFF0EA5E9),
                ),
                MetricCard(
                  label: 'Pending',
                  value: money(stats.pending),
                  icon: Icons.schedule,
                  color: const Color(0xFFD97706),
                ),
                MetricCard(
                  label: 'Invoices',
                  value: '${stats.invoices}',
                  icon: Icons.description_outlined,
                  color: const Color(0xFF2563EB),
                ),
                MetricCard(
                  label: 'Products',
                  value: '${stats.products}',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF7C3AED),
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: cardWidth,
                        height: columns == 1 ? 112 : 128,
                        child: metric,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.percent, color: Color(0xFF7DEBFF)),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomText(
                    'Estimated profit margin',
                    variant: CustomTextStyle.label,
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
                CustomText(
                  '${stats.profitMargin.toStringAsFixed(1)}%',
                  variant: CustomTextStyle.title,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 900;
              final recent = _RecentInvoices(
                stats: stats,
                onChanged: onChanged,
                onInvoices: onInvoices,
              );
              final actions = _QuickActions(
                onNewInvoice: onNewInvoice,
                onAddProduct: onAddProduct,
                onTemplate: onTemplate,
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
        ],
      ),
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

class _QuickActions extends StatelessWidget {
  final VoidCallback onNewInvoice;
  final VoidCallback onAddProduct;
  final VoidCallback onTemplate;

  const _QuickActions({
    required this.onNewInvoice,
    required this.onAddProduct,
    required this.onTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.point_of_sale, 'Start billing', onNewInvoice),
      (Icons.inventory_2_outlined, 'Add product', onAddProduct),
      (Icons.dashboard_customize_outlined, 'Invoice template', onTemplate),
    ];
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CustomText('Quick actions', variant: CustomTextStyle.title),
          const SizedBox(height: 12),
          ...actions.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: item.$3,
                  icon: Icon(item.$1),
                  label: CustomText(
                    item.$2,
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
