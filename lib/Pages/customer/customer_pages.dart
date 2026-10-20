import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/responsive.dart';
import '../../core/app_database.dart';
import '../../core/nearby_connection_service.dart';
import '../../core/custom_mesh_service.dart';
import '../../shared/help.dart';
import '../../shared/ui.dart';
import 'customer_order_detail_page.dart';

class NearbyShopsPage extends StatefulWidget {
  final LocalProfile profile;
  final VoidCallback? onOpenOrders;

  const NearbyShopsPage({super.key, required this.profile, this.onOpenOrders});

  @override
  State<NearbyShopsPage> createState() => _NearbyShopsPageState();
}

class _NearbyShopsPageState extends State<NearbyShopsPage> {
  final _nearby = NearbyConnectionService.instance;
  bool _started = false;
  bool _catalogOpen = false;
  bool _operationBusy = false;
  final bool _qrOnly = true;
  DialogRoute<void>? _syncRoute;
  Timer? _syncTimeout;
  final _syncStage = ValueNotifier<String>('Connecting to shop Wi-Fi');
  int _qrSyncAttempt = 0;

  @override
  void initState() {
    super.initState();
    _nearby
      ..addListener(_changed)
      ..onCatalog = _openCatalog;
    // Automatic Nearby scanning is temporarily disabled: connect via shop QR.
    // WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _changed() {
    if (_syncRoute != null) {
      if (_nearby.activity == NearbyActivity.error) {
        _finishQrSync();
        if (mounted) {
          showAppSnack(context, _nearby.errorMessage ?? 'Could not sync menu');
        }
      } else if (_nearby.activity == NearbyActivity.syncing) {
        _syncStage.value = 'Syncing shop menu';
      } else if (_nearby.activity == NearbyActivity.connecting) {
        _syncStage.value = 'Connecting to shop';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_qrOnly) return;
    if (_started || _operationBusy) return;
    _operationBusy = true;
    _started = true;
    if (mounted) setState(() {});
    try {
      await _nearby.resumeDiscovery(widget.profile);
    } finally {
      _operationBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (_operationBusy) return;
    _operationBusy = true;
    setState(() {});
    try {
      await operation();
    } finally {
      _operationBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _pauseScanning() async {
    if (_nearby.activity != NearbyActivity.discovering &&
        _nearby.activity != NearbyActivity.reconnecting) {
      return;
    }
    _operationBusy = true;
    setState(() {});
    try {
      await _nearby.stopDiscovery();
      _started = false;
      if (mounted) showAppSnack(context, 'Nearby scanning paused');
    } finally {
      _operationBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _scanMeshQr() async {
    if (_operationBusy || _syncRoute != null) return;
    try {
      if (!await CustomMeshService.instance.isWifiEnabled()) {
        await CustomMeshService.instance.openWifiSettings();
        return;
      }
    } on PlatformException catch (error) {
      if (mounted) {
        showAppSnack(context, error.message ?? 'Could not check Wi-Fi status');
      }
      return;
    }
    if (!mounted) return;
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      if (!mounted) return;
      await _showPermissionDialog(
        title: 'Camera permission required',
        message:
            'Camera access is needed to scan a hotspot connection QR code.',
      );
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final uri = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const _MeshQrScannerPage()),
    );
    if (uri == null || !mounted) return;
    final attempt = ++_qrSyncAttempt;
    _syncStage.value = 'Connecting to shop Wi-Fi';
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Opening shop menu'),
          content: ValueListenableBuilder<String>(
            valueListenable: _syncStage,
            builder: (_, stage, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 20),
                Text(stage),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: _cancelQrSync, child: const Text('Cancel')),
          ],
        ),
      ),
    );
    _syncRoute = route;
    unawaited(navigator.push(route));
    _syncTimeout = Timer(const Duration(seconds: 45), () {
      _cancelQrSync();
      if (mounted) {
        showAppSnack(context, 'Menu sync timed out. Scan the shop QR again.');
      }
    });
    await _runOperation(() async {
      final wasScanning =
          _nearby.activity == NearbyActivity.discovering ||
          _nearby.activity == NearbyActivity.reconnecting;
      if (wasScanning) await _nearby.stopDiscovery(manual: false);
      try {
        await CustomMeshService.instance.start().timeout(
          const Duration(seconds: 15),
        );
        if (!mounted || attempt != _qrSyncAttempt) return;
        await CustomMeshService.instance
            .connect(uri)
            .timeout(const Duration(seconds: 30));
        if (!mounted || attempt != _qrSyncAttempt || _syncRoute == null) return;
        _syncStage.value = 'Finding shop on hotspot';
        final address = await CustomMeshService.instance.qrNodeAddress(uri);
        if (mounted && attempt == _qrSyncAttempt && _syncRoute != null) {
          _started = true;
          await _nearby
              .connectToScannedMeshShop(widget.profile, address)
              .timeout(const Duration(seconds: 10));
        }
      } catch (error) {
        if (!mounted || attempt != _qrSyncAttempt) return;
        _finishQrSync();
        if (mounted) {
          showAppSnack(
            context,
            error is PlatformException
                ? _customerConnectionError(error.message)
                : 'Could not sync shop menu: ${_customerConnectionError(error)}',
          );
        }
        if (!_qrOnly && wasScanning && !_nearby.connected) {
          _started = true;
          await _nearby.resumeDiscovery(widget.profile);
        }
      }
    });
  }

