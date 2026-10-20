import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_database.dart';
import '../core/nearby_connection_service.dart';
import '../core/notification_service.dart';
import '../pages/Billing/billing_page.dart';
import '../pages/customer/customer_order_detail_page.dart';
import '../pages/customer/customer_pages.dart';
import '../pages/dashboard/dashboard_page.dart';
import '../pages/invoices/invoices_page.dart';
import '../pages/orders/shop_orders_page.dart';
import '../pages/products/products_page.dart';
import '../pages/profiles/profile_selection_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/templates/templates_page.dart';
import '../shared/ui.dart';
import '../splash.dart';
import 'responsive.dart';
import 'theme.dart';

class InvoiceApp extends StatelessWidget {
  final Future<void> Function()? initialize;

  const InvoiceApp({super.key, this.initialize});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LIMS',
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child ?? const SizedBox.shrink(),
    ),
    home: SplashScreen(
      initialize: initialize ?? AppDatabase.instance.open,
      child: const _ProfileGate(),
    ),
  );
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate();

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  LocalProfile? _profile;

  @override
  void initState() {
    super.initState();
    _profile = AppDatabase.instance.activeProfile();
  }

  Future<void> _leaveProfile() async {
    await NearbyConnectionService.instance.disconnect();
    AppDatabase.instance.logout();
    if (mounted) setState(() => _profile = null);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return ProfileSelectionPage(
        onSelected: (value) => setState(() => _profile = value),
      );
    }
    return profile.role == AppRole.customer
        ? CustomerShell(profile: profile, onLeaveProfile: _leaveProfile)
        : AppShell(profile: profile, onLeaveProfile: _leaveProfile);
  }
}

class AppShell extends StatefulWidget {
  final LocalProfile profile;
  final VoidCallback onLeaveProfile;

