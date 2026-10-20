import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import '../../shared/ui.dart';

class ProfileSelectionPage extends StatefulWidget {
  final ValueChanged<LocalProfile> onSelected;

  const ProfileSelectionPage({super.key, required this.onSelected});

  @override
  State<ProfileSelectionPage> createState() => _ProfileSelectionPageState();
}

class _ProfileSelectionPageState extends State<ProfileSelectionPage> {
  Future<void> _create(AppRole role) async {
    final controller = TextEditingController();
    final label = role == AppRole.customer ? 'Your name' : 'Shop name';
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (context) => GlassDialog(
        title: role == AppRole.customer
            ? 'Create customer profile'
            : 'Create shopkeeper profile',
        actions: [
          TextButton(
            onPressed: () => closeAppDialog(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              closeAppDialog(context, value);
            },
            child: const CustomText(
              'Continue',
              color: Color(0xFF062026),
              variant: CustomTextStyle.label,
            ),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) closeAppDialog(context, value.trim());
          },
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final profile = AppDatabase.instance.createProfile(role, result);
    widget.onSelected(profile);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = AppDatabase.instance.profiles();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      size: 52,
                      color: Color(0xFF7DEBFF),
                    ),
                    const SizedBox(height: 16),
                    const CustomText(
                      'Choose how you use LIMS',
                      variant: CustomTextStyle.display,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const CustomText(
                      'Profiles stay on this device. Switching profiles never deletes local data.',
                      color: Colors.white70,
                      textAlign: TextAlign.center,
                    ),
                    if (profiles.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const CustomText(
                        'Continue as',
                        variant: CustomTextStyle.title,
                      ),
                      const SizedBox(height: 10),
                      ...profiles.map(
                        (profile) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassContainer(
                            child: ListTile(
                              onTap: () {
                                AppDatabase.instance.selectProfile(profile.id);
                                widget.onSelected(profile);
                              },
                              leading: CircleAvatar(
                                child: Icon(
                                  profile.role == AppRole.customer
                                      ? Icons.person_outline
                                      : Icons.storefront_outlined,
                                ),
                              ),
                              title: CustomText(
                                profile.displayName,
                                variant: CustomTextStyle.subtitle,
                              ),
                              subtitle: CustomText(
                                profile.role == AppRole.customer
                                    ? 'Customer'
                                    : 'Shopkeeper',
                                color: Colors.white70,
                              ),
                              trailing: const Icon(Icons.arrow_forward),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 560;
                        const optionHeight = 220.0;
                        final options = [
                          _RoleOption(
                            icon: Icons.person_search_outlined,
                            title: 'Customer',
                            message:
                                'Find nearby shops, order, and view local history.',
                            onTap: () => _create(AppRole.customer),
                          ),
                          _RoleOption(
                            icon: Icons.storefront_outlined,
                            title: 'Shopkeeper',
                            message:
                                'Publish a menu, receive orders, and manage billing.',
                            onTap: () => _create(AppRole.shopkeeper),
                          ),
                        ];
                        return narrow
                            ? Column(
                                children: options
                                    .map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: optionHeight,
                                          child: item,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              )
                            : SizedBox(
                                height: optionHeight,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: options[0]),
                                    const SizedBox(width: 12),
                                    Expanded(child: options[1]),
                                  ],
                                ),
                              );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GlassContainer(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 32),
        const SizedBox(height: 14),
        CustomText(title, variant: CustomTextStyle.title),
        const SizedBox(height: 5),
        Expanded(child: CustomText(message, color: Colors.white70)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onTap,
            child: const Text('Create profile'),
          ),
        ),
      ],
    ),
  );
}