  void _cancelQrSync() {
    _qrSyncAttempt++;
    _finishQrSync();
    if (mounted) setState(() => _operationBusy = false);
    unawaited(
      _nearby
          .disconnect()
          .timeout(const Duration(seconds: 3))
          .catchError((Object _) {}),
    );
  }

  void _finishQrSync() {
    _syncTimeout?.cancel();
    _syncTimeout = null;
    final route = _syncRoute;
    _syncRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _showPermissionDialog({
    required String title,
    required String message,
  }) async {
    final permanentlyDenied = await Permission.camera.isPermanentlyDenied;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          permanentlyDenied
              ? '$message Open app settings and allow Camera permission to continue.'
              : message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (permanentlyDenied)
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await openAppSettings();
              },
              child: const Text('Open app settings'),
            ),
        ],
      ),
    );
  }

  Future<void> _openCatalog(
    String shopId,
    String shopName,
    List<ProductRecord> products,
  ) async {
    if (!mounted || _catalogOpen) return;
    _finishQrSync();
    _catalogOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopCatalogPage(
          customer: widget.profile,
          shopId: shopId,
          shopName: shopName,
          products: products,
        ),
      ),
    );
    _catalogOpen = false;
    if (mounted && !_nearby.connected) {
      _started = false;
      _start();
    }
  }

  Future<void> _connectCachedShop(CachedShopRecord cached) =>
      _nearby.connectToShopId(
        customer: widget.profile,
        shopId: cached.shop.shopId,
        shopName: cached.shop.name,
      );

  Future<void> _connectAndOpenShop(DiscoveredShop endpoint) async {
    await _nearby.connect(widget.profile, endpoint);
    for (var attempt = 0; attempt < 40; attempt++) {
      if (!mounted || _catalogOpen) return;
      if (_nearby.connected &&
          _nearby.activity == NearbyActivity.connected &&
          _nearby.connectedShopId != null &&
          _sameShopId(_nearby.connectedShopId!, endpoint.shop.shopId)) {
        await _openCatalog(
          _nearby.connectedShopId!,
          _nearby.connectedShopName ?? endpoint.shop.name,
          _nearby.currentCatalog,
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  bool _sameShopId(String left, String right) {
    final normalizedLeft = left.replaceAll('-', '').toLowerCase();
    final normalizedRight = right.replaceAll('-', '').toLowerCase();
    return normalizedLeft.length >= 8 &&
        normalizedRight.length >= 8 &&
        normalizedLeft.substring(0, 8) == normalizedRight.substring(0, 8);
  }

  @override
  void dispose() {
    _finishQrSync();
    _syncStage.dispose();
    _nearby
      ..removeListener(_changed)
      ..onCatalog = null;
    _nearby.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_qrOnly) {
      final orders = AppDatabase.instance.ordersForProfile(widget.profile.id);
      final activeOrders = orders
          .where((order) => !_isFinishedOrder(order.status))
          .length;
      final recentOrders = orders.take(3).toList();
      final connected = _nearby.connectedShopId != null;
      return PageFrame(
        title: 'Welcome back, ${_firstName(widget.profile.displayName)}',
        subtitle: 'Find a nearby shop, browse its menu, and order in seconds.',
        actions: [
          IconButton.filledTonal(
            tooltip: 'How to use this app',
            onPressed: () => showRoleHelp(context, AppRole.customer),
            icon: const Icon(Icons.help_outline),
          ),
        ],
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CustomerWelcomePanel(
              connected: connected,
              connectedShopName: _nearby.connectedShopName,
              busy: _operationBusy || _syncRoute != null,
              errorMessage: _nearby.errorMessage,
              onScan: _scanMeshQr,
              onOpenConnected: connected
                  ? () => _openCatalog(
                      _nearby.connectedShopId!,
                      _nearby.connectedShopName ?? 'Shop',
                      _nearby.currentCatalog,
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final stats = [
                  _CustomerStat(
                    label: 'Active orders',
                    value: '$activeOrders',
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF8DEBFF),
                    onTap: widget.onOpenOrders,
                  ),
                  _CustomerStat(
                    label: 'Connection',
                    value: connected ? 'Ready' : 'Offline',
                    icon: connected ? Icons.wifi : Icons.wifi_off,
                    color: connected
                        ? const Color(0xFF9FF2B4)
                        : const Color(0xFFFFA8A8),
                    onTap: connected
                        ? () => _openCatalog(
                            _nearby.connectedShopId!,
                            _nearby.connectedShopName ?? 'Shop',
                            _nearby.currentCatalog,
                          )
                        : _scanMeshQr,
                  ),
                ];
                return Flex(
                  direction: wide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0)
                        SizedBox(
                          width: wide ? 10 : null,
                          height: wide ? null : 10,
                        ),
                      wide
                          ? Expanded(child: _CustomerStatCard(stat: stats[i]))
                          : _CustomerStatCard(stat: stats[i]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (recentOrders.isNotEmpty) ...[
              const _CustomerSectionHeader(
                title: 'Recent activity',
                actionLabel: 'Latest updates',
                icon: Icons.history,
              ),
              const SizedBox(height: 10),
              ...recentOrders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CustomerOrderPreview(
                    order: order,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomerOrderDetailPage(
                          profile: widget.profile,
                          orderId: order.id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final scanning =
        _nearby.activity == NearbyActivity.discovering ||
        _nearby.activity == NearbyActivity.reconnecting;
    final paused = _nearby.discoveryPaused && !scanning;
    final shops = _nearby.shops;
    final cachedShops = _nearby.cachedShops;
    final activeShop = _nearby.connectedShopId == null
        ? null
        : NearbyShopRecord(
            shopId: _nearby.connectedShopId!,
            name: _nearby.connectedShopName ?? 'Connected shop',
            category: 'Active shop',
            orderingEnabled: true,
            statusEnabled: true,
            chatEnabled: true,
            catalogRevision: _nearby.currentCatalogRevision,
            lastSeen: DateTime.now(),
          );
    final landscape = Breakpoints.landscapeMobile(context);
    return PageFrame(
      title: 'Nearby shops',
      subtitle: 'Discover local menus through Nearby Connections.',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Scan hotspot QR',
          onPressed: _operationBusy ? null : _scanMeshQr,
          icon: const Icon(Icons.hub_outlined),
        ),
        IconButton.filledTonal(
          tooltip: 'How to use this app',
          onPressed: () => showRoleHelp(context, AppRole.customer),
          icon: const Icon(Icons.help_outline),
        ),
      ],
      scrollable: landscape,
      child: Column(
        mainAxisSize: landscape ? MainAxisSize.min : MainAxisSize.max,
        children: [
          GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                scanning
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _nearby.activity == NearbyActivity.error
                            ? Icons.wifi_off
                            : Icons.wifi_find,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(switch (_nearby.activity) {
                        NearbyActivity.connecting => 'Connecting to shop',
                        NearbyActivity.connected =>
                          'Connected to ${_nearby.connectedShopName ?? 'shop'}',
                        NearbyActivity.syncing => 'Syncing menu',
                        NearbyActivity.reconnecting =>
                          'Reconnecting to ${_nearby.connectedShopName ?? 'shop'}',
                        _ when scanning => 'Scanning nearby shops',
                        _ when paused => 'Nearby scan paused',
                        _ => 'Nearby scan stopped',
                      }, variant: CustomTextStyle.label),
                      CustomText(
                        paused
                            ? 'Tap play to look for nearby shops again'
                            : _nearby.errorMessage ??
                                  '${shops.length} shop${shops.length == 1 ? '' : 's'} found',
                        variant: CustomTextStyle.caption,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: scanning
                      ? 'Pause scanning'
                      : paused
                      ? 'Resume scanning'
                      : 'Scan again',
                  onPressed: scanning
                      ? _pauseScanning
                      : _operationBusy
                      ? null
                      : () {
                          _started = false;
                          _start();
                        },
                  icon: _operationBusy && scanning
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          scanning
                              ? Icons.pause
                              : paused
                              ? Icons.play_arrow
                              : Icons.refresh,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (landscape)
            shops.isEmpty && activeShop == null && cachedShops.isEmpty
                ? EmptyPanel(
                    icon: Icons.storefront_outlined,
                    title: scanning
                        ? 'Looking for open shops'
                        : 'No nearby shops found',
                    message:
                        _nearby.errorMessage ??
                        'Ask the shopkeeper to turn on Shop visibility, then keep this screen open nearby.',
                    action: scanning
                        ? null
                        : FilledButton.icon(
                            onPressed: _operationBusy
                                ? null
                                : () {
                                    _started = false;
                                    _start();
                                  },
                            icon: const Icon(Icons.wifi_find),
                            label: const Text('Scan again'),
                          ),
                  )
                : activeShop != null && shops.isEmpty && cachedShops.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: _ActiveShopTile(
                      shop: activeShop,
                      connected: _nearby.connected,
                      onTap: () => _openCatalog(
                        activeShop.shopId,
                        activeShop.name,
                        _nearby.currentCatalog,
                      ),
                      onReconnect: _operationBusy
                          ? null
                          : () => _runOperation(_nearby.reconnectNow),
                      reconnecting: _nearby.reconnecting,
                      enabled: !_operationBusy,
                    ),
                  )
                : _ShopResults(
                    shops: shops,
                    activeShop: activeShop,
                    cachedShops: cachedShops,
                    connected: _nearby.connected,
                    shrinkWrap: true,
                    onConnect: _operationBusy
                        ? null
                        : (endpoint) => _runOperation(
                            () => _connectAndOpenShop(endpoint),
                          ),
                    onOpenActive: () => _openCatalog(
                      activeShop!.shopId,
                      activeShop.name,
                      _nearby.currentCatalog,
                    ),
                    onOpenCached: (cached) =>
                        _runOperation(() => _connectCachedShop(cached)),
                    onReconnect: _operationBusy
                        ? null
                        : () => _runOperation(_nearby.reconnectNow),
                    reconnecting: _nearby.reconnecting,
                    enabled: !_operationBusy,
                  )
          else
            Expanded(
              child: shops.isEmpty && activeShop == null && cachedShops.isEmpty
                  ? EmptyPanel(
                      icon: Icons.storefront_outlined,
                      title: scanning
                          ? 'Looking for open shops'
                          : 'No nearby shops found',
                      message:
                          _nearby.errorMessage ??
                          'Ask the shopkeeper to turn on Shop visibility, then keep this screen open nearby.',
                      action: scanning
                          ? null
                          : _nearby.reconnecting ||
                                _nearby.connectedShopId != null
                          ? FilledButton.icon(
                              onPressed: _operationBusy
                                  ? null
                                  : () => _runOperation(_nearby.reconnectNow),
                              icon: const Icon(Icons.sync),
                              label: const Text('Reconnect'),
                            )
                          : FilledButton.icon(
                              onPressed: _operationBusy
                                  ? null
                                  : () {
                                      _started = false;
                                      _start();
                                    },
                              icon: const Icon(Icons.wifi_find),
                              label: const Text('Scan again'),
                            ),
                    )
                  : activeShop != null && shops.isEmpty && cachedShops.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: _ActiveShopTile(
                        shop: activeShop,
                        connected: _nearby.connected,
                        onTap: () => _openCatalog(
                          activeShop.shopId,
                          activeShop.name,
                          _nearby.currentCatalog,
                        ),
                        onReconnect: _operationBusy
                            ? null
                            : () => _runOperation(_nearby.reconnectNow),
                        reconnecting: _nearby.reconnecting,
                        enabled: !_operationBusy,
                      ),
                    )
                  : _ShopResults(
                      shops: shops,
                      activeShop: activeShop,
                      cachedShops: cachedShops,
                      connected: _nearby.connected,
                      onConnect: _operationBusy
                          ? null
                          : (endpoint) => _runOperation(
                              () => _connectAndOpenShop(endpoint),
                            ),
                      onOpenActive: () => _openCatalog(
                        activeShop!.shopId,
                        activeShop.name,
                        _nearby.currentCatalog,
                      ),
                      onOpenCached: (cached) =>
                          _runOperation(() => _connectCachedShop(cached)),
                      onReconnect: _operationBusy
                          ? null
                          : () => _runOperation(_nearby.reconnectNow),
                      enabled: !_operationBusy,
                    ),
            ),
        ],
      ),
    );
  }

  String _firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

  bool _isFinishedOrder(String status) {
    final value = status.toLowerCase();
    return value == 'completed' || value == 'cancelled' || value == 'closed';
  }
}

class _CustomerWelcomePanel extends StatelessWidget {
  final bool connected;
  final String? connectedShopName;
  final bool busy;
  final String? errorMessage;
  final VoidCallback onScan;
  final VoidCallback? onOpenConnected;

  const _CustomerWelcomePanel({
    required this.connected,
    required this.connectedShopName,
    required this.busy,
    required this.errorMessage,
    required this.onScan,
    required this.onOpenConnected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      radius: 24,
      glassColor: scheme.primary.withValues(alpha: .13),
      border: Border.all(color: scheme.primary.withValues(alpha: .34)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected ? Icons.wifi : Icons.qr_code_2,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    CustomText(
                      connected ? 'SHOP CONNECTED' : 'READY TO DISCOVER',
                      variant: CustomTextStyle.caption,
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              CustomText(
                connected
                    ? 'Your menu is ready'
                    : 'What are you in the mood for?',
                variant: CustomTextStyle.title,
              ),
              const SizedBox(height: 5),
              CustomText(
                connected
                    ? '${connectedShopName ?? 'Your shop'} is connected. Continue browsing where you left off.'
                    : 'Scan a shop QR code to instantly open its menu and place an order.',
                color: Colors.white.withValues(alpha: .72),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                CustomText(
                  errorMessage!,
                  variant: CustomTextStyle.caption,
                  color: const Color(0xFFFFB1B1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          );
          final action = FilledButton.icon(
            onPressed: busy ? null : (connected ? onOpenConnected : onScan),
            icon: Icon(
              connected ? Icons.menu_book_outlined : Icons.qr_code_scanner,
            ),
            label: Text(connected ? 'Open menu' : 'Scan shop QR'),
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [copy, const SizedBox(height: 18), action],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 20),
                    action,
                  ],
                );
        },
      ),
    );
  }
}

class _CustomerStat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _CustomerStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
}

class _CustomerStatCard extends StatelessWidget {
  final _CustomerStat stat;

  const _CustomerStatCard({required this.stat});

  @override
  Widget build(BuildContext context) => GlassContainer(
    padding: EdgeInsets.zero,
    radius: 18,
    child: InkWell(
      onTap: stat.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: stat.color.withValues(alpha: .14),
              child: Icon(stat.icon, color: stat.color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(stat.value, variant: CustomTextStyle.title),
                  CustomText(
                    stat.label,
                    variant: CustomTextStyle.caption,
                    color: Colors.white.withValues(alpha: .64),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (stat.onTap != null)
              const Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: Colors.white54,
              ),
          ],
        ),
      ),
    ),
  );
}

class _CustomerSectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final IconData icon;

  const _CustomerSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: const Color(0xFF8DEBFF)),
      const SizedBox(width: 8),
      Expanded(child: CustomText(title, variant: CustomTextStyle.subtitle)),
      CustomText(
        actionLabel,
        variant: CustomTextStyle.caption,
        color: Colors.white.withValues(alpha: .55),
      ),
    ],
  );
}

