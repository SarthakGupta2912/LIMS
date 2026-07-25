import 'package:flutter/material.dart';

import '../core/app_database.dart';
import '../pages/billing/billing_page.dart';
import '../pages/dashboard/dashboard_page.dart';
import '../pages/invoices/invoices_page.dart';
import '../pages/products/products_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/templates/templates_page.dart';
import '../shared/ui.dart';
import 'responsive.dart';
import 'theme.dart';

class InvoiceApp extends StatelessWidget {
  const InvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Invoice Manager',
      theme: buildAppTheme(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FutureBuilder<void>(
        future: AppDatabase.instance.open(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupScreen();
          }
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error.toString());
          }
          return const AppShell();
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _productsKey = GlobalKey<ProductsPageState>();
  final _templatesKey = GlobalKey<TemplatesPageState>();
  int _index = 0;

  void _refresh() => setState(() {});
  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  void _addProduct() {
    _go(1);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _productsKey.currentState?.openProductDialog(),
    );
  }

  void _addTemplate() {
    _go(4);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _templatesKey.currentState?.openTemplateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = Breakpoints.compact(context);
    final mobileShell = compact || Breakpoints.mobileOrTablet;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final pages = [
      DashboardPage(
        onNewInvoice: () {
          _go(2);
        },
        onAddProduct: _addProduct,
        onTemplate: _addTemplate,
        onChanged: _refresh,
        onInvoices: () => _go(3),
      ),
      ProductsPage(key: _productsKey, onChanged: _refresh),
      BillingPage(
        onChanged: _refresh,
        onNeedTemplate: _addTemplate,
        onNeedProduct: _addProduct,
      ),
      InvoicesPage(onChanged: _refresh),
      TemplatesPage(key: _templatesKey, onChanged: _refresh),
      SettingsPage(onChanged: _refresh),
    ];
    final content = mobileShell
        ? _StablePageViewport(index: _index, pages: pages)
        : RepaintBoundary(child: pages[_index]);

    return GlassBackground(
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        appBar: mobileShell
            ? AppBar(
                title: const CustomText(
                  'Invoice Manager',
                  variant: CustomTextStyle.subtitle,
                ),
              )
            : null,
        body: mobileShell
            ? content
            : Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _DesktopNav(index: _index, onChanged: _go),
                  ),
                  Expanded(child: content),
                ],
              ),
        bottomNavigationBar: mobileShell && !keyboardVisible
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: GlassContainer(
                  radius: 24,
                  blur: 20,
                  color: Colors.white.withValues(alpha: .16),
                  child: _MobileBottomNav(index: _index, onChanged: _go),
                ),
              )
            : null,
      ),
    );
  }
}

class _StablePageViewport extends StatelessWidget {
  final int index;
  final List<Widget> pages;

  const _StablePageViewport({required this.index, required this.pages});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IndexedStack(
        index: index,
        children: pages.map((page) => RepaintBoundary(child: page)).toList(),
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _MobileBottomNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = const [
      (0, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Home'),
      (1, Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
      (2, Icons.point_of_sale_outlined, Icons.point_of_sale, 'Billing'),
      (
        4,
        Icons.dashboard_customize_outlined,
        Icons.dashboard_customize,
        'Templates',
      ),
      (5, Icons.settings_outlined, Icons.settings, 'Settings'),
    ];

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: SizedBox(
        height: AppSize.space(context, 64),
        child: Row(
          children: items.indexed.map((entry) {
            final selected = entry.$2.$1 == index;
            final item = entry.$2;
            return Expanded(
              child: _MobileBottomNavItem(
                icon: item.$2,
                selectedIcon: item.$3,
                label: item.$4,
                selected: selected,
                onTap: () => onChanged(item.$1),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MobileBottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MobileBottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.white.withValues(alpha: .72);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: double.infinity,
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                color: color,
                size: AppSize.icon(context, 24),
              ),
              SizedBox(height: AppSize.space(context, 3)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CustomText(
                    label,
                    variant: CustomTextStyle.caption,
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _DesktopNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final narrow = Breakpoints.narrowDesktop(context);
    final items = const [
      (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
      (Icons.inventory_2_outlined, Icons.inventory_2, 'Products'),
      (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Billing'),
      (Icons.receipt_long_outlined, Icons.receipt_long, 'Invoices'),
      (
        Icons.dashboard_customize_outlined,
        Icons.dashboard_customize,
        'Templates',
      ),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];
    return SizedBox(
      width: narrow ? 88 : 240,
      child: GlassContainer(
        radius: 28,
        blur: 22,
        color: Colors.white.withValues(alpha: .16),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minHeight =
                  constraints.maxHeight.isFinite && constraints.maxHeight < 520
                  ? 520.0
                  : constraints.maxHeight;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          narrow ? 14 : 20,
                          22,
                          narrow ? 14 : 20,
                          14,
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(child: Icon(Icons.receipt_long)),
                            if (!narrow) ...[
                              const SizedBox(width: 12),
                              const Expanded(
                                child: CustomText(
                                  'Invoice Manager',
                                  variant: CustomTextStyle.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...items.indexed.map(
                        (item) => _DesktopNavItem(
                          icon: item.$2.$1,
                          selectedIcon: item.$2.$2,
                          label: item.$2.$3,
                          selected: index == item.$1,
                          narrow: narrow,
                          onTap: () => onChanged(item.$1),
                        ),
                      ),
                      if (!narrow) ...[
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: CustomText(
                            'Offline-first billing for small businesses',
                            color: Colors.white.withValues(alpha: .68),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool narrow;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.narrow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.white.withValues(alpha: .72);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18, vertical: 4),
      child: Tooltip(
        message: narrow ? label : '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: narrow
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                SizedBox(width: narrow ? 0 : 18),
                Icon(selected ? selectedIcon : icon, color: color),
                if (!narrow) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: CustomText(
                      label,
                      variant: CustomTextStyle.subtitle,
                      color: color,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupError extends StatelessWidget {
  final String error;
  const _StartupError({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CustomText(
            'Could not open local database.\n\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
