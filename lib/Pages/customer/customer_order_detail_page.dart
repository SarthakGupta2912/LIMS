import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import '../../core/nearby_connection_service.dart';
import '../../shared/ui.dart';

class CustomerOrderDetailPage extends StatefulWidget {
  final LocalProfile profile;
  final String orderId;

  const CustomerOrderDetailPage({
    super.key,
    required this.profile,
    required this.orderId,
  });

  @override
  State<CustomerOrderDetailPage> createState() =>
      _CustomerOrderDetailPageState();
}

class _CustomerOrderDetailPageState extends State<CustomerOrderDetailPage> {
  final _nearby = NearbyConnectionService.instance;

  @override
  void initState() {
    super.initState();
    _nearby.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nearby.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;
    final order = db.orderForProfile(widget.profile.id, widget.orderId);
    if (order == null) {
      return GlassBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: const Center(child: Text('This order is no longer available.')),
        ),
      );
    }
    final items = db.orderItems(widget.profile.id, order.id);
    final storedUpdates = db.orderStatusUpdates(widget.profile.id, order.id);
    final rawUpdates =
        storedUpdates.isEmpty && order.status != 'waiting_to_send'
        ? [
            OrderStatusUpdateRecord(
              id: 'legacy-${order.id}',
              orderId: order.id,
              ownerProfileId: widget.profile.id,
              status: order.status,
              updatedAt: order.updatedAt,
              pickupAt: order.pickupAt,
              version: order.version,
              syncStatus: order.syncStatus,
            ),
          ]
        : storedUpdates;
    final updates = _distinctStatusUpdates(rawUpdates);
    final terminalFailure = const {
      'rejected',
      'cancelled',
    }.contains(order.status);

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: PageFrame(
            title: order.shopName,
            subtitle: 'Order ${_shortId(order.id)}',
            scrollable: true,
            actions: [
              IconButton.filledTonal(
                tooltip: 'Back to orders',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(CupertinoIcons.back),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(
                                  _statusHeadline(order.status),
                                  variant: CustomTextStyle.title,
                                ),
                                const SizedBox(height: 5),
                                CustomText(
                                  order.pickupAt == null
                                      ? 'Placed ${_dateTime(order.createdAt)}'
                                      : 'Pickup by ${_dateTime(order.pickupAt!)}',
                                  color: Colors.white70,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          CustomText(
                            money(order.total),
                            variant: CustomTextStyle.title,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      OrderMilestoneProgress(
                        status: order.status,
                        createdAt: order.createdAt,
                        updates: updates,
                      ),
                      if (terminalFailure) ...[
                        const SizedBox(height: 18),
                        _TerminalStatus(status: order.status, updates: updates),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassContainer(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CustomText(
                        'Order details',
                        variant: CustomTextStyle.title,
                      ),
                      const SizedBox(height: 14),
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .16),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${item.quantity}x'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomText(
                                      item.productName,
                                      variant: CustomTextStyle.label,
                                    ),
                                    CustomText(
                                      '${money(item.unitPrice)} each',
                                      variant: CustomTextStyle.caption,
                                      color: Colors.white60,
                                    ),
                                  ],
                                ),
                              ),
                              CustomText(
                                money(item.total),
                                variant: CustomTextStyle.label,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (items.isEmpty)
                        const CustomText(
                          'Item details are unavailable for this order.',
                          color: Colors.white70,
                        ),
                      if (order.note.isNotEmpty) ...[
                        const Divider(height: 24),
                        const CustomText(
                          'Order note',
                          variant: CustomTextStyle.label,
                        ),
                        const SizedBox(height: 4),
                        CustomText(order.note, color: Colors.white70),
                      ],
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: CustomText(
                              'Total',
                              variant: CustomTextStyle.title,
                            ),
                          ),
                          CustomText(
                            money(order.total),
                            variant: CustomTextStyle.title,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassContainer(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CustomText(
                        'Status history',
                        variant: CustomTextStyle.title,
                      ),
                      const SizedBox(height: 14),
                      _HistoryRow(
                        label: 'Order placed',
                        time: order.createdAt,
                        icon: Icons.receipt_long_outlined,
                        first: true,
                        last: updates.isEmpty,
                      ),
                      ...updates.indexed.map(
                        (entry) => _HistoryRow(
                          label: _statusLabel(entry.$2.status),
                          time: entry.$2.updatedAt,
                          icon: _statusIcon(entry.$2.status),
                          first: false,
                          last: entry.$1 == updates.length - 1,
                        ),
                      ),
                      if (order.status == 'waiting_to_send') ...[
                        const SizedBox(height: 8),
                        const CustomText(
                          'Waiting to send when this shop reconnects.',
                          color: Colors.amberAccent,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrderMilestoneProgress extends StatelessWidget {
  final String status;
  final DateTime createdAt;
  final List<OrderStatusUpdateRecord> updates;

  static const _statuses = [
    'placed',
    'accepted',
    'preparing',
    'ready_for_pickup',
    'completed',
  ];

  const OrderMilestoneProgress({
    super.key,
    required this.status,
    required this.createdAt,
    required this.updates,
  });

  @override
  Widget build(BuildContext context) {
    final current = switch (status) {
      'waiting_to_send' || 'pending' || 'rejected' || 'cancelled' => 0,
      'accepted' => 1,
      'preparing' => 2,
      'ready_for_pickup' => 3,
      'completed' => 4,
      _ => 0,
    };
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('order-progress-$status'),
      label: 'Order progress: ${_statusLabel(status)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < _statuses.length; index++) ...[
            Expanded(
              child: _Milestone(
                label: _statusLabel(_statuses[index]),
                time: _milestoneTime(_statuses[index]),
                icon: _statusIcon(_statuses[index]),
                reached: index <= current,
                current: index == current,
              ),
            ),
            if (index < _statuses.length - 1)
              SizedBox(
                width: 12,
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.only(top: 19),
                  color: index < current
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: .42),
                ),
              ),
          ],
        ],
      ),
    );
  }

  DateTime? _milestoneTime(String milestone) {
    if (milestone == 'placed') return createdAt;
    for (final update in updates) {
      if (update.status == milestone) return update.updatedAt;
    }
    return null;
  }
}