  const AppShell({
    super.key,
    required this.profile,
    required this.onLeaveProfile,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _productsKey = GlobalKey<ProductsPageState>();
  final _templatesKey = GlobalKey<TemplatesPageState>();
  final List<int> _history = [];
  int _index = 0;
  StreamSubscription<String>? _notificationNav;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationNav = NotificationService.instance.onNavigateToOrder.listen(
      (_) => _go(5),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (NotificationService.instance.consumePendingOrderId() != null) {
        _go(5);
      }
      NearbyConnectionService.instance.resumeForForeground(widget.profile);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NearbyConnectionService.instance.resumeForForeground(widget.profile);
    } else {
      NearbyConnectionService.instance.pauseForBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationNav?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _go(int index) {
    if (index == _index) return;
    setState(() {
      _history
        ..remove(_index)
        ..add(_index);
      if (_history.length > 5) _history.removeAt(0);
      _index = index;
    });
  }

  void _back() {
    if (_history.isNotEmpty) setState(() => _index = _history.removeLast());
  }

  void _addProduct() {
    _go(1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _productsKey.currentState?.openProductDialog(),
    );
  }

  void _addTemplate() {
    _go(4);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _templatesKey.currentState?.openTemplateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = Breakpoints.compact(context);
    final mobile = compact || Breakpoints.mobileOrTablet;
    final shop = AppDatabase.instance.shopForProfile(widget.profile.id);
    final mode = shop?.mode ?? ShopkeeperMode.counterBilling;
    final pages = [
      DashboardPage(
        mode: mode,
        onNewInvoice: () => _go(2),
        onAddProduct: _addProduct,
        onTemplate: _addTemplate,
        onChanged: _refresh,
        onInvoices: () => _go(3),
        onOrders: () => _go(5),
      ),
      ProductsPage(key: _productsKey, onChanged: _refresh),
      BillingPage(
        onChanged: _refresh,
        onNeedTemplate: _addTemplate,
        onNeedProduct: _addProduct,
      ),
      InvoicesPage(onChanged: _refresh),
      TemplatesPage(key: _templatesKey, onChanged: _refresh),
      ShopOrdersPage(profile: widget.profile),
      SettingsPage(onChanged: _refresh, onLeaveProfile: widget.onLeaveProfile),
    ];
    final content = mobile
        ? IndexedStack(index: _index, children: pages)
        : Row(
            children: [
              _Nav(index: _index, mode: mode, onChanged: _go),
              Expanded(child: pages[_index]),
            ],
          );
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: GlassBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(top: true, bottom: false, child: content),
          bottomNavigationBar: mobile
              ? _BottomNav(index: _index, mode: mode, onChanged: _go)
              : null,
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  final int index;
  final ShopkeeperMode mode;
  final ValueChanged<int> onChanged;

  const _Nav({
    required this.index,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(int, IconData, String)>[
      (0, Icons.space_dashboard_outlined, 'Dashboard'),
      (1, Icons.inventory_2_outlined, 'Products'),
      if (mode == ShopkeeperMode.counterBilling)
        (2, Icons.point_of_sale_outlined, 'Billing'),
      if (mode == ShopkeeperMode.counterBilling)
        (3, Icons.receipt_long_outlined, 'Invoices'),
      if (mode == ShopkeeperMode.counterBilling)
        (4, Icons.dashboard_customize_outlined, 'Templates'),
      (5, Icons.receipt_long_outlined, 'Orders'),
      (6, Icons.settings_outlined, 'Settings'),
    ];
    return SizedBox(
      width: 220,
      child: GlassContainer(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 18),
          children: [
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text('LIMS'),
            ),
            ...items.map(
              (item) => ListTile(
                selected: index == item.$1,
                leading: Icon(item.$2),
                title: Text(item.$3),
                onTap: () => onChanged(item.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ShopkeeperMode mode;
  final ValueChanged<int> onChanged;

  const _BottomNav({
    required this.index,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(int, IconData, String)>[
      (0, Icons.space_dashboard_outlined, 'Home'),
      (1, Icons.inventory_2_outlined, 'Products'),
      if (mode == ShopkeeperMode.counterBilling)
        (2, Icons.point_of_sale_outlined, 'Billing'),
      (5, Icons.receipt_long_outlined, 'Orders'),
      (6, Icons.settings_outlined, 'Settings'),
    ];
    return NavigationBar(
      selectedIndex: items
          .indexWhere((item) => item.$1 == index)
          .clamp(0, items.length - 1),
      onDestinationSelected: (value) => onChanged(items[value].$1),
      destinations: [
        for (final item in items)
          NavigationDestination(icon: Icon(item.$2), label: item.$3),
      ],
    );
  }
}

class CustomerShell extends StatefulWidget {
  final LocalProfile profile;
  final VoidCallback onLeaveProfile;

  const CustomerShell({
    super.key,
    required this.profile,
    required this.onLeaveProfile,
  });

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell>
    with WidgetsBindingObserver {
  int _index = 0;
  StreamSubscription<CustomerBuzzEvent>? _buzzes;
  StreamSubscription<String>? _notificationNav;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _buzzes = NearbyConnectionService.instance.customerBuzzEvents.listen(
      _showBuzz,
    );
    _notificationNav = NotificationService.instance.onNavigateToOrder.listen(
      _openOrder,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final orderId = NotificationService.instance.consumePendingOrderId();
      if (orderId != null) _openOrder(orderId);
      NearbyConnectionService.instance.resumeForForeground(widget.profile);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NearbyConnectionService.instance.resumeForForeground(widget.profile);
    } else {
      NearbyConnectionService.instance.pauseForBackground();
    }
  }

  Future<void> _showBuzz(CustomerBuzzEvent event) async {
    if (!mounted) return;
    final viewOrder = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerBuzzDialog(event: event),
    );
    await NearbyConnectionService.instance.respondToCustomerBuzz(event.eventId);
    if (viewOrder == true && mounted) _openOrder(event.orderId);
  }

  void _openOrder(String orderId) {
    if (!mounted) return;
    setState(() => _index = 1);
    final order = AppDatabase.instance.orderForProfile(
      widget.profile.id,
      orderId,
    );
    if (order != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerOrderDetailPage(
            profile: widget.profile,
            orderId: orderId,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _buzzes?.cancel();
    _notificationNav?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      NearbyShopsPage(
        profile: widget.profile,
        onOpenOrders: () => setState(() => _index = 1),
      ),
      CustomerOrdersPage(profile: widget.profile),
      CustomerSettingsPage(
        profile: widget.profile,
        onSwitchProfile: widget.onLeaveProfile,
        onLogout: widget.onLeaveProfile,
      ),
    ];
    const destinations = [
      (Icons.storefront_outlined, 'Nearby'),
      (Icons.receipt_long_outlined, 'Orders'),
      (Icons.settings_outlined, 'Settings'),
    ];
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: IndexedStack(index: _index, children: pages),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: [
            for (final item in destinations)
              NavigationDestination(icon: Icon(item.$1), label: item.$2),
          ],
        ),
      ),
    );
  }
}

class CustomerBuzzDialog extends StatelessWidget {
  final CustomerBuzzEvent event;

  const CustomerBuzzDialog({super.key, required this.event});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${event.shopName} needs your attention'),
    content: Text(
      'The shopkeeper is calling you about order ${event.orderId.substring(0, event.orderId.length.clamp(0, 8)).toUpperCase()}.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Dismiss'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('View order'),
      ),
    ],
  );
}