class _CustomerOrderPreview extends StatelessWidget {
  final LocalOrderRecord order;
  final VoidCallback? onTap;

  const _CustomerOrderPreview({required this.order, this.onTap});

  @override
  Widget build(BuildContext context) => GlassContainer(
    padding: EdgeInsets.zero,
    radius: 16,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              child: Icon(Icons.receipt_long_outlined, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    order.shopName,
                    variant: CustomTextStyle.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CustomText(
                    '${order.status}  |  ${_relativeDate(order.updatedAt)}',
                    variant: CustomTextStyle.caption,
                    color: Colors.white.withValues(alpha: .6),
                  ),
                ],
              ),
            ),
            CustomText(money(order.total), variant: CustomTextStyle.label),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 13,
                  color: Colors.white54,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  String _relativeDate(DateTime value) {
    final age = DateTime.now().difference(value);
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

class _MeshQrScannerPage extends StatefulWidget {
  const _MeshQrScannerPage();

  @override
  State<_MeshQrScannerPage> createState() => _MeshQrScannerPageState();
}

class _MeshQrScannerPageState extends State<_MeshQrScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  void _detected(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null ||
        !(value.toLowerCase().startsWith('custommesh://') ||
            value.toLowerCase().startsWith('meshrabiya://'))) {
      return;
    }
    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan hotspot QR')),
    body: MobileScanner(controller: _controller, onDetect: _detected),
  );
}

