import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import '../billing/billing_page.dart';
import '../../shared/ui.dart';

class InvoicesPage extends StatefulWidget {
  final VoidCallback onChanged;

  const InvoicesPage({super.key, required this.onChanged});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _search = TextEditingController();
  int _page = 0;
  String _status = 'all';
  String _sort = 'newest';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = AppDatabase.instance.invoicePage(
      page: _page,
      query: _search.text,
      status: _status,
      sort: _sort,
    );
    final pageCount = result.pageCount;
    if (_page >= pageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = pageCount - 1);
      });
    }

    return PageFrame(
      title: 'Invoices',
      subtitle: 'Search, review, and follow up on every invoice.',
      child: Column(
        children: [
          _InvoiceFilters(
            search: _search,
            status: _status,
            sort: _sort,
            onSearch: () => setState(() => _page = 0),
            onStatus: (value) => setState(() {
              _status = value;
              _page = 0;
            }),
            onSort: (value) => setState(() {
              _sort = value;
              _page = 0;
            }),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: result.invoices.isEmpty
                ? const EmptyPanel(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices found',
                    message: 'Try changing the search or filter.',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth < 760
                        ? _InvoiceList(
                            invoices: result.invoices,
                            onChanged: widget.onChanged,
                          )
                        : _InvoiceTable(
                            invoices: result.invoices,
                            onChanged: widget.onChanged,
                          ),
                  ),
          ),
          const SizedBox(height: 12),
          _InvoicePagination(
            page: _page,
            pageCount: pageCount,
            total: result.total,
            onPrevious: _page == 0 ? null : () => setState(() => _page--),
            onNext: _page >= pageCount - 1
                ? null
                : () => setState(() => _page++),
          ),
        ],
      ),
    );
  }
}

class _InvoiceFilters extends StatelessWidget {
  final TextEditingController search;
  final String status;
  final String sort;
  final VoidCallback onSearch;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSort;

  const _InvoiceFilters({
    required this.search,
    required this.status,
    required this.sort,
    required this.onSearch,
    required this.onStatus,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final searchField = TextField(
          controller: search,
          onChanged: (_) => onSearch(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search invoice number or note',
          ),
        );
        final controls = [
          DropdownButtonFormField<String>(
            initialValue: status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All invoices')),
              DropdownMenuItem(
                value: 'payment_pending',
                child: Text('Pending'),
              ),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
            ],
            onChanged: (value) => onStatus(value ?? 'all'),
          ),
          DropdownButtonFormField<String>(
            initialValue: sort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: const [
              DropdownMenuItem(value: 'newest', child: Text('Newest first')),
              DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
              DropdownMenuItem(
                value: 'amount_high',
                child: Text('Highest amount'),
              ),
              DropdownMenuItem(
                value: 'amount_low',
                child: Text('Lowest amount'),
              ),
            ],
            onChanged: (value) => onSort(value ?? 'newest'),
          ),
        ];
        if (narrow) {
          return Column(
            children: [
              searchField,
              const SizedBox(height: 10),
              ...controls.map(
                (control) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: control,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: searchField),
            const SizedBox(width: 10),
            ...controls.map(
              (control) => SizedBox(
                width: 170,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: control,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InvoiceList extends StatelessWidget {
  final List<RecentInvoice> invoices;
  final VoidCallback onChanged;

  const _InvoiceList({required this.invoices, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: invoices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _InvoiceCard(invoice: invoices[index], onChanged: onChanged),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final RecentInvoice invoice;
  final VoidCallback onChanged;

  const _InvoiceCard({required this.invoice, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pending = invoice.status == 'payment_pending';
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            CircleAvatar(
              child: Icon(
                pending ? Icons.schedule : Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(invoice.number, variant: CustomTextStyle.label),
                  CustomText(
                    '${invoice.createdAt.day}/${invoice.createdAt.month}/${invoice.createdAt.year}  |  ${invoice.paymentMethod}',
                    variant: CustomTextStyle.caption,
                    color: Colors.white.withValues(alpha: .7),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (constraints.maxWidth >= 330)
              CustomText(money(invoice.total), variant: CustomTextStyle.label),
            if (pending)
              IconButton(
                tooltip: 'Collect payment',
                onPressed: () => _collect(context),
                icon: const Icon(Icons.payments_outlined),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _collect(BuildContext context) async {
    await showPaymentCollectionDialog(
      context,
      invoiceNumber: invoice.number,
      amount: invoice.total,
      payeeName: invoice.upiPayeeName,
      upiId: invoice.upiId,
      method: invoice.paymentMethod,
    );
    onChanged();
  }
}

class _InvoiceTable extends StatelessWidget {
  final List<RecentInvoice> invoices;
  final VoidCallback onChanged;

  const _InvoiceTable({required this.invoices, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Invoice')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Method')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Amount'), numeric: true),
              DataColumn(label: Text('Action')),
            ],
            rows: invoices.map((invoice) {
              final pending = invoice.status == 'payment_pending';
              return DataRow(
                cells: [
                  DataCell(Text(invoice.number)),
                  DataCell(
                    Text(
                      '${invoice.createdAt.day}/${invoice.createdAt.month}/${invoice.createdAt.year}',
                    ),
                  ),
                  DataCell(Text(invoice.paymentMethod)),
                  DataCell(Text(pending ? 'Pending' : 'Paid')),
                  DataCell(Text(money(invoice.total))),
                  DataCell(
                    pending
                        ? TextButton(
                            onPressed: () async {
                              await showPaymentCollectionDialog(
                                context,
                                invoiceNumber: invoice.number,
                                amount: invoice.total,
                                payeeName: invoice.upiPayeeName,
                                upiId: invoice.upiId,
                                method: invoice.paymentMethod,
                              );
                              onChanged();
                            },
                            child: const Text('Collect'),
                          )
                        : const Icon(Icons.check_circle_outline),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _InvoicePagination extends StatelessWidget {
  final int page;
  final int pageCount;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _InvoicePagination({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            CustomText(
              'Page ${page + 1} of $pageCount',
              variant: CustomTextStyle.caption,
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );
        return compact
            ? Column(
                children: [
                  CustomText(
                    '$total invoice${total == 1 ? '' : 's'}',
                    variant: CustomTextStyle.caption,
                    color: Colors.white.withValues(alpha: .7),
                  ),
                  controls,
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CustomText(
                    '$total invoice${total == 1 ? '' : 's'}',
                    variant: CustomTextStyle.caption,
                    color: Colors.white.withValues(alpha: .7),
                  ),
                  controls,
                ],
              );
      },
    );
  }
}
