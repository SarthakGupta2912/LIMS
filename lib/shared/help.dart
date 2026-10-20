import 'package:flutter/material.dart';

import '../app/responsive.dart';
import '../core/app_database.dart';
import 'ui.dart';

Future<void> showRoleHelp(BuildContext context, AppRole role) {
  final sections = role == AppRole.customer
      ? const [
          (
            'Find nearby shops',
            'Keep Wi-Fi on. Shops appear while this screen is open.',
          ),
          (
            'Place an order',
            'Open a shop, choose available items, review the cart, and send it while you are near the shop.',
          ),
          (
            'Pickup updates',
            'The shop provides an estimated pickup time. Reconnect near the shop for newer status and messages.',
          ),
          (
            'Local history',
            'Orders and related messages stay on this device for one year, then are removed automatically.',
          ),
          (
            'Move devices',
            'Use Transfer to new device in Settings before changing phones.',
          ),
        ]
      : const [
          (
            'Make the shop visible',
            'Turn on Shop visibility while the app is open so nearby customers can find the menu.',
          ),
          (
            'Publish the menu',
            'Only products marked visible to customers are included in the nearby catalog.',
          ),
          (
            'Manage orders',
            'Accept or reject new orders. Add an estimated pickup time when accepting an order.',
          ),
          (
            'Status and chat',
            'You control status sharing and messaging globally and for each order.',
          ),
          (
            'Move devices',
            'Use Transfer to new device in Settings to move local business data.',
          ),
        ];
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (context) => GlassDialog(
      title: role == AppRole.customer ? 'Customer guide' : 'Shopkeeper guide',
      maxWidth: Breakpoints.compact(context) ? double.infinity : 560,
      actions: [
        FilledButton(
          onPressed: () => closeAppDialog(context),
          child: const CustomText(
            'Got it',
            color: Color(0xFF062026),
            variant: CustomTextStyle.label,
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: sections.indexed.map((entry) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.$1 == sections.length - 1 ? 0 : 16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 16, child: Text('${entry.$1 + 1}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(entry.$2.$1, variant: CustomTextStyle.label),
                      const SizedBox(height: 3),
                      CustomText(entry.$2.$2, color: Colors.white70),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ),
  );
}