String _customerConnectionError(Object? error) {
  final message = error?.toString() ?? '';
  final lower = message.toLowerCase();
  if (lower.contains('mesh') ||
      lower.contains('hotspot') ||
      lower.contains('wifi') ||
      lower.contains('connect')) {
    return 'Unable to connect to the hotspot. Check that the hotspot is enabled and try again.';
  }
  return message.isEmpty
      ? 'Unable to connect to the hotspot. Please try again.'
      : message;
}

class _ActiveShopTile extends StatelessWidget {
  final NearbyShopRecord shop;
  final bool connected;
  final VoidCallback? onTap;
  final VoidCallback? onReconnect;
  final bool reconnecting;
  final bool enabled;

  const _ActiveShopTile({
    required this.shop,
    required this.connected,
    required this.onTap,
    required this.onReconnect,
    this.reconnecting = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => GlassContainer(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onTap: enabled ? (connected ? onTap : onReconnect) : null,
      leading: CircleAvatar(
        radius: 18,
        child: Icon(connected ? Icons.wifi : Icons.sync, size: 20),
      ),
      title: CustomText(
        shop.name,
        variant: CustomTextStyle.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: CustomText(
        connected
            ? 'Connected  |  Menu up to date'
            : reconnecting
            ? 'Reconnecting  |  Looking for shop'
            : 'Connection lost  |  Tap to reconnect',
        color: Colors.white70,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        connected
            ? Icons.arrow_forward
            : reconnecting
            ? Icons.sync
            : Icons.refresh,
      ),
    ),
  );
}

class _ShopResults extends StatelessWidget {
  final List<DiscoveredShop> shops;
  final NearbyShopRecord? activeShop;
  final List<CachedShopRecord> cachedShops;
  final bool connected;
  final bool shrinkWrap;
  final ValueChanged<DiscoveredShop>? onConnect;
  final VoidCallback onOpenActive;
  final ValueChanged<CachedShopRecord> onOpenCached;
  final VoidCallback? onReconnect;
  final bool reconnecting;
  final bool enabled;

  const _ShopResults({
    required this.shops,
    required this.activeShop,
    required this.cachedShops,
    required this.connected,
    required this.onConnect,
    required this.onOpenActive,
    required this.onOpenCached,
    required this.onReconnect,
    this.reconnecting = false,
    this.enabled = true,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleShops = activeShop == null
        ? shops
        : shops
              .where((shop) => shop.shop.shopId != activeShop!.shopId)
              .toList();
    final items = <Widget>[];
    if (activeShop != null) {
      items.add(
        _ActiveShopTile(
          shop: activeShop!,
          connected: connected,
          onTap: onOpenActive,
          onReconnect: onReconnect,
          reconnecting: reconnecting,
          enabled: enabled,
        ),
      );
    }
    items.addAll(
      visibleShops.map(
        (endpoint) => GlassContainer(
          key: ValueKey('nearby-${endpoint.shop.shopId}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: InkWell(
            onTap: enabled && onConnect != null
                ? () => onConnect!(endpoint)
                : null,
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const CircleAvatar(
                radius: 18,
                child: Icon(Icons.storefront_outlined, size: 20),
              ),
              title: CustomText(
                endpoint.shop.name,
                variant: CustomTextStyle.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: CustomText(
                '${endpoint.shop.category}  |  Nearby now',
                color: Colors.white70,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: endpoint.shop.orderingEnabled
                  ? const Icon(Icons.arrow_forward)
                  : const Chip(label: Text('Browse only')),
            ),
          ),
        ),
      ),
    );
    if (cachedShops.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: CustomText(
            'Previously visited',
            variant: CustomTextStyle.label,
            color: Colors.white70,
          ),
        ),
      );
      items.addAll(
        cachedShops.map(
          (cached) => GlassContainer(
            key: ValueKey('cached-${cached.shop.shopId}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: enabled ? () => onOpenCached(cached) : null,
              leading: const CircleAvatar(
                radius: 18,
                child: Icon(Icons.menu_book_outlined, size: 20),
              ),
              title: CustomText(
                cached.shop.name,
                variant: CustomTextStyle.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: CustomText(
                'Tap to reconnect  |  Updated ${_relativeAge(cached.syncedAt)}',
                color: Colors.white70,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) => items[index],
    );
  }

  String _relativeAge(DateTime time) {
    final age = DateTime.now().difference(time);
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

class ShopCatalogPage extends StatefulWidget {
  final LocalProfile customer;
  final String shopId;
  final String shopName;
  final List<ProductRecord> products;

  const ShopCatalogPage({
    super.key,
    required this.customer,
    required this.shopId,
    required this.shopName,
    required this.products,
  });

  @override
  State<ShopCatalogPage> createState() => _ShopCatalogPageState();
}

class _ShopCatalogPageState extends State<ShopCatalogPage> {
  final Map<int, int> _cart = {};
  final _nearby = NearbyConnectionService.instance;
  late List<ProductRecord> _products;

  @override
  void initState() {
    super.initState();
    _products = widget.products;
    _nearby.addListener(_syncChanged);
  }

  void _syncChanged() {
    if (!mounted || _nearby.connectedShopId != widget.shopId) return;
    setState(() => _products = _nearby.currentCatalog);
  }

  @override
  void dispose() {
    _nearby.removeListener(_syncChanged);
    super.dispose();
  }

  int _cartKey(int index, ProductRecord product) => product.id ?? -(index + 1);

  @override
  Widget build(BuildContext context) {
    final count = _cart.values.fold<int>(0, (sum, value) => sum + value);
    var total = 0.0;
    for (var i = 0; i < _products.length; i++) {
      final product = _products[i];
      total += product.price * (_cart[_cartKey(i, product)] ?? 0);
    }
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.shopName)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _products.isEmpty
                ? const EmptyPanel(
                    icon: Icons.restaurant_menu,
                    title: 'No public menu yet',
                    message:
                        'This shop has not published customer-visible items.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 92),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = _products[index];
                      final key = _cartKey(index, product);
                      final quantity = _cart[key] ?? 0;
                      return GlassContainer(
                        child: ListTile(
                          enabled: product.isAvailable,
                          title: CustomText(
                            product.name,
                            variant: CustomTextStyle.subtitle,
                          ),
                          subtitle: CustomText(
                            '${product.description.isEmpty ? product.category : product.description}\n${money(product.price)}',
                            color: Colors.white70,
                            maxLines: 3,
                          ),
                          trailing: product.isAvailable
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      onPressed: quantity == 0
                                          ? null
                                          : () => setState(
                                              () => _cart[key] = quantity - 1,
                                            ),
                                      icon: const Icon(Icons.remove),
                                    ),
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '$quantity',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    IconButton.filled(
                                      onPressed: () => setState(
                                        () => _cart[key] = quantity + 1,
                                      ),
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                )
                              : const Chip(label: Text('Unavailable')),
                        ),
                      );
                    },
                  ),
          ),
        ),
        bottomNavigationBar: count == 0
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _reviewOrder(total),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text('$count items  |  ${money(total)}  |  Review'),
                ),
              ),
      ),
    );
  }