class _Milestone extends StatelessWidget {
  final String label;
  final DateTime? time;
  final IconData icon;
  final bool reached;
  final bool current;

  const _Milestone({
    required this.label,
    required this.time,
    required this.icon,
    required this.reached,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = reached ? scheme.primary : scheme.onSurfaceVariant;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: current ? 42 : 38,
          height: current ? 42 : 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reached
                ? scheme.primary.withValues(alpha: current ? .28 : .16)
                : scheme.surfaceContainerHighest.withValues(alpha: .45),
            border: Border.all(color: color, width: current ? 2.2 : 1.2),
          ),
          child: Icon(reached && !current ? Icons.check : icon, color: color),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: reached ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (time != null)
          Text(
            _time(time!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
      ],
    );
  }
}

class _TerminalStatus extends StatelessWidget {
  final String status;
  final List<OrderStatusUpdateRecord> updates;

  const _TerminalStatus({required this.status, required this.updates});

  @override
  Widget build(BuildContext context) {
    final matching = updates.where((update) => update.status == status);
    final time = matching.isEmpty ? null : matching.last.updatedAt;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: .6),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cancel_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              '${_statusLabel(status)}${time == null ? '' : ' on ${_dateTime(time)}'}',
              variant: CustomTextStyle.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final DateTime time;
  final IconData icon;
  final bool first;
  final bool last;

  const _HistoryRow({
    required this.label,
    required this.time,
    required this.icon,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 38,
            child: Column(
              children: [
                if (!first)
                  Expanded(child: Container(width: 2, color: primary)),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: .18),
                    shape: BoxShape.circle,
                    border: Border.all(color: primary),
                  ),
                  child: Icon(icon, size: 17, color: primary),
                ),
                if (!last) Expanded(child: Container(width: 2, color: primary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(label, variant: CustomTextStyle.label),
                  CustomText(
                    _dateTime(time),
                    variant: CustomTextStyle.caption,
                    color: Colors.white60,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _statusHeadline(String status) => switch (status) {
  'waiting_to_send' => 'Order saved on this device',
  'pending' => 'Waiting for shop confirmation',
  'accepted' => 'Your order was accepted',
  'preparing' => 'Preparing your order',
  'ready_for_pickup' => 'Your order is ready',
  'completed' => 'Order completed',
  'rejected' => 'Order rejected',
  'cancelled' => 'Order cancelled',
  _ => _statusLabel(status),
};

String _statusLabel(String status) => switch (status) {
  'placed' => 'Placed',
  'waiting_to_send' => 'Waiting to send',
  'pending' => 'Received',
  'accepted' => 'Accepted',
  'preparing' => 'Preparing',
  'ready_for_pickup' => 'Ready',
  'completed' => 'Completed',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

IconData _statusIcon(String status) => switch (status) {
  'placed' || 'waiting_to_send' || 'pending' => Icons.receipt_long_outlined,
  'accepted' => Icons.storefront_outlined,
  'preparing' => Icons.soup_kitchen_outlined,
  'ready_for_pickup' => Icons.shopping_bag_outlined,
  'completed' => Icons.home_outlined,
  'rejected' || 'cancelled' => Icons.cancel_outlined,
  _ => Icons.circle_outlined,
};

String _shortId(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

String _dateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} at ${_time(value)}';

String _time(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

List<OrderStatusUpdateRecord> _distinctStatusUpdates(
  List<OrderStatusUpdateRecord> updates,
) {
  final result = <OrderStatusUpdateRecord>[];
  for (final update in updates) {
    if (result.isEmpty || result.last.status != update.status) {
      result.add(update);
    }
  }
  return result;
}
