import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/custom_mesh_service.dart';
import '../../shared/ui.dart';

/// Flutter implementation of Meshrabiya's LocalVirtualNodeScreen.
class MeshNodePage extends StatefulWidget {
  const MeshNodePage({super.key});

  @override
  State<MeshNodePage> createState() => _MeshNodePageState();
}

class _MeshNodePageState extends State<MeshNodePage> {
  final _mesh = CustomMeshService.instance;
  String _band = 'BAND_5GHZ';
  String _hotspotType = 'AUTO';
  bool _busy = false;
  String? _error;

  static const _bands = <String, String>{
    'BAND_5GHZ': 'BAND_5GHZ',
    'BAND_2GHZ': 'BAND_2GHZ',
  };
  static const _hotspotTypes = <String, String>{
    'AUTO': 'AUTO',
    'WIFIDIRECT_GROUP': 'WIFIDIRECT_GROUP',
    'LOCALONLY_HOTSPOT': 'LOCALONLY_HOTSPOT',
  };

  @override
  void initState() {
    super.initState();
    _mesh.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mesh.removeListener(_changed);
    super.dispose();
  }

  Future<void> _toggleHotspot(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (enabled) {
        if (!await _mesh.isWifiEnabled()) {
          if (mounted) await _showWifiDisabledDialog();
          return;
        }
        final denied = await _mesh.deniedPermissions();
        if (denied.isNotEmpty) {
          final granted = await _mesh.requestPermissions();
          if (!granted) {
            if (mounted) await _showPermissionSettingsDialog(denied);
            return;
          }
        }
        await _mesh.start();
        await _mesh.enableHotspot(band: _band, hotspotType: _hotspotType);
      } else {
        await _mesh.disableHotspot();
      }
    } on PlatformException catch (error) {
      if (mounted) await _handlePlatformError(error);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPermissionSettingsDialog(
    List<Permission> permissions,
  ) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permissions required'),
        content: Text(
          '${_permissionNames(permissions)} permission is required to create a hotspot. Enable it in app settings and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
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

  String _permissionNames(List<Permission> permissions) {
    final names = <String>{};
    for (final permission in permissions) {
      if (permission == Permission.bluetoothScan ||
          permission == Permission.bluetoothConnect) {
        names.add('Bluetooth');
      } else if (permission == Permission.nearbyWifiDevices) {
        names.add('Nearby Wi-Fi');
      } else if (permission == Permission.locationWhenInUse) {
        names.add('Location');
      }
    }
    return names.join(' and ');
  }

  Future<void> _handlePlatformError(PlatformException error) async {
    if (error.code == 'PERMISSION_DENIED') {
      await _showSettingsDialog(
        title: 'Permission required',
        message:
            error.message ??
            'Nearby Wi-Fi and Bluetooth permissions are required to create a mesh hotspot.',
        open: openAppSettings,
        buttonLabel: 'Open app settings',
      );
    } else if (error.code == 'WIFI_DISABLED') {
      await _showWifiDisabledDialog();
    } else if (mounted) {
      setState(() => _error = error.message ?? _message(error));
    }
  }

  Future<void> _showWifiDisabledDialog() => _showSettingsDialog(
    title: 'Turn on Wi-Fi',
    message:
        'Wi-Fi is disabled. Turn it on in device settings before starting the hotspot.',
    open: _mesh.openWifiSettings,
    buttonLabel: 'Open Wi-Fi settings',
  );

  Future<void> _showSettingsDialog({
    required String title,
    required String message,
    required Future<bool> Function() open,
    required String buttonLabel,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await open();
            },
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }

  String _message(Object error) {
    final text = error.toString().replaceFirst('PlatformException(', '').trim();
    return text.isEmpty ? 'Could not change the hotspot.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final state = _mesh.state;
    final active = state.hotspotEnabled;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('This node'),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _sectionHeader(title: 'Hotspot', icon: Icons.wifi),
            if (!active) ...[
              _chipGroup(
                label: 'Band',
                values: _bands,
                selected: _band,
                onSelected: (value) => setState(() => _band = value),
              ),
              _chipGroup(
                label: 'Hotspot Type',
                values: _hotspotTypes,
                selected: _hotspotType,
                onSelected: (value) => setState(() => _hotspotType = value),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _toggleHotspot(!active),
                child: Text(active ? 'Stop Hotspot' : 'Start Hotspot'),
              ),
            ),
            if (!active)
              _infoTile(
                'This creates a hotspot that other devices can use to connect to this device as a WiFi station (client). It will not share mobile Internet. Any device can operate as a WiFi hotspot and station (client) simultaneously. Once the hotspot is created a QR code will be displayed that can be used to connect devices. This cannot start if you are using the system mobile hotspot and/or tethering.',
              ),
            if (active && state.connectUri?.isNotEmpty == true) ...[
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(data: state.connectUri!),
                    ),
                  ),
                ),
              ),
              if (state.nodes.isNotEmpty)
                ...state.nodes.map(
                  (node) => ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(node.dottedAddress),
                    subtitle: Text('Ping ${node.ping}ms    Hops: ${node.hops}'),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    String? subtitle,
    IconData? icon,
  }) {
    return ListTile(
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
    );
  }

  Widget _infoTile(String text) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(text, style: const TextStyle(color: Colors.white70)),
    );
  }

  Widget _chipGroup({
    required String label,
    required Map<String, String> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in values.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: ChoiceChip(
                      selected: selected == entry.key,
                      label: Text(entry.value),
                      onSelected: (_) => onSelected(entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
