import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../shared/ui.dart';

class BillingPage extends StatefulWidget {
  final VoidCallback onChanged;
  final VoidCallback onNeedTemplate;
  final VoidCallback onNeedProduct;

  const BillingPage({
    super.key,
    required this.onChanged,
    required this.onNeedTemplate,
    required this.onNeedProduct,
  });

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  final _search = TextEditingController();
  final _cart = <int, CartLine>{};
  bool _generating = false;

  List<CartLine> get _lines => _cart.values.toList();
  double get _total => _lines.fold(0, (sum, line) => sum + line.total);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _changeQty(ProductRecord product, int delta) {
    if (_generating) return;
    final id = product.id;
    if (id == null) return;
    final qty = (_cart[id]?.quantity ?? 0) + delta;
    setState(() {
      if (qty <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = CartLine(product: product, quantity: qty);
      }
    });
  }

  Future<bool> _generateInvoice() async {
    if (_cart.isEmpty || _generating) return false;
    final lines = _lines;
    final total = _total;
    if (lines.isEmpty || total < 0) return false;

    final template = AppDatabase.instance.selectedTemplate();
    if (template == null) {
      showAppSnack(context, 'Create and select an invoice template first');
      widget.onNeedTemplate();
      return false;
    }
    if (template.id == null) {
      showAppSnack(context, 'Select a saved invoice template first');
      widget.onNeedTemplate();
      return false;
    }
    final payment = await _showPaymentDetailsDialog(
      context,
      onlineEnabled: template.upiEnabled,
      payeeName: template.upiPayeeName,
      upiId: template.upiId,
    );
    if (payment == null) return false;
    setState(() => _generating = true);
    try {
      final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      final dir = await AppDatabase.instance.ensureInvoiceSaveDir();
      final path = p.join(dir.path, '$invoiceNumber.pdf');
      final bytes = await buildInvoicePdf(
        invoiceNumber,
        template,
        lines,
        total,
        upiPayeeName:
            payment.mode == PaymentMode.online && payment.onlineMethod == 'upi'
            ? payment.payeeName
            : '',
        upiId:
            payment.mode == PaymentMode.online && payment.onlineMethod == 'upi'
            ? payment.upiId
            : '',
        paymentMethod: payment.mode == PaymentMode.cash
            ? 'cash'
            : payment.onlineMethod,
      );
      await File(path).writeAsBytes(bytes);
      AppDatabase.instance.saveInvoice(
        invoiceNumber: invoiceNumber,
        lines: lines,
        templateId: template.id,
        total: total,
        pdfPath: path,
        upiPayeeName:
            payment.mode == PaymentMode.online && payment.onlineMethod == 'upi'
            ? payment.payeeName
            : '',
        upiId:
            payment.mode == PaymentMode.online && payment.onlineMethod == 'upi'
            ? payment.upiId
            : '',
        paymentMethod: payment.mode == PaymentMode.cash
            ? 'cash'
            : payment.onlineMethod,
      );
      if (payment.mode == PaymentMode.cash) {
        AppDatabase.instance.recordPayment(
          invoiceNumber: invoiceNumber,
          amount: total,
          method: 'cash',
        );
      } else {
        if (!mounted) return true;
        await showPaymentCollectionDialog(
          context,
          invoiceNumber: invoiceNumber,
          amount: total,
          payeeName: payment.payeeName,
          upiId: payment.upiId,
          method: payment.onlineMethod,
        );
      }
      if (mounted) {
        setState(_cart.clear);
      }
      widget.onChanged();
      if (mounted) {
        showAppSnack(context, 'Invoice saved: $invoiceNumber');
      }
      return true;
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Could not generate invoice. Please try again.');
      }
      debugPrint('Invoice generation failed: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = AppDatabase.instance.products(query: _search.text);
    final landscape = Breakpoints.landscapeMobile(context);
    return PageFrame(
      title: 'Billing',
      subtitle: 'Create invoices quickly from your saved product catalog.',
      actions: [
        LayoutBuilder(
          builder: (context, constraints) => (_cart.isNotEmpty)
              ? FilledButton.icon(
                  onPressed: _showCartSheet,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: CustomText(
                    'Cart ${_cart.length}',
                    color: const Color(0xFF062026),
                    variant: CustomTextStyle.label,
                  ),
                )
              : SizedBox(),
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
              hintText: 'Search products for this invoice',
            ),
          ),
          const SizedBox(height: 14),
          if (landscape)
            products.isEmpty
                ? EmptyPanel(
                    icon: Icons.point_of_sale,
                    title: 'No products available',
                    message: 'Add products before starting billing.',
                    action: FilledButton.icon(
                      onPressed: widget.onNeedProduct,
                      icon: const Icon(Icons.add),
                      label: const CustomText(
                        'Add product',
                        color: Color(0xFF062026),
                        variant: CustomTextStyle.label,
                      ),
                    ),
                  )
                : _ProductPicker(
                    products: products,
                    cart: _cart,
                    enabled: !_generating,
                    onQty: _changeQty,
                    shrinkWrap: true,
                  )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final splitLayout = constraints.maxWidth >= 820;
                  return products.isEmpty
                      ? EmptyPanel(
                          icon: Icons.point_of_sale,
                          title: 'No products available',
                          message: 'Add products before starting billing.',
                          action: FilledButton.icon(
                            onPressed: widget.onNeedProduct,
                            icon: const Icon(Icons.add),
                            label: const CustomText(
                              'Add product',
                              color: Color(0xFF062026),
                              variant: CustomTextStyle.label,
                            ),
                          ),
                        )
                      : splitLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _ProductPicker(
                                products: products,
                                cart: _cart,
                                enabled: !_generating,
                                onQty: _changeQty,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 340,
                              child: _CartPanel(
                                lines: _lines,
                                total: _total,
                                generating: _generating,
                                onGenerate: _generateInvoice,
                                onQty: _changeQty,
                              ),
                            ),
                          ],
                        )
                      : _ProductPicker(
                          products: products,
                          cart: _cart,
                          enabled: !_generating,
                          onQty: _changeQty,
                        );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> generate() async {
            final generation = _generateInvoice();
            setSheetState(() {});
            final success = await generation;
            if (!context.mounted) return;
            setSheetState(() {});
            if (success && Navigator.canPop(context)) Navigator.pop(context);
          }

          void changeQty(ProductRecord product, int delta) {
            _changeQty(product, delta);
            if (!context.mounted) return;
            if (_cart.isEmpty && Navigator.canPop(context)) {
              Navigator.pop(context);
              return;
            }
            setSheetState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _CartPanel(
              lines: _lines,
              total: _total,
              generating: _generating,
              onGenerate: generate,
              onQty: changeQty,
            ),
          );
        },
      ),
    );
  }
}

