import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/custom_mesh_service.dart';
import '../../core/app_database.dart';
import '../../core/nearby_connection_service.dart';
import '../../shared/ui.dart';

class MeshrabiyaPage extends StatefulWidget {
  const MeshrabiyaPage({super.key, required this.active, this.role})
    : nodeOnly = false;

  const MeshrabiyaPage.thisNode({super.key})
    : active = true,
      nodeOnly = true,
      role = AppRole.shopkeeper;

  final bool active;
  final bool nodeOnly;
  final AppRole? role;

  @override
  State<MeshrabiyaPage> createState() => _MeshrabiyaPageState();
}

class _MeshrabiyaPageState extends State<MeshrabiyaPage> {
  static const _channel = MethodChannel('lims/meshrabiya');
  static const _events = EventChannel('lims/meshrabiya/events');
  StreamSubscription<Object?>? _subscription;
  Map<Object?, Object?> _state = {};
  bool _starting = false;
  bool _busy = false;
  String? _error;
  String _band = 'BAND_5GHZ';
  String? _selectedPath;
  String? _contacting;
  int _index = 0;
  final Set<String> _pendingActions = {};

  @override
  void initState() {
    super.initState();
    NearbyConnectionService.instance.addListener(_nearbyChanged);
    if (widget.active) unawaited(_start());
  }

