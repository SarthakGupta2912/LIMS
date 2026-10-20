import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../core/custom_mesh_service.dart';
import '../templates/templates_page.dart';
import '../meshrabiya/meshrabiya_page.dart';
import '../../shared/file_picker_helpers.dart';
import '../../shared/help.dart';
import '../../shared/ui.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onChanged;
  final VoidCallback onLeaveProfile;

  const SettingsPage({
    super.key,
    required this.onChanged,
    required this.onLeaveProfile,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _mesh = CustomMeshService.instance;

  @override
  void initState() {
    super.initState();
    _mesh.addListener(_meshChanged);
  }

  void _meshChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mesh.removeListener(_meshChanged);
    super.dispose();
  }

  Future<void> _editProfileName() async {
    final profile = AppDatabase.instance.activeProfile();
    if (profile == null) return;
    final controller = TextEditingController(text: profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    AppDatabase.instance.updateProfileName(profile.id, name);
    setState(() {});
    widget.onChanged();
  }

  Future<void> _openTemplate([InvoiceTemplateRecord? template]) async {
    final saved = await showTemplateDialog(context, template);
    if (saved == true && mounted) {
      setState(() {});
      widget.onChanged();
    }
  }

  Future<void> _deleteTemplate(InvoiceTemplateRecord template) async {
    final id = template.id;
    if (id == null) return;
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: 'Delete template?',
      message:
          'The template "${template.organizationName}" will be permanently deleted. Existing invoices will remain available.',
      confirmLabel: 'Delete template',
    );
    if (!confirmed || !mounted) return;
    AppDatabase.instance.deleteTemplate(id);
    setState(() {});
    widget.onChanged();
  }

  Future<void> _chooseInvoiceFolder() async {
    final picked = await pickFolderPath(
      context: context,
      title: 'Choose invoice save folder',
      pickText: 'Use this folder',
    );
    if (picked == null || picked.trim().isEmpty) return;

    final moved = await AppDatabase.instance.updateInvoiceSaveDir(picked);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    showAppSnack(
      context,
      moved == 0
          ? 'Invoice folder updated'
          : 'Invoice folder updated and $moved PDF${moved == 1 ? '' : 's'} moved',
    );
  }

  Future<void> _resetInvoiceFolder() async {
    final moved = await AppDatabase.instance.updateInvoiceSaveDir(null);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    showAppSnack(
      context,
      moved == 0
          ? 'Invoice folder reset to default'
          : 'Invoice folder reset and $moved PDF${moved == 1 ? '' : 's'} moved',
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;
    final selectedPath = db.invoiceSaveDir();
    final isDefault = selectedPath == db.defaultInvoiceDir;
    final landscape = Breakpoints.landscapeMobile(context);
    final activeProfile = db.activeProfile();
    final shop = activeProfile == null
        ? null
        : db.shopForProfile(activeProfile.id);
    final content = [
      GlassContainer(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: const CustomText(
                      'Invoice save folder',
                      variant: CustomTextStyle.title,
                    ),
                  ),
                  Chip(
                    label: CustomText(
                      isDefault ? 'Default' : 'Custom',
                      variant: CustomTextStyle.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CustomSelectableText(
                selectedPath,
                color: Colors.white.withValues(alpha: .78),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _chooseInvoiceFolder,
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                    label: const CustomText(
                      'Choose folder',
                      color: Color(0xFF062026),
                      variant: CustomTextStyle.label,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: isDefault ? null : _resetInvoiceFolder,
                    icon: const Icon(Icons.restore),
                    label: const CustomText(
                      'Reset default',
                      variant: CustomTextStyle.label,
                      color: Color(0xFFB8F4FF),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final dir = Directory(selectedPath);
                      if (!await dir.exists()) {
                        await dir.create(recursive: true);
                      }
                      if (!context.mounted) return;
                      showAppSnack(context, 'Folder is ready');
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const CustomText(
                      'Check folder',
                      variant: CustomTextStyle.label,
                      color: Color(0xFFB8F4FF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (shop != null) ...[
        GlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dashboard_customize_outlined),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: CustomText(
                        'Invoice templates',
                        variant: CustomTextStyle.title,
                      ),
                    ),
                    Text('${db.templates().length}/5'),
                  ],
                ),
                const SizedBox(height: 6),
                const CustomText(
                  'Prepare up to five invoice designs before billing.',
                  color: Colors.white70,
                ),
                const SizedBox(height: 12),
                ...db.templates().map(
                  (template) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      template.isSelected
                          ? Icons.check_circle
                          : Icons.description_outlined,
                    ),
                    title: CustomText(template.organizationName),
                    subtitle: CustomText(
                      template.isSelected ? 'Active for billing' : 'Available',
                      color: Colors.white70,
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Edit template',
                          onPressed: () => _openTemplate(template),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete template',
                          onPressed: () => _deleteTemplate(template),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    onTap: template.isSelected || template.id == null
                        ? null
                        : () {
                            AppDatabase.instance.selectTemplate(template.id!);
                            setState(() {});
                            widget.onChanged();
                          },
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: db.templates().length >= 5
                      ? null
                      : () => _openTemplate(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add template'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        GlassContainer(
          child: ListTile(
            onTap: !_mesh.supported
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MeshrabiyaPage.thisNode(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
            leading: const Icon(Icons.hub_outlined),
            trailing: const Icon(Icons.chevron_right),
            title: const CustomText(
              'Hotspot',
              variant: CustomTextStyle.subtitle,
            ),
            subtitle: CustomText(
              _mesh.state.hotspotEnabled
                  ? 'Hotspot is ready. Tap to open the virtual node screen and QR code.'
                  : 'Create a hotspot and connection QR code.',
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      GlassContainer(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit name'),
              subtitle: Text(activeProfile?.displayName ?? ''),
              onTap: _editProfileName,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('How to use LIMS'),
              onTap: () => showRoleHelp(context, AppRole.shopkeeper),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch profile'),
              subtitle: const Text(
                'Customer and Shopkeeper data stay separate',
              ),
              onTap: widget.onLeaveProfile,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: widget.onLeaveProfile,
            ),
          ],
        ),
      ),
    ];

    return PageFrame(
      title: 'Settings',
      subtitle:
          'Control where invoices are saved and prepare future backup options.',
      scrollable: landscape,
      child: landscape
          ? Column(children: content)
          : ListView(children: content),
    );
  }
}
