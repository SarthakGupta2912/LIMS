import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../core/nearby_connection_service.dart';
import '../../shared/ui.dart';

class ShopOrdersPage extends StatefulWidget {
  final LocalProfile profile;

  const ShopOrdersPage({super.key, required this.profile});

  @override
  State<ShopOrdersPage> createState() => _ShopOrdersPageState();
}

class _ShopOrdersPageState extends State<ShopOrdersPage> {
  final _nearby = NearbyConnectionService.instance;
  String _filter = 'new';

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

  List<LocalOrderRecord> _filtered(List<LocalOrderRecord> orders) {
    return switch (_filter) {
      'new' => orders.where((order) => order.status == 'pending').toList(),
      'active' =>
        orders
            .where(
              (order) => const ['accepted', 'preparing'].contains(order.status),
            )
            .toList(),
      'ready' =>
        orders.where((order) => order.status == 'ready_for_pickup').toList(),
      'completed' =>
        orders
            .where(
              (order) => const [
                'completed',
                'rejected',
                'cancelled',
              ].contains(order.status),
            )
            .toList(),
      _ => orders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final orders = _filtered(AppDatabase.instance.ordersForProfile(profile.id));
    final landscape = Breakpoints.landscapeMobile(context);
    final list = orders.isEmpty
        ? EmptyPanel(
            icon: Icons.room_service_outlined,
            title: _filter == 'new' ? 'No new orders' : 'No orders here',
            message:
                'Orders update here automatically while customers are connected.',
          )
        : ListView.separated(
            shrinkWrap: landscape,
            physics: landscape
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final order = orders[index];
              return GlassContainer(
                child: ListTile(
                  onTap: () => showShopOrderDialog(
                    context,
                    profile: widget.profile,
                    initialOrder: order,
                    onChanged: () {
                      if (mounted) setState(() {});
                    },
                  ),
                  leading: CircleAvatar(child: Icon(_statusIcon(order.status))),
                  title: CustomText(
                    order.customerName,
                    variant: CustomTextStyle.subtitle,
                  ),
                  subtitle: CustomText(
                    '${_statusLabel(order.status)}  |  ${_shortId(order.id)}${order.pickupAt == null ? '' : '\nPickup ${_time(order.pickupAt!)}'}',
                    color: Colors.white70,
                    maxLines: 2,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CustomText(
                        money(order.total),
                        variant: CustomTextStyle.label,
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              );
            },
          );

    return PageFrame(
      title: 'Orders',
      subtitle: 'Accept orders, set pickup estimates, and manage preparation.',
      actions: [
        Chip(
          avatar: Icon(
            _nearby.connected ? Icons.wifi : Icons.wifi_find,
            size: 17,
          ),
          label: Text(_nearby.connected ? 'Customer connected' : 'Nearby only'),
        ),
      ],
      scrollable: landscape,
      child: Column(
        mainAxisSize: landscape ? MainAxisSize.min : MainAxisSize.max,
        children: [
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final item in const [
                  ('new', 'New'),
                  ('active', 'Active'),
                  ('ready', 'Ready'),
                  ('completed', 'History'),
                  ('all', 'All'),
                ]) ...[
                  FilterChip(
                    label: Text(item.$2),
                    selected: _filter == item.$1,
                    onSelected: (_) => setState(() => _filter = item.$1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (landscape) list else Expanded(child: list),
        ],
      ),
    );
  }
}

Future<void> showShopOrderDialog(
  BuildContext context, {
  required LocalProfile profile,
  required LocalOrderRecord initialOrder,
  VoidCallback? onChanged,
}) async {
  final nearby = NearbyConnectionService.instance;
  var order =
      AppDatabase.instance.orderForProfile(profile.id, initialOrder.id) ??
      initialOrder;
  var selectedStatus = order.status;
  DateTime? selectedPickupAt = order.pickupAt;
  var shareStatus = order.shareStatus;
  var chatEnabled = order.chatEnabled;
  var buzzing = false;
  String? buzzResult;
  Timer? cooldownTimer;
  final items = AppDatabase.instance.orderItems(profile.id, order.id);
  final saved = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        order =
            AppDatabase.instance.orderForProfile(profile.id, initialOrder.id) ??
            order;
        final statuses = _allowedStatuses(order.status);
        if (!statuses.contains(selectedStatus)) {
          selectedStatus = statuses.first;
        }
        final buzzActive = _buzzIsActive(order);
        final buzzRemaining = buzzActive
            ? _buzzSessionRemaining(order)
            : _buzzCooldownRemaining(order);
        if (buzzRemaining > Duration.zero && cooldownTimer == null) {
          cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!context.mounted) {
              timer.cancel();
              return;
            }
            setDialogState(() {});
            order =
                AppDatabase.instance.orderForProfile(profile.id, order.id) ??
                order;
            final remaining = _buzzIsActive(order)
                ? _buzzSessionRemaining(order)
                : _buzzCooldownRemaining(order);
            if (remaining == Duration.zero) {
              timer.cancel();
              cooldownTimer = null;
            }
          });
        }
        final customerReachable = nearby.customerIsReachable(order.customerId);
        return GlassDialog(
          title: 'Order ${_shortId(order.id)}',
          maxWidth: Breakpoints.compact(context) ? double.infinity : 560,
          actions: [
            TextButton(
              onPressed: () => closeAppDialog(context, false),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed:
                  selectedStatus == order.status &&
                      _sameMoment(selectedPickupAt, order.pickupAt) &&
                      shareStatus == order.shareStatus &&
                      chatEnabled == order.chatEnabled
                  ? null
                  : () => closeAppDialog(context, true),
              icon: const Icon(Icons.sync),
              label: const Text('Update order'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CustomText(
                      order.customerName,
                      variant: CustomTextStyle.title,
                    ),
                  ),
                  CustomText(
                    money(order.total),
                    variant: CustomTextStyle.title,
                  ),
                ],
              ),
              if (order.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                CustomText('Note: ${order.note}', color: Colors.white70),
              ],
              const Divider(height: 24),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${item.quantity} × ${item.productName}'),
                      ),
                      Text(money(item.total)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              if (isBuzzEligibleStatus(order.status)) ...[
                OutlinedButton.icon(
                  onPressed:
                      buzzing ||
                          (!buzzActive &&
                              (!customerReachable ||
                                  buzzRemaining > Duration.zero))
                      ? null
                      : () async {
                          if (buzzActive) {
                            setDialogState(() {
                              buzzing = true;
                              buzzResult = null;
                            });
                            final stopResult = await nearby.stopCustomerBuzz(
                              order,
                            );
                            if (!context.mounted) return;
                            setDialogState(() {
                              buzzing = false;
                              order =
                                  AppDatabase.instance.orderForProfile(
                                    profile.id,
                                    order.id,
                                  ) ??
                                  order;
                              buzzResult = switch (stopResult) {
                                CustomerBuzzStopResult.delivered =>
                                  'Customer buzz stopped.',
                                CustomerBuzzStopResult.customerUnavailable =>
                                  'Session stopped here. The disconnected customer phone will stop automatically.',
                                CustomerBuzzStopResult.alreadyEnded =>
                                  'Buzz session already ended.',
                              };
                            });
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                            context: context,
                            barrierColor: Colors.black.withValues(alpha: .28),
                            builder: (confirmationContext) => GlassDialog(
                              title: 'Buzz ${order.customerName}?',
                              maxWidth: Breakpoints.compact(confirmationContext)
                                  ? double.infinity
                                  : 420,
                              actions: [
                                TextButton(
                                  onPressed: () => closeAppDialog(
                                    confirmationContext,
                                    false,
                                  ),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton.icon(
                                  onPressed: () =>
                                      closeAppDialog(confirmationContext, true),
                                  icon: const Icon(
                                    Icons.notifications_active_outlined,
                                  ),
                                  label: const Text('Buzz customer'),
                                ),
                              ],
                              child: const CustomText(
                                'This starts a repeating vibration on the connected customer phone for up to 5 minutes.',
                                color: Colors.white70,
                              ),
                            ),
                          );
                          if (confirmed != true || !context.mounted) return;
                          setDialogState(() {
                            buzzing = true;
                            buzzResult = null;
                          });
                          final result = await nearby.buzzCustomer(order);
                          if (!context.mounted) return;
                          setDialogState(() {
                            buzzing = false;
                            order =
                                AppDatabase.instance.orderForProfile(
                                  profile.id,
                                  order.id,
                                ) ??
                                order;
                            buzzResult = _buzzResultText(result);
                          });
                        },
                  icon: buzzing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          buzzActive
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_active_outlined,
                        ),
                  label: Text(
                    buzzActive
                        ? 'Stop buzz (${_cooldownLabel(buzzRemaining)})'
                        : buzzRemaining > Duration.zero
                        ? 'Buzz available in ${_cooldownLabel(buzzRemaining)}'
                        : 'Buzz customer',
                  ),
                ),
                const SizedBox(height: 6),
                CustomText(
                  buzzResult ??
                      (buzzActive
                          ? 'Vibrating for 30 seconds every minute.'
                          : customerReachable
                          ? 'Send an urgent attention alert to this customer.'
                          : 'Customer must be connected to receive a buzz.'),
                  color: Colors.white70,
                ),
                const Divider(height: 24),
              ],
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(labelText: 'Order status'),
                items: statuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_statusLabel(status)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  selectedStatus = value ?? order.status;
                  if (selectedStatus == 'accepted' &&
                      selectedPickupAt == null) {
                    selectedPickupAt = DateTime.now().add(
                      const Duration(minutes: 15),
                    );
                  }
                }),
              ),
              if (selectedStatus == 'accepted') ...[
                const SizedBox(height: 14),
                const CustomText(
                  'Estimated pickup',
                  variant: CustomTextStyle.label,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [10, 15, 20, 30]
                      .map(
                        (minutes) => ChoiceChip(
                          label: Text('$minutes min'),
                          selected: _matchesPickupMinutes(
                            selectedPickupAt,
                            minutes,
                          ),
                          onSelected: (_) => setDialogState(
                            () => selectedPickupAt = DateTime.now().add(
                              Duration(minutes: minutes),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final current = selectedPickupAt ?? DateTime.now();
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(current),
                    );
                    if (!context.mounted || picked == null) return;
                    final now = DateTime.now();
                    var custom = DateTime(
                      now.year,
                      now.month,
                      now.day,
                      picked.hour,
                      picked.minute,
                    );
                    if (!custom.isAfter(now)) {
                      custom = custom.add(const Duration(days: 1));
                    }
                    setDialogState(() => selectedPickupAt = custom);
                  },
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(
                    _matchesPickupPreset(selectedPickupAt)
                        ? 'Custom time'
                        : 'Pickup ${_time(selectedPickupAt!)}',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: shareStatus,
                title: const Text('Share status with customer'),
                onChanged: (value) => setDialogState(() => shareStatus = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: chatEnabled,
                title: const Text('Allow order messages'),
                onChanged: (value) => setDialogState(() => chatEnabled = value),
              ),
              const SizedBox(height: 8),
              if (nearby.hasPendingStatusForCustomer(order.customerId)) ...[
                const CustomText(
                  'Status queued — it will sync automatically.',
                  color: Colors.white70,
                ),
                TextButton.icon(
                  onPressed: () async {
                    await nearby.resendPendingStatuses(order.customerId);
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Resend pending status'),
                ),
              ] else
                const CustomText(
                  'No pending status sync.',
                  color: Colors.white70,
                ),
            ],
          ),
        );
      },
    ),
  );
  cooldownTimer?.cancel();
  if (saved != true || !context.mounted) return;
  final pickupAt = selectedStatus == 'accepted'
      ? selectedPickupAt ?? DateTime.now().add(const Duration(minutes: 15))
      : order.pickupAt;
  await nearby.updateOrderStatus(
    order: order,
    status: selectedStatus,
    pickupAt: pickupAt,
    shareStatus: shareStatus,
    chatEnabled: chatEnabled,
  );
  if (!context.mounted) return;
  order = AppDatabase.instance.orderForProfile(profile.id, order.id)!;
  onChanged?.call();
  showAppSnack(
    context,
    nearby.connected
        ? 'Order updated and sent to the customer.'
        : 'Order updated. It will sync when the customer reconnects.',
  );
}

