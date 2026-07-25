import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_management_system/core/app_database.dart';
import 'package:invoice_management_system/pages/billing/billing_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('large invoices remain a single PDF page', () async {
    final lines = List.generate(
      20,
      (index) => CartLine(
        product: ProductRecord(
          id: index + 1,
          name: 'Professional service package ${index + 1}',
          price: 125 + index.toDouble(),
        ),
        quantity: 2,
      ),
    );
    final total = lines.fold<double>(0, (sum, line) => sum + line.total);

    final bytes = await buildInvoicePdf(
      'INV-PDF-TEST',
      const InvoiceTemplateRecord(
        organizationName: 'Modern Business',
        currency: 'Rs.',
        notes: 'Thank you for choosing our services.',
        terms: 'Payment is due against this invoice.',
      ),
      lines,
      total,
      paymentMethod: 'cash',
    );
    final source = latin1.decode(bytes);
    final pages = RegExp(r'/Type\s*/Page(?!s)\b').allMatches(source).length;

    expect(pages, 1);
  });
}