  void _nearbyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(MeshrabiyaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _state['address'] == null) {
      unawaited(_start());
    }
  }

  void _update(Object? value) {
    if (!mounted || value is! Map) return;
    setState(() {
      _state = Map<Object?, Object?>.from(value);
      if (_state['supports5Ghz'] == false) _band = 'BAND_2GHZ';
    });
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (!CustomMeshService.instance.supported) {
        throw UnsupportedError('Hotspot requires an Android device.');
      }
      await CustomMeshService.instance.start();
      _subscription ??= _events.receiveBroadcastStream().listen(
        _update,
        onError: _showError,
      );
      _update(await _channel.invokeMethod<Object?>('start'));
      final profile = AppDatabase.instance.activeProfile();
      if (profile?.role == AppRole.shopkeeper) {
        final shop = AppDatabase.instance.shopForProfile(profile!.id);
        if (shop != null) {
          await NearbyConnectionService.instance.startAdvertising(
            profile,
            shop,
          );
        }
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is PlatformException
          ? error.message ?? error.code
          : error.toString();
    });
  }

  Future<void> _operate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hotspot() => _operate(() async {
    if (_state['hotspotEnabled'] != true &&
        !await CustomMeshService.instance.isWifiEnabled()) {
      await CustomMeshService.instance.openWifiSettings();
      return;
    }
    await _channel.invokeMethod<Object?>('hotspot', {
      'enabled': _state['hotspotEnabled'] != true,
      'band': _band,
      'type': 'AUTO',
    });
  });

  Future<void> _pickFile() => _operate(() async {
    final result = await FilePicker.pickFile();
    final path = result?.path;
    if (path != null && mounted) setState(() => _selectedPath = path);
  });

  Future<void> _send(String address) => _operate(() async {
    setState(() => _contacting = address);
    try {
      _update(
        await _channel.invokeMethod<Object?>('send', {
          'path': _selectedPath,
          'address': address,
        }),
      );
      if (mounted) setState(() => _selectedPath = null);
    } finally {
      if (mounted) setState(() => _contacting = null);
    }
  });

  Future<void> _incomingAction(String action, Map transfer) async {
    final key =
        '${transfer['host']}/${transfer['id']}/${transfer['receivedAt']}';
    if (!_pendingActions.add(key)) return;
    setState(() => _error = null);
    try {
      _update(
        await _channel.invokeMethod<Object?>(action, {
          'id': transfer['id'],
          'host': transfer['host'],
          'receivedAt': transfer['receivedAt'],
        }),
      );
    } catch (error) {
      _showError(error);
    } finally {
      _pendingActions.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _open(Map transfer) async {
    final path = transfer['file'] as String?;
    if (path == null) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) _showError(result.message);
  }

  @override
  void dispose() {
    NearbyConnectionService.instance.removeListener(_nearbyChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _index == 1 && _selectedPath != null;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: widget.nodeOnly,
          leading: selecting
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _selectedPath = null),
                )
              : widget.nodeOnly
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text(
            selecting
                ? 'Select receiver'
                : ['Hotspot', 'Send', 'Receive'][_index],
          ),
        ),
        body: Column(
          children: [
            if (_starting) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(_error!),
                trailing: _state['address'] == null && !_starting
                    ? IconButton(
                        tooltip: 'Retry',
                        onPressed: _start,
                        icon: const Icon(Icons.refresh),
                      )
                    : IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => setState(() => _error = null),
                        icon: const Icon(Icons.close),
                      ),
              ),
            Expanded(
              child: switch (_index) {
                0 => _thisNode(),
                1 => selecting ? _receivers() : _sendList(),
                _ => _receiveList(),
              },
            ),
          ],
        ),
        floatingActionButton: _index == 1 && !selecting
            ? SizedBox(
                height: 56,
                child: FloatingActionButton.extended(
                  onPressed: _busy || _state['address'] == null
                      ? null
                      : _pickFile,
                  icon: const Icon(Icons.send),
                  label: const Text('Send File'),
                ),
              )
            : const SizedBox.shrink(),
        bottomNavigationBar: widget.nodeOnly
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (index) =>
                    setState(() => _index = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.wifi_tethering),
                    label: 'Hotspot',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.upload_file),
                    label: 'Send',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.download),
                    label: 'Receive',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _thisNode() {
    final active = _state['hotspotEnabled'] == true;
    final starting = _busy || _state['hotspotStarting'] == true;
    final customers = NearbyConnectionService.instance.connectedMeshCustomers;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(
              active ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomText(
                starting
                    ? 'Starting hotspot'
                    : active
                    ? 'Hotspot active'
                    : 'Hotspot off',
                variant: CustomTextStyle.title,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!active) ...[
          const CustomText('Wi-Fi band', variant: CustomTextStyle.label),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final band in [
                if (_state['supports5Ghz'] != false) 'BAND_5GHZ',
                'BAND_2GHZ',
              ])
                ChoiceChip(
                  label: Text(band == 'BAND_5GHZ' ? '5 GHz' : '2.4 GHz'),
                  selected: _band == band,
                  onSelected: starting
                      ? null
                      : (_) => setState(() => _band = band),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: starting || _state['address'] == null ? null : _hotspot,
            icon: starting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    active ? Icons.stop_circle_outlined : Icons.wifi_tethering,
                  ),
            label: Text(active ? 'Stop hotspot' : 'Start hotspot'),
          ),
        ),
        if (active && _state['connectUri'] != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: _state['connectUri'] as String,
                    size: (constraints.maxWidth - 24).clamp(0, 260).toDouble(),
                  ),
                ),
              ),
            ),
          ),
        if (widget.role == AppRole.shopkeeper) ...[
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: CustomText(
                  'Connected customers',
                  variant: CustomTextStyle.subtitle,
                ),
              ),
              Text('${customers.length}'),
            ],
          ),
          const SizedBox(height: 12),
          if (customers.isEmpty)
            const CustomText('No customers connected', color: Colors.white70)
          else
            for (final customer in customers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassContainer(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: CustomText(customer.name),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  Widget _sendList() => ListView(
    padding: const EdgeInsets.only(bottom: 88),
    children: [
      for (final t in (_state['outgoing'] as List? ?? []).whereType<Map>())
        ListTile(
          title: Text('${t['name']} -> ${t['host']}'),
          subtitle: Text(
            'Status: ${t['status']} Sent ${t['transferred']} / ${t['size']}',
          ),
        ),
    ],
  );

  Widget _receivers() => ListView(
    children: [
      if (_contacting != null) ...[
        const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          ),
        ),
        Center(
          child: Text(
            'Contacting $_contacting\nThis might take a few seconds.',
          ),
        ),
      ] else
        for (final node in (_state['nodes'] as List? ?? []).whereType<Map>())
          ListTile(
            title: Text('${node['address']}'),
            subtitle: Text('Ping ${node['ping']}ms    Hops: ${node['hops']}'),
            onTap: _busy ? null : () => _send(node['address'] as String),
          ),
    ],
  );

  Widget _receiveList() => ListView(
    children: [
      for (final t in (_state['incoming'] as List? ?? []).whereType<Map>())
        ListTile(
          title: Text('${t['name']}'),
          onTap: t['status'] == 'COMPLETED' ? () => _open(t) : null,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From ${t['host']} (${t['status']})'),
              Text(
                '${t['transferred']} / ${t['size']} bytes${t['status'] == 'COMPLETED' ? ' @ ${(t['size'] as num) ~/ (t['transferTime'] as num)}KB/s (${t['transferTime']})ms' : ''}',
              ),
              if (t['status'] == 'PENDING')
                Wrap(
                  spacing: 16,
                  children: [
                    for (final action in ['accept', 'decline'])
                      OutlinedButton(
                        onPressed:
                            _pendingActions.contains(
                              '${t['host']}/${t['id']}/${t['receivedAt']}',
                            )
                            ? null
                            : () => _incomingAction(action, t),
                        child: Text(action == 'accept' ? 'Accept' : 'Decline'),
                      ),
                  ],
                ),
              if (t['status'] == 'COMPLETED')
                OutlinedButton(
                  onPressed: () => _open(t),
                  child: const Text('Open'),
                ),
            ],
          ),
          trailing: t['status'] == 'COMPLETED'
              ? IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _incomingAction('delete', t),
                  icon: const Icon(Icons.delete),
                )
              : null,
        ),
    ],
  );
}