class _ProductPicker extends StatelessWidget {
  final List<ProductRecord> products;
  final Map<int, CartLine> cart;
  final bool enabled;
  final void Function(ProductRecord product, int delta) onQty;
  final bool shrinkWrap;

  const _ProductPicker({
    required this.products,
    required this.cart,
    required this.enabled,
    required this.onQty,
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
        final qty = cart[product.id]?.quantity ?? 0;
        return GlassContainer(
          child: ListTile(
            title: CustomText(
              product.name,
              variant: CustomTextStyle.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: CustomText(
              money(product.price),
              variant: CustomTextStyle.caption,
              color: Colors.white.withValues(alpha: .72),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _QtyStepper(
              quantity: qty,
              enabled: enabled,
              onAdd: () => onQty(product, 1),
              onRemove: () => onQty(product, -1),
            ),
          ),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  final List<CartLine> lines;
  final double total;
  final bool generating;
  final Future<void> Function() onGenerate;
  final void Function(ProductRecord product, int delta) onQty;

  const _CartPanel({
    required this.lines,
    required this.total,
    required this.generating,
    required this.onGenerate,
    required this.onQty,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CustomText('Invoice cart', variant: CustomTextStyle.title),
            const SizedBox(height: 12),
            if (lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: CustomText(
                  'Add products to start an invoice.',
                  color: Colors.white.withValues(alpha: .72),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .42,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 14),
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return Row(
                      children: [
                        Expanded(
                          child: CustomText(
                            '${line.product.name}\n${money(line.total)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _QtyStepper(
                          quantity: line.quantity,
                          enabled: !generating,
                          onAdd: () => onQty(line.product, 1),
                          onRemove: () => onQty(line.product, -1),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const CustomText('Total', variant: CustomTextStyle.label),
                CustomText(money(total), variant: CustomTextStyle.label),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: lines.isEmpty || generating
                    ? null
                    : () async => onGenerate(),
                icon: generating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF062026),
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: CustomText(
                  generating ? 'Generating...' : 'Generate invoice',
                  color: const Color(0xFF062026),
                  variant: CustomTextStyle.label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _QtyStepper({
    required this.quantity,
    this.enabled = true,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: !enabled || quantity == 0 ? null : onRemove,
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease',
        ),
        SizedBox(
          width: 28,
          child: CustomText(
            '$quantity',
            variant: CustomTextStyle.label,
            textAlign: TextAlign.center,
          ),
        ),
        IconButton.filled(
          onPressed: enabled ? onAdd : null,
          icon: const Icon(Icons.add),
          tooltip: 'Increase',
        ),
      ],
    );
  }
}

enum PaymentMode { cash, online }

class _PaymentDetails {
  final PaymentMode mode;
  final String payeeName;
  final String upiId;
  final String onlineMethod;

  const _PaymentDetails({
    required this.mode,
    required this.payeeName,
    required this.upiId,
    required this.onlineMethod,
  });
}

Future<_PaymentDetails?> _showPaymentDetailsDialog(
  BuildContext context, {
  required bool onlineEnabled,
  required String payeeName,
  required String upiId,
}) {
  var mode = onlineEnabled ? PaymentMode.online : PaymentMode.cash;
  var onlineMethod = upiId.trim().contains('@') ? 'upi' : 'card';
  final payee = TextEditingController(text: payeeName);
  final upi = TextEditingController(text: upiId);
  return showDialog<_PaymentDetails>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => GlassDialog(
        title: 'Payment method',
        actions: [
          TextButton(
            onPressed: () => closeAppDialog(context),
            child: const CustomText('Cancel', variant: CustomTextStyle.label),
          ),
          FilledButton(
            onPressed: () {
              if (mode == PaymentMode.online &&
                  onlineMethod == 'upi' &&
                  !upi.text.trim().contains('@')) {
                showAppSnack(context, 'Enter a valid UPI ID or choose cash');
                return;
              }
              closeAppDialog(
                context,
                _PaymentDetails(
                  mode: mode,
                  payeeName: payee.text.trim(),
                  upiId: upi.text.trim(),
                  onlineMethod: onlineMethod,
                ),
              );
            },
            child: const CustomText(
              'Continue',
              color: Color(0xFF062026),
              variant: CustomTextStyle.label,
            ),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<PaymentMode>(
              segments: [
                const ButtonSegment(
                  value: PaymentMode.cash,
                  label: Text('Cash'),
                ),
                if (onlineEnabled)
                  const ButtonSegment(
                    value: PaymentMode.online,
                    label: Text('Online'),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: (value) => setState(() => mode = value.first),
            ),
            if (mode == PaymentMode.online) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: onlineMethod,
                decoration: const InputDecoration(labelText: 'Online method'),
                items: const [
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(
                    value: 'bank_transfer',
                    child: Text('Bank transfer'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => onlineMethod = value ?? 'upi'),
              ),
              if (onlineMethod == 'upi') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: payee,
                  decoration: const InputDecoration(
                    labelText: 'UPI payee name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: upi,
                  decoration: const InputDecoration(labelText: 'UPI ID'),
                ),
              ],
              const SizedBox(height: 10),
              const CustomText(
                'Payment will remain pending until you confirm it from your UPI app or bank statement.',
                variant: CustomTextStyle.caption,
                color: Colors.white70,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> showPaymentCollectionDialog(
  BuildContext context, {
  required String invoiceNumber,
  required double amount,
  required String payeeName,
  required String upiId,
  String method = 'upi',
}) async {
  final note = TextEditingController();
  final reference = TextEditingController();
  final uri = _upiUri(
    invoiceNumber: invoiceNumber,
    amount: amount,
    payeeName: payeeName,
    upiId: upiId,
  );
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => GlassDialog(
      title: 'Collect payment',
      actions: [
        TextButton(
          onPressed: () => closeAppDialog(context),
          child: const CustomText('Next bill', variant: CustomTextStyle.label),
        ),
        FilledButton(
          onPressed: () {
            AppDatabase.instance.recordPayment(
              invoiceNumber: invoiceNumber,
              amount: amount,
              method: method,
              note: reference.text.trim(),
            );
            closeAppDialog(context, true);
          },
          child: const CustomText(
            'Payment successful',
            color: Color(0xFF062026),
            variant: CustomTextStyle.label,
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(invoiceNumber, variant: CustomTextStyle.title),
          const SizedBox(height: 4),
          CustomText(money(amount), variant: CustomTextStyle.display),
          if (method == 'upi' && upiId.isNotEmpty) ...[
            const SizedBox(height: 16),
            QrImageView(data: uri, size: 190, backgroundColor: Colors.white),
            const SizedBox(height: 8),
            CustomText(
              '$payeeName  -  $upiId',
              variant: CustomTextStyle.caption,
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: reference,
            decoration: const InputDecoration(
              labelText: 'UTR / payment reference (optional)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Failure or pending note (optional)',
            ),
          ),
          const SizedBox(height: 8),
          const CustomText(
            'If the bank is delayed, choose Next bill. This invoice stays pending and can be completed later.',
            variant: CustomTextStyle.caption,
            color: Colors.white70,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
  if (paid != true && note.text.trim().isNotEmpty) {
    AppDatabase.instance.updateInvoicePayment(
      invoiceNumber,
      'payment_pending',
      note: note.text.trim(),
    );
  }
  reference.dispose();
  note.dispose();
}

String _upiUri({
  required String invoiceNumber,
  required double amount,
  required String payeeName,
  required String upiId,
}) {
  final query = <String, String>{
    'pa': upiId,
    'pn': payeeName,
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    'tn': invoiceNumber,
  };
  return 'upi://pay?${query.entries.map((entry) => '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}').join('&')}';
}

Future<List<int>> buildInvoicePdf(
  String number,
  InvoiceTemplateRecord template,
  List<CartLine> lines,
  double total, {
  String upiPayeeName = '',
  String upiId = '',
  String paymentMethod = 'cash',
}) async {
  final pdf = pw.Document();
  final accent = PdfColor.fromInt(template.accentColor);
  const ink = PdfColor.fromInt(0xFF172126);
  const muted = PdfColor.fromInt(0xFF66747C);
  const lineColor = PdfColor.fromInt(0xFFDDE4E7);
  const softBackground = PdfColor.fromInt(0xFFF4F7F8);
  final baseFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Poppins-Bold.ttf'),
  );
  final watermark = pw.MemoryImage(
    (await rootBundle.load(
      'assets/invoice-manager-logo-wordmark.png',
    )).buffer.asUint8List(),
  );
  final logo =
      template.logoPath != null && File(template.logoPath!).existsSync()
      ? pw.MemoryImage(await File(template.logoPath!).readAsBytes())
      : null;
  final regular = pw.TextStyle(font: baseFont, color: ink, fontSize: 9);
  final bold = pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold);
  final date = DateTime.now();
  final issueDate =
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
  final paymentLabel = switch (paymentMethod) {
    'upi' => 'UPI payment',
    'card' => 'Card payment',
    'bank_transfer' => 'Bank transfer',
    'other' => 'Online payment',
    _ => 'Cash payment',
  };
  final paymentPending = paymentMethod != 'cash';
  final compact = lines.length > 8;
  final veryCompact = lines.length > 14;
  final cellVertical = veryCompact
      ? 3.0
      : compact
      ? 4.0
      : 6.0;
  final body = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: pw.BoxDecoration(
          color: accent,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Container(
                width: 64,
                height: 64,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(7),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 5,
                  verticalRadius: 5,
                  child: pw.Center(
                    child: pw.Image(
                      logo,
                      width: 54,
                      height: 54,
                      fit: pw.BoxFit.contain,
                      alignment: pw.Alignment.center,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    template.organizationName,
                    maxLines: 2,
                    style: bold.copyWith(color: PdfColors.white, fontSize: 20),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Professional invoice',
                    style: regular.copyWith(
                      color: PdfColors.white,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(
              width: 155,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'INVOICE',
                    style: bold.copyWith(color: PdfColors.white, fontSize: 25),
                  ),
                  pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      number,
                      style: regular.copyWith(
                        color: PdfColors.white,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(
        children: [
          pw.Expanded(
            child: _pdfInfoBlock(
              label: 'ISSUE DATE',
              value: issueDate,
              regular: regular,
              bold: bold,
              muted: muted,
              lineColor: lineColor,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfInfoBlock(
              label: 'PAYMENT',
              value: paymentLabel,
              regular: regular,
              bold: bold,
              muted: muted,
              lineColor: lineColor,
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _pdfInfoBlock(
              label: 'STATUS',
              value: paymentPending ? 'Payment pending' : 'Paid',
              regular: regular,
              bold: bold,
              muted: muted,
              lineColor: lineColor,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: lineColor, width: .7),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(27),
            1: pw.FlexColumnWidth(4.6),
            2: pw.FlexColumnWidth(1.1),
            3: pw.FlexColumnWidth(2),
            4: pw.FlexColumnWidth(2),
          },
          border: pw.TableBorder(
            horizontalInside: const pw.BorderSide(color: lineColor, width: .45),
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: ink),
              children: [
                _pdfTableCell('#', bold, color: PdfColors.white),
                _pdfTableCell('ITEM DESCRIPTION', bold, color: PdfColors.white),
                _pdfTableCell(
                  'QTY',
                  bold,
                  color: PdfColors.white,
                  alignment: pw.Alignment.centerRight,
                ),
                _pdfTableCell(
                  'UNIT PRICE',
                  bold,
                  color: PdfColors.white,
                  alignment: pw.Alignment.centerRight,
                ),
                _pdfTableCell(
                  'AMOUNT',
                  bold,
                  color: PdfColors.white,
                  alignment: pw.Alignment.centerRight,
                ),
              ],
            ),
            ...lines.indexed.map((entry) {
              final line = entry.$2;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: entry.$1.isOdd ? softBackground : PdfColors.white,
                ),
                children: [
                  _pdfTableCell(
                    '${entry.$1 + 1}',
                    regular,
                    vertical: cellVertical,
                  ),
                  _pdfTableCell(
                    line.product.name,
                    regular,
                    vertical: cellVertical,
                  ),
                  _pdfTableCell(
                    '${line.quantity}',
                    regular,
                    vertical: cellVertical,
                    alignment: pw.Alignment.centerRight,
                  ),
                  _pdfTableCell(
                    money(line.product.price, template.currency),
                    regular,
                    vertical: cellVertical,
                    alignment: pw.Alignment.centerRight,
                  ),
                  _pdfTableCell(
                    money(line.total, template.currency),
                    bold.copyWith(fontSize: 9, color: ink),
                    vertical: cellVertical,
                    alignment: pw.Alignment.centerRight,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: upiId.isNotEmpty
                ? pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: softBackground,
                      border: pw.Border.all(color: lineColor, width: .7),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Container(
                          width: 82,
                          height: 82,
                          padding: const pw.EdgeInsets.all(5),
                          color: PdfColors.white,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: _upiUri(
                              invoiceNumber: number,
                              amount: total,
                              payeeName: upiPayeeName,
                              upiId: upiId,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'SCAN TO PAY',
                                style: bold.copyWith(
                                  color: accent,
                                  fontSize: 10,
                                ),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                upiPayeeName,
                                style: bold.copyWith(fontSize: 9, color: ink),
                              ),
                              pw.Text(
                                upiId,
                                style: regular.copyWith(fontSize: 8),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'Reference: $number',
                                style: regular.copyWith(
                                  fontSize: 7.5,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: softBackground,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      paymentPending
                          ? 'Online payment pending confirmation.'
                          : 'Payment received. Thank you for your business.',
                      style: regular.copyWith(color: muted),
                    ),
                  ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(13),
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    paymentPending ? 'TOTAL DUE' : 'TOTAL PAID',
                    textAlign: pw.TextAlign.right,
                    style: regular.copyWith(
                      color: PdfColors.white,
                      fontSize: 8,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      money(total, template.currency),
                      style: bold.copyWith(
                        color: PdfColors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      if (template.notes.isNotEmpty || template.terms.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (template.notes.isNotEmpty)
              pw.Expanded(
                child: _pdfTextSection(
                  title: 'NOTE',
                  value: template.notes,
                  regular: regular,
                  bold: bold,
                  muted: muted,
                ),
              ),
            if (template.notes.isNotEmpty && template.terms.isNotEmpty)
              pw.SizedBox(width: 18),
            if (template.terms.isNotEmpty)
              pw.Expanded(
                child: _pdfTextSection(
                  title: 'TERMS',
                  value: template.terms,
                  regular: regular,
                  bold: bold,
                  muted: muted,
                ),
              ),
          ],
        ),
      ],
    ],
  );

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
      build: (context) => pw.Stack(
        fit: pw.StackFit.expand,
        children: [
          pw.Positioned.fill(child: pw.Container(color: PdfColors.white)),
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Opacity(
                opacity: .045,
                child: pw.Image(
                  watermark,
                  width: 260,
                  height: 320,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          ),
          pw.Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: pw.Container(width: 7, color: accent),
          ),
          pw.Positioned(
            left: 30,
            right: 24,
            top: 24,
            bottom: 54,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topLeft,
              child: pw.SizedBox(
                width: PdfPageFormat.a4.width - 54,
                child: body,
              ),
            ),
          ),
          pw.Positioned(
            left: 7,
            right: 0,
            bottom: 0,
            child: pw.Container(
              height: 42,
              padding: const pw.EdgeInsets.symmetric(horizontal: 23),
              decoration: const pw.BoxDecoration(
                color: softBackground,
                border: pw.Border(
                  top: pw.BorderSide(color: lineColor, width: .7),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      template.organizationName,
                      maxLines: 1,
                      style: regular.copyWith(fontSize: 7.5, color: muted),
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Text(
                    '$number  |  Generated $issueDate',
                    style: regular.copyWith(fontSize: 7.5, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}

pw.Widget _pdfInfoBlock({
  required String label,
  required String value,
  required pw.TextStyle regular,
  required pw.TextStyle bold,
  required PdfColor muted,
  required PdfColor lineColor,
}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: lineColor, width: .7),
    borderRadius: pw.BorderRadius.circular(5),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: regular.copyWith(fontSize: 7, color: muted)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: bold.copyWith(
          fontSize: 9,
          color: const PdfColor.fromInt(0xFF172126),
        ),
      ),
    ],
  ),
);

pw.Widget _pdfTableCell(
  String value,
  pw.TextStyle style, {
  PdfColor? color,
  double vertical = 6,
  pw.Alignment alignment = pw.Alignment.centerLeft,
}) => pw.Container(
  alignment: alignment,
  padding: pw.EdgeInsets.symmetric(horizontal: 7, vertical: vertical),
  child: pw.Text(
    value,
    maxLines: 2,
    style: color == null ? style : style.copyWith(color: color),
  ),
);

pw.Widget _pdfTextSection({
  required String title,
  required String value,
  required pw.TextStyle regular,
  required pw.TextStyle bold,
  required PdfColor muted,
}) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(title, style: bold.copyWith(fontSize: 8.5, color: muted)),
    pw.SizedBox(height: 3),
    pw.Text(
      value,
      maxLines: 3,
      style: regular.copyWith(fontSize: 8, color: muted),
    ),
  ],
);
