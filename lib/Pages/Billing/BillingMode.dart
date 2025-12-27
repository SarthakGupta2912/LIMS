import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../Functions/Functions.dart';
import '../../Modals.dart';
import '../../Widgets/Widgets.dart';
import '../InvoiceDesign/InvoiceDesign.dart';

class BillingMode extends StatefulWidget {
  final String? saveFileLocation;
  const BillingMode({super.key, required this.saveFileLocation});

  @override
  State<BillingMode> createState() => _BillingModeState();
}

class _BillingModeState extends State<BillingMode> {
  final Map<Product, int> _cart = {};

  void _addToCart(Product product, int quantity) {
    if (quantity <= 0) return;
    setState(() {
      _cart[product] = quantity;

      // if (_cart.containsKey(product)) {
      //   _cart[product] = _cart[product]! + quantity;
      // } else {
      //   _cart[product] = quantity;
      // }
    });
    showToast("Added $quantity ${product.name} to cart", context);
  }

  void _showQuantityDialog(Product product) {
    final TextEditingController quantityController = TextEditingController(
      text: "1",
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(media.height * 0.02),
          ),
          child: Padding(
            padding: EdgeInsets.all(media.width * 0.04),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MyTextWidget(
                    text: "Add Quantity",
                    textType: "Heading",
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: media.height * 0.02),
                  MyTextWidget(
                    text: "Enter quantity for ${product.name}",
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: media.height * 0.02),
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: customInputDecoration(
                      label: "Quantity",
                      hint: "Enter quantity",
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Required";
                      }
                      if (int.tryParse(value) == null ||
                          int.parse(value) <= 0) {
                        return "Invalid quantity";
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: media.height * 0.03),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Button(
                        text: "Cancel",
                        color: Colors.grey,
                        textcolor: Colors.white,
                        height: media.height * 0.06,
                        width: media.width * 0.25,
                        onTap: () => pop(context),
                      ),
                      Button(
                        text: "Add",
                        color: Colors.green,
                        textcolor: Colors.white,
                        height: media.height * 0.06,
                        width: media.width * 0.25,
                        onTap: () {
                          if (formKey.currentState!.validate()) {
                            _addToCart(
                              product,
                              int.parse(quantityController.text),
                            );
                            pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<InvoiceTemplate?> _getSelectedTemplate() async {
    if (widget.saveFileLocation == null || widget.saveFileLocation!.isEmpty) {
      return null;
    }
    final file = File('${widget.saveFileLocation}/invoice_templates.json');
    if (await file.exists()) {
      try {
        final String templatesJson = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(templatesJson);
        final templates = decoded
            .map((e) => InvoiceTemplate.fromMap(e))
            .toList();
        // Return selected template, or first if only 1 exists (fallback logic)
        try {
          return templates.firstWhere((t) => t.isSelected);
        } catch (e) {
          if (templates.length == 1) return templates.first;
          return null;
        }
      } catch (e) {
        debugPrint("Error loading templates: $e");
      }
    }
    return null;
  }

  Future<void> _generatePdf() async {
    final template = await _getSelectedTemplate();
    if (template == null) {
      showToast("Please select an invoice template first.", context);
      return;
    }

    final pdf = pw.Document();
    final image =
        template.logoPath != null && File(template.logoPath!).existsSync()
        ? pw.MemoryImage(File(template.logoPath!).readAsBytesSync())
        : null;

    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();

    double totalAmount = 0;
    _cart.forEach((key, value) {
      totalAmount += key.price * value;
    });

    final String currencySymbol = template.currency ?? '';

    // 🔹 Modern PDF Design
    final baseColor = PdfColors.indigo900;
    final accentColor = PdfColors.indigo100;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Header Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (image != null)
                        pw.Container(
                          width: 80,
                          height: 80,
                          margin: const pw.EdgeInsets.only(bottom: 10),
                          child: pw.Image(image),
                        ),
                      pw.Text(
                        template.organizationName,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 26,
                          color: baseColor,
                        ),
                      ),
                      pw.Text(
                        "Date: ${DateTime.now().toString().split(' ')[0]}",
                        style: pw.TextStyle(font: font, fontSize: 14),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "INVOICE",
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 40,
                          color: PdfColors.grey300,
                        ),
                      ),
                      pw.Text(
                        "INV-${DateTime.now().millisecondsSinceEpoch}",
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 16,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 40),

              // 2. Table Section
              pw.TableHelper.fromTextArray(
                headers: ['Item', 'Quantity', 'Per Unit Price', 'Subtotal'],
                data: _cart.entries.map((entry) {
                  final product = entry.key;
                  final quantity = entry.value;
                  final subtotal = product.price * quantity;
                  return [
                    product.name,
                    quantity.toString(),
                    '$currencySymbol${product.price.toStringAsFixed(2)}',
                    '$currencySymbol${subtotal.toStringAsFixed(2)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  font: boldFont,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: pw.BoxDecoration(color: baseColor),
                rowDecoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
                cellStyle: pw.TextStyle(font: font),
                cellAlignment: pw.Alignment.center,
                cellAlignments: {
                  1: pw.Alignment.center,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                },
                cellPadding: const pw.EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 10,
                ),
                oddRowDecoration: pw.BoxDecoration(color: accentColor),
              ),
              pw.SizedBox(height: 20),

              // 3. Totals Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Total Amount Due",
                        style: pw.TextStyle(font: font, fontSize: 14),
                      ),
                      pw.Text(
                        "$currencySymbol${totalAmount.toStringAsFixed(2)}",
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 24,
                          color: baseColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),

              // 4. Footer
              pw.Divider(color: baseColor),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  "Thank you!",
                  style: pw.TextStyle(
                    font: boldFont,
                    color: PdfColors.grey700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    final String fileName =
        "Invoice_${DateTime.now().millisecondsSinceEpoch}.pdf";

    // Ensure invoices folder exists (safety check)
    final invoicesDir = Directory("${widget.saveFileLocation}/invoices");
    if (!await invoicesDir.exists()) {
      await invoicesDir.create(recursive: true);
    }

    final String path = "${invoicesDir.path}/$fileName";
    final File file = File(path);
    await file.writeAsBytes(await pdf.save());
    setState(() {
      _cart.clear();
    });
    await showSuccessDialog(
      context,
      "Invoice saved to ${invoicesDir.path}",
      // BillingMode(saveFileLocation: widget.saveFileLocation),
    );

    // Optionally open the PDF
    // await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  void _showCart() {
    bool isGenerating = false;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Container(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MyTextWidget(text: "Cart Items", textType: "Heading"),
                  SizedBox(height: 10),
                  if (_cart.isEmpty)
                    MyTextWidget(text: "Cart is empty")
                  else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          final product = _cart.keys.elementAt(index);
                          final quantity = _cart[product];
                          return ListTile(
                            title: MyTextWidget(text: product.name),
                            subtitle: MyTextWidget(
                              text:
                                  "Qty: $quantity | Price: ${product.price * quantity!}",
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                setState(() {
                                  _cart.remove(product);
                                });
                                setSheetState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  if (_cart.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Button(
                        text: "Proceed & Generate Invoice",
                        isLoading: isGenerating,
                        height: media.height * 0.06,
                        width: media.width * 0.4,
                        color: Colors.blue,
                        textcolor: Colors.white,
                        onTap: () async {
                          if (isGenerating) return;
                          setSheetState(() => isGenerating = true);
                          try {
                            await _generatePdf();
                            if (context.mounted) {
                              pop(context); // Close bottom sheet
                            }
                          } finally {
                            if (context.mounted) {
                              setSheetState(() => isGenerating = false);
                            }
                          }
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppbar(
        appBarTitle: 'Billing Mode',
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "Cart",
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                onPressed: _showCart,
              ),
              if (_cart.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${_cart.length}',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (products.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      title: MyTextWidget(text: product.name),
                      subtitle: MyTextWidget(
                        text: "ID: ${product.id} | Price: ${product.price}",
                      ),
                      trailing: IconButton(
                        tooltip: "Add Quantity",
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () => _showQuantityDialog(product),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              MyTextWidget(text: "No products available"),
            ],
          ],
        ),
      ),
    );
  }
}
