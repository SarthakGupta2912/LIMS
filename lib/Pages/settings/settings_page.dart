import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import '../../shared/file_picker_helpers.dart';
import '../../shared/ui.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onChanged;

  const SettingsPage({super.key, required this.onChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _chooseInvoiceFolder() async {
    final picked = await pickFolderPath(
      context: context,
      title: 'Choose invoice save folder',
      pickText: 'Use this folder',
    );
    if (picked == null || picked.trim().isEmpty) return;

    AppDatabase.instance.setInvoiceSaveDir(picked);
    await AppDatabase.instance.ensureInvoiceSaveDir();
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    showAppSnack(context, 'Invoice folder updated');
  }

  Future<void> _resetInvoiceFolder() async {
    AppDatabase.instance.resetInvoiceSaveDir();
    await AppDatabase.instance.ensureInvoiceSaveDir();
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    showAppSnack(context, 'Invoice folder reset to default');
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase.instance;
    final selectedPath = db.invoiceSaveDir();
    final isDefault = selectedPath == db.defaultInvoiceDir;

    return PageFrame(
      title: 'Settings',
      subtitle:
          'Control where invoices are saved and prepare future backup options.',
      child: ListView(
        children: [
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
          const EmptyPanel(
            icon: Icons.backup_outlined,
            title: 'Backup tools coming next',
            message:
                'This settings area is ready for export, import, and restore features.',
          ),
        ],
      ),
    );
  }
}
