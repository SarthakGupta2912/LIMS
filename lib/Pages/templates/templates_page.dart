import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../shared/file_picker_helpers.dart';
import '../../shared/ui.dart';

class TemplatesPage extends StatefulWidget {
  final VoidCallback onChanged;
  const TemplatesPage({super.key, required this.onChanged});

  @override
  State<TemplatesPage> createState() => TemplatesPageState();
}

class TemplatesPageState extends State<TemplatesPage> {
  Future<void> openTemplateDialog([InvoiceTemplateRecord? template]) async {
    final saved = await showTemplateDialog(context, template);
    if (saved == true) {
      setState(() {});
      widget.onChanged();
    }
  }

  void _select(InvoiceTemplateRecord template) {
    final id = template.id;
    if (id == null) return;
    AppDatabase.instance.selectTemplate(id);
    setState(() {});
    widget.onChanged();
  }

  void _delete(InvoiceTemplateRecord template) {
    final id = template.id;
    if (id == null) return;
    AppDatabase.instance.deleteTemplate(id);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final templates = AppDatabase.instance.templates();
    return PageFrame(
      title: 'Invoice Templates',
      subtitle: 'Store business branding, currency, notes, and invoice terms.',
      actions: [
        FilledButton.icon(
          onPressed: () => openTemplateDialog(),
          icon: const Icon(Icons.add),
          label: const CustomText(
            'New template',
            color: Color(0xFF062026),
            variant: CustomTextStyle.label,
          ),
        ),
      ],
      child: templates.isEmpty
          ? EmptyPanel(
              icon: Icons.dashboard_customize_outlined,
              title: 'No templates yet',
              message: 'Create a template before generating invoices.',
              action: FilledButton.icon(
                onPressed: () => openTemplateDialog(),
                icon: const Icon(Icons.add),
                label: const CustomText(
                  'Create template',
                  color: Color(0xFF062026),
                  variant: CustomTextStyle.label,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final singleColumn = constraints.maxWidth < 620;
                return GridView.extent(
                  maxCrossAxisExtent: singleColumn ? 620 : 400,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 196,
                  children: templates.map((template) {
                    return _TemplateCard(
                      template: template,
                      onSelect: () => _select(template),
                      onEdit: () => openTemplateDialog(template),
                      onDelete: () => _delete(template),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final InvoiceTemplateRecord template;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Color(template.accentColor);
    final logo =
        template.logoPath != null && File(template.logoPath!).existsSync();
    return GlassContainer(
      color: template.isSelected
          ? accent.withValues(alpha: .12)
          : const Color(0x2EFFFFFF),
      border: Border.all(
        color: template.isSelected
            ? accent.withValues(alpha: .9)
            : Colors.white.withValues(alpha: .12),
        width: template.isSelected ? 1.6 : 1,
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: logo
                        ? Image.file(
                            File(template.logoPath!),
                            fit: BoxFit.cover,
                          )
                        : Icon(Icons.business, color: accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomText(
                      template.organizationName,
                      variant: CustomTextStyle.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TemplateMetaChip(
                    icon: Icons.payments_outlined,
                    label: template.currency,
                  ),
                  _TemplateMetaChip(
                    icon: template.upiEnabled
                        ? Icons.account_balance_outlined
                        : Icons.payments_outlined,
                    label: template.upiEnabled ? 'Online + cash' : 'Cash only',
                  ),
                  _TemplateMetaChip(
                    icon: logo ? Icons.image_outlined : Icons.business_outlined,
                    label: logo ? 'Custom logo' : 'No logo',
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  if (template.isSelected)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: accent, size: 18),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: CustomText(
                              'Active for billing',
                              variant: CustomTextStyle.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onSelect,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Use template'),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TemplateMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: .7)),
          const SizedBox(width: 5),
          CustomText(
            label,
            variant: CustomTextStyle.caption,
            color: Colors.white.withValues(alpha: .78),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

Future<bool?> showTemplateDialog(
  BuildContext context, [
  InvoiceTemplateRecord? template,
]) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: template?.organizationName ?? '');
  final logo = TextEditingController(text: template?.logoPath ?? '');
  final currency = TextEditingController(text: template?.currency ?? 'Rs.');
  final notes = TextEditingController(
    text: template?.notes ?? 'Thank you for your business.',
  );
  final terms = TextEditingController(
    text: template?.terms ?? 'Payment received.',
  );
  final upiPayeeName = TextEditingController(
    text: template?.upiPayeeName ?? '',
  );
  final upiId = TextEditingController(text: template?.upiId ?? '');
  var upiEnabled = template?.upiEnabled ?? false;
  var accent = template?.accentColor ?? 0xFF2563EB;
  final sourceTemplates = AppDatabase.instance
      .templates()
      .where((item) => item.id != template?.id && item.upiId.isNotEmpty)
      .toList();

  final dialog = showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => GlassDialog(
        title: template == null ? 'Create template' : 'Edit template',
        maxWidth: Breakpoints.compact(context) ? double.infinity : 560,
        actions: [
          TextButton(
            onPressed: () => closeAppDialog(context, false),
            child: const CustomText(
              'Cancel',
              variant: CustomTextStyle.label,
              color: Color(0xFFB8F4FF),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              AppDatabase.instance.saveTemplate(
                InvoiceTemplateRecord(
                  id: template?.id,
                  organizationName: name.text.trim(),
                  logoPath: logo.text.trim().isEmpty ? null : logo.text.trim(),
                  currency: currency.text.trim().isEmpty
                      ? 'Rs.'
                      : currency.text.trim(),
                  accentColor: accent,
                  notes: notes.text.trim(),
                  terms: terms.text.trim(),
                  upiPayeeName: upiPayeeName.text.trim(),
                  upiId: upiId.text.trim(),
                  upiEnabled: upiEnabled,
                  isSelected: template?.isSelected ?? false,
                ),
              );
              closeAppDialog(context, true);
            },
            child: const CustomText(
              'Save',
              color: Color(0xFF062026),
              variant: CustomTextStyle.label,
            ),
          ),
        ],
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Business name'),
                textInputAction: TextInputAction.next,
                validator: _required,
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const CustomText(
                  'Accept online payments',
                  variant: CustomTextStyle.label,
                ),
                value: upiEnabled,
                onChanged: (value) => setDialogState(() => upiEnabled = value),
              ),
              if (upiEnabled && sourceTemplates.isNotEmpty)
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Copy UPI details from template',
                  ),
                  items: sourceTemplates
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.organizationName} - ${item.upiId}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final source = sourceTemplates.firstWhere(
                      (item) => item.id == id,
                    );
                    setDialogState(() {
                      upiPayeeName.text = source.upiPayeeName;
                      upiId.text = source.upiId;
                      upiEnabled = true;
                    });
                  },
                ),
              if (upiEnabled) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: upiPayeeName,
                  decoration: const InputDecoration(
                    labelText: 'UPI payee name',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: upiId,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID (optional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return value.trim().contains('@')
                        ? null
                        : 'Enter a valid UPI ID';
                  },
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                maxLength: 8,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: logo,
                      decoration: const InputDecoration(labelText: 'Logo path'),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Pick logo',
                    onPressed: () async {
                      final picked = await pickImagePath(
                        context: context,
                        title: 'Select logo',
                        pickText: 'Use this logo',
                      );
                      if (picked != null) logo.text = picked;
                    },
                    icon: const Icon(Icons.image_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: CustomText(
                  'Accent color',
                  variant: CustomTextStyle.label,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children:
                    const [
                          0xFF2563EB,
                          0xFF059669,
                          0xFF7C3AED,
                          0xFFDC2626,
                          0xFF111827,
                        ]
                        .map(
                          (color) => ChoiceChip(
                            label: const SizedBox.shrink(),
                            selected: accent == color,
                            avatar: CircleAvatar(backgroundColor: Color(color)),
                            onSelected: (_) =>
                                setDialogState(() => accent = color),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Invoice note'),
                maxLines: 2,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: terms,
                decoration: const InputDecoration(labelText: 'Terms'),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return dialog;
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;
