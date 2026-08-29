import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../shared/ui.dart';

class ProductsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const ProductsPage({super.key, required this.onChanged});

  @override
  State<ProductsPage> createState() => ProductsPageState();
}

class ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  final _selected = <int>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> openProductDialog([ProductRecord? product]) async {
    final saved = await showProductDialog(context, product);
    if (saved == true) {
      setState(_selected.clear);
      widget.onChanged();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: count == 1 ? 'Delete product?' : 'Delete products?',
      message: count == 1
          ? 'This product will be permanently deleted.'
          : '$count selected products will be permanently deleted.',
      confirmLabel: count == 1 ? 'Delete product' : 'Delete $count',
    );
    if (!confirmed || !mounted) return;
    AppDatabase.instance.deleteProducts(_selected);
    setState(_selected.clear);
    widget.onChanged();
    showAppSnack(
      context,
      count == 1 ? 'Deleted product' : 'Deleted selected products',
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = AppDatabase.instance.products(query: _search.text);
    final landscape = Breakpoints.landscapeMobile(context);
    return PageFrame(
      title: 'Products',
      subtitle: 'Maintain the items and services you bill most often.',
      actions: [
        if (_selected.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline),
            label: CustomText(
              'Delete ${_selected.length}',
              variant: CustomTextStyle.label,
              color: const Color(0xFFB8F4FF),
            ),
          ),
        FilledButton.icon(
          onPressed: () => openProductDialog(),
          icon: const Icon(Icons.add),
          label: const CustomText(
            'Add product',
            color: Color(0xFF062026),
            variant: CustomTextStyle.label,
          ),
        ),
      ],
      scrollable: landscape,
      child: Column(
        mainAxisSize: landscape ? MainAxisSize.min : MainAxisSize.max,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by product name',
            ),
          ),
          const SizedBox(height: 14),
          if (landscape)
            _MobileProductList(
              products: products,
              selected: _selected,
              onSelect: _toggle,
              onEdit: openProductDialog,
              shrinkWrap: true,
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final listLayout =
                      Breakpoints.mobileOrTablet || constraints.maxWidth < 760;
                  return products.isEmpty
                      ? EmptyPanel(
                          icon: Icons.inventory_2_outlined,
                          title: 'No products found',
                          message:
                              'Add products once and reuse them while creating invoices.',
                          action: FilledButton.icon(
                            onPressed: () => openProductDialog(),
                            icon: const Icon(Icons.add),
                            label: const CustomText(
                              'Add product',
                              color: Color(0xFF062026),
                              variant: CustomTextStyle.label,
                            ),
                          ),
                        )
                      : listLayout
                      ? _MobileProductList(
                          products: products,
                          selected: _selected,
                          onSelect: _toggle,
                          onEdit: openProductDialog,
                        )
                      : _ProductTable(
                          products: products,
                          selected: _selected,
                          onSelect: _toggle,
                          onEdit: openProductDialog,
                        );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _toggle(ProductRecord product, bool selected) {
    final id = product.id;
    if (id == null) return;
    setState(() => selected ? _selected.add(id) : _selected.remove(id));
  }
}

class _ProductTable extends StatelessWidget {
  final List<ProductRecord> products;
  final Set<int> selected;
  final void Function(ProductRecord product, bool selected) onSelect;
  final void Function(ProductRecord product) onEdit;