  Future<void> _reviewOrder(double total) async {
    final note = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: 'Review order',
        actions: [
          TextButton(
            onPressed: () => closeAppDialog(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => closeAppDialog(context, true),
            icon: const Icon(Icons.send),
            label: const Text('Send order'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomText(
              '${_cart.values.fold<int>(0, (sum, value) => sum + value)} items',
              variant: CustomTextStyle.label,
            ),
            const SizedBox(height: 4),
            CustomText(money(total), variant: CustomTextStyle.title),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Order note (optional)',
              ),
            ),
            const SizedBox(height: 10),
            CustomText(
              _nearby.connected && _nearby.connectedShopId == widget.shopId
                  ? 'Connected. The shop will confirm receipt.'
                  : 'Saved now and sent automatically when this shop reconnects.',
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) {
      note.dispose();
      return;
    }
    final lines = <CartLine>[];
    for (var i = 0; i < _products.length; i++) {
      final product = _products[i];
      final quantity = _cart[_cartKey(i, product)] ?? 0;
      if (quantity > 0) {
        lines.add(CartLine(product: product, quantity: quantity));
      }
    }
    await _nearby.submitOrder(
      customer: widget.customer,
      shopId: widget.shopId,
      shopName: widget.shopName,
      lines: lines,
      note: note.text.trim(),
    );
    note.dispose();
    if (!mounted) return;
    setState(_cart.clear);
    showAppSnack(
      context,
      _nearby.connected
          ? 'Order sent. Waiting for shop confirmation.'
          : 'Order saved. It will send when the shop reconnects.',
    );
  }
}

class CustomerOrdersPage extends StatefulWidget {
  final LocalProfile profile;

  const CustomerOrdersPage({super.key, required this.profile});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  final _nearby = NearbyConnectionService.instance;

  @override
  void initState() {
    super.initState();
    _nearby.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _openOrder(LocalOrderRecord order) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          CustomerOrderDetailPage(profile: widget.profile, orderId: order.id),
    ),
  );

  @override
  void dispose() {
    _nearby.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = AppDatabase.instance.ordersForProfile(widget.profile.id);
    final landscape = Breakpoints.landscapeMobile(context);
    return PageFrame(
      title: 'My orders',
      subtitle: 'Active and previous orders from nearby shops.',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Sync latest order status',
          onPressed: _nearby.connected ? _nearby.requestStatusSync : null,
          icon: const Icon(Icons.sync),
        ),
      ],
      scrollable: landscape,
      child: Column(
        mainAxisSize: landscape ? MainAxisSize.min : MainAxisSize.max,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(14),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFF7DEBFF)),
                SizedBox(width: 10),
                Expanded(
                  child: CustomText(
                    'Orders and related messages are stored on this device for one year. Older records are removed automatically.',
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (landscape)
            orders.isEmpty
                ? const EmptyPanel(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message:
                        'Orders placed with nearby shops will appear here.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return GlassContainer(
                        child: ListTile(
                          onTap: () => _openOrder(order),
                          leading: const CircleAvatar(
                            child: Icon(Icons.takeout_dining_outlined),
                          ),
                          title: CustomText(
                            order.shopName,
                            variant: CustomTextStyle.subtitle,
                          ),
                          subtitle: CustomText(
                            '${order.status.replaceAll('_', ' ')}  |  ${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                            color: Colors.white70,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              CustomText(
                                money(order.total),
                                variant: CustomTextStyle.label,
                              ),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  )
          else
            Expanded(
              child: orders.isEmpty
                  ? const EmptyPanel(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      message:
                          'Orders placed with nearby shops will appear here.',
                    )
                  : ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return GlassContainer(
                          child: ListTile(
                            onTap: () => _openOrder(order),
                            leading: const CircleAvatar(
                              child: Icon(Icons.takeout_dining_outlined),
                            ),
                            title: CustomText(
                              order.shopName,
                              variant: CustomTextStyle.subtitle,
                            ),
                            subtitle: CustomText(
                              '${order.status.replaceAll('_', ' ')}  |  ${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                              color: Colors.white70,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                CustomText(
                                  money(order.total),
                                  variant: CustomTextStyle.label,
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class CustomerSettingsPage extends StatelessWidget {
  final LocalProfile profile;
  final VoidCallback onSwitchProfile;
  final VoidCallback onLogout;

  const CustomerSettingsPage({
    super.key,
    required this.profile,
    required this.onSwitchProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final landscape = Breakpoints.landscapeMobile(context);
    final content = [
      GlassContainer(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit name'),
              subtitle: Text(profile.displayName),
              onTap: () async {
                final controller = TextEditingController(
                  text: profile.displayName,
                );
                final name = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Edit name'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (name == null || name.isEmpty || !context.mounted) return;
                AppDatabase.instance.updateProfileName(profile.id, name);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch profile'),
              subtitle: const Text('Change between Customer and Shopkeeper'),
              onTap: onSwitchProfile,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              subtitle: const Text('Return to local profile selection'),
              onTap: onLogout,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      GlassContainer(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('How to use LIMS'),
              onTap: () => showRoleHelp(context, AppRole.customer),
            ),
          ],
        ),
      ),
    ];
    return PageFrame(
      title: 'Settings',
      subtitle: 'Profiles, nearby connections, and local data.',
      scrollable: landscape,
      child: landscape
          ? Column(children: content)
          : ListView(children: content),
    );
  }
}