List<String> _allowedStatuses(String current) => switch (current) {
  'pending' => const ['pending', 'accepted', 'rejected'],
  'accepted' => const ['accepted', 'preparing', 'cancelled'],
  'preparing' => const ['preparing', 'ready_for_pickup', 'cancelled'],
  'ready_for_pickup' => const ['ready_for_pickup', 'completed'],
  _ => [current],
};

String _statusLabel(String status) => switch (status) {
  'pending' => 'New order',
  'accepted' => 'Accepted',
  'preparing' => 'Preparing',
  'ready_for_pickup' => 'Ready for pickup',
  'completed' => 'Completed',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

IconData _statusIcon(String status) => switch (status) {
  'accepted' => Icons.check_circle_outline,
  'preparing' => Icons.soup_kitchen_outlined,
  'ready_for_pickup' => Icons.shopping_bag_outlined,
  'completed' => Icons.task_alt,
  'rejected' || 'cancelled' => Icons.cancel_outlined,
  _ => Icons.notifications_active_outlined,
};

String _shortId(String id) =>
    id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

String _time(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

bool _sameMoment(DateTime? left, DateTime? right) =>
    left?.millisecondsSinceEpoch == right?.millisecondsSinceEpoch;

bool _matchesPickupMinutes(DateTime? pickupAt, int minutes) {
  if (pickupAt == null) return false;
  final difference = pickupAt.difference(DateTime.now()).inMinutes;
  return difference >= minutes - 1 && difference <= minutes + 1;
}

bool _matchesPickupPreset(DateTime? pickupAt) =>
    pickupAt != null &&
    [10, 15, 20, 30].any((minutes) => _matchesPickupMinutes(pickupAt, minutes));

Duration _buzzCooldownRemaining(LocalOrderRecord order) {
  final endedAt = order.buzzStoppedAt ?? order.buzzEndsAt;
  if (endedAt == null || _buzzIsActive(order)) return Duration.zero;
  final remaining = endedAt
      .add(const Duration(seconds: 30))
      .difference(DateTime.now());
  return remaining.isNegative ? Duration.zero : remaining;
}

bool _buzzIsActive(LocalOrderRecord order) =>
    order.buzzEventId != null &&
    order.buzzStoppedAt == null &&
    order.buzzEndsAt != null &&
    order.buzzEndsAt!.isAfter(DateTime.now());

Duration _buzzSessionRemaining(LocalOrderRecord order) {
  final endsAt = order.buzzEndsAt;
  if (endsAt == null || !_buzzIsActive(order)) return Duration.zero;
  final remaining = endsAt.difference(DateTime.now());
  return remaining.isNegative ? Duration.zero : remaining;
}

String _cooldownLabel(Duration duration) {
  final seconds =
      duration.inSeconds + (duration.inMilliseconds % 1000 > 0 ? 1 : 0);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return minutes == 0 ? '${remainder}s' : '${minutes}m ${remainder}s';
}

String _buzzResultText(CustomerBuzzResult result) => switch (result) {
  CustomerBuzzResult.delivered => 'Customer phone buzzed.',
  CustomerBuzzResult.deliveryUnconfirmed =>
    'Buzz sent, but delivery was not confirmed.',
  CustomerBuzzResult.unavailable => 'Customer is no longer connected.',
  CustomerBuzzResult.cooldown => 'Please wait before buzzing this order again.',
  CustomerBuzzResult.invalidOrder =>
    'Buzz is only available for active accepted orders.',
  CustomerBuzzResult.sendFailed => 'Could not send the buzz. Try again.',
};