  const _ProductTable({
    required this.products,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              showCheckboxColumn: true,
              columns: const [
                DataColumn(
                  label: CustomText('Product', variant: CustomTextStyle.label),
                ),
                DataColumn(
                  label: CustomText('Price', variant: CustomTextStyle.label),
                ),
                DataColumn(
                  label: CustomText('Profit', variant: CustomTextStyle.label),
                ),
                DataColumn(
                  label: CustomText('Stock', variant: CustomTextStyle.label),
                ),
                DataColumn(
                  label: CustomText('Actions', variant: CustomTextStyle.label),
                ),
              ],
              rows: products.map((product) {
                final isSelected = selected.contains(product.id);
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (value) => onSelect(product, value ?? false),
                  cells: [
                    DataCell(
                      CustomText(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(CustomText(money(product.price))),
                    DataCell(
                      CustomText(
                        '${product.profitPercent.toStringAsFixed(1)}%',
                      ),
                    ),
                    DataCell(CustomText('${product.stockQuantity}')),
                    DataCell(
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => onEdit(product),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileProductList extends StatelessWidget {
  final List<ProductRecord> products;
  final Set<int> selected;
  final void Function(ProductRecord product, bool selected) onSelect;
  final void Function(ProductRecord product) onEdit;
  final bool shrinkWrap;

  const _MobileProductList({
    required this.products,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final product = products[index];
        final isSelected = selected.contains(product.id);
        return GlassContainer(
          child: CheckboxListTile(
            value: isSelected,
            onChanged: (value) => onSelect(product, value ?? false),
            title: CustomText(
              product.name,
              variant: CustomTextStyle.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: CustomText(
              '${money(product.price)}  -  Profit ${product.profitPercent.toStringAsFixed(1)}%  -  Stock ${product.stockQuantity}',
              variant: CustomTextStyle.caption,
              color: Colors.white.withValues(alpha: .72),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            secondary: IconButton(
              tooltip: 'Edit',
              onPressed: () => onEdit(product),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        );
      },
    );
  }
}

Future<bool?> showProductDialog(
  BuildContext context, [
  ProductRecord? product,
]) {
  final formKey = GlobalKey<FormState>();
  final nameKey = GlobalKey<FormFieldState<String>>();
  final priceKey = GlobalKey<FormFieldState<String>>();
  final profitKey = GlobalKey<FormFieldState<String>>();
  final name = TextEditingController(text: product?.name ?? '');
  final price = TextEditingController(text: product?.price.toString() ?? '');
  final profit = TextEditingController(
    text: product?.profitPercent.toString() ?? '0',
  );
  final stock = TextEditingController(text: '${product?.stockQuantity ?? 0}');
  var showErrors = false;

  final dialog = showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .18),
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => GlassDialog(
        title: product == null ? 'Add product' : 'Edit product',
        maxWidth: Breakpoints.compact(context) ? double.infinity : 480,
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
              setDialogState(() => showErrors = true);
              if (!validateFormAndScrollToFirstError(formKey, [
                nameKey,
                priceKey,
                profitKey,
              ])) {
                return;
              }
              AppDatabase.instance.saveProduct(
                ProductRecord(
                  id: product?.id,
                  name: name.text.trim(),
                  price: double.parse(price.text),
                  profitPercent: double.tryParse(profit.text) ?? 0,
                  stockQuantity: int.tryParse(stock.text) ?? 0,
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
                key: nameKey,
                controller: name,
                decoration: const InputDecoration(labelText: 'Product name'),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (showErrors) setDialogState(() => showErrors = false);
                },
                validator: (value) {
                  if (!showErrors) return null;
                  final requiredError = _required(value);
                  if (requiredError != null) return requiredError;
                  final exists = AppDatabase.instance.productNameExists(
                    value!,
                    exceptId: product?.id,
                  );
                  return exists
                      ? 'A product with this name already exists'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: priceKey,
                controller: price,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) {
                  if (showErrors) setDialogState(() => showErrors = false);
                },
                validator: (value) {
                  if (!showErrors) return null;
                  return (double.tryParse(value ?? '') ?? -1) >= 0
                      ? null
                      : 'Enter a valid price';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: profitKey,
                controller: profit,
                decoration: const InputDecoration(labelText: 'Profit %'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) {
                  if (showErrors) setDialogState(() => showErrors = false);
                },
                validator: (value) {
                  if (!showErrors) return null;
                  return (double.tryParse(value ?? '') ?? -1) >= 0
                      ? null
                      : 'Enter a valid profit percentage';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: stock,
                decoration: const InputDecoration(labelText: 'Stock quantity'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
