import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_database.dart';
import 'nearby_connection_service.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  static const _nearbyServiceId = 2001;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _navigateController = StreamController<String>.broadcast();
  bool _initialized = false;
  bool _nearbyServiceRunning = false;
  Future<void> _nearbyServiceOperation = Future.value();
  String? _pendingOrderId;

  /// Emits an order id whenever a notification tap/action should open the
  /// orders screen. Shells subscribe; the terminated-launch case is covered
  /// by [consumePendingOrderId].
  Stream<String> get onNavigateToOrder => _navigateController.stream;

  String? consumePendingOrderId() {
    final orderId = _pendingOrderId;
    _pendingOrderId = null;
    return orderId;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_lims'),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
    } catch (error) {
      // Notifications must never prevent the app from starting.
      debugPrint('Local notifications unavailable: $error');
    }
    _initialized = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showNewOrder(LocalOrderRecord order) async {
    await initialize();
    await _plugin.show(
      id: _notificationId(order.id),
      title: 'New order from ${order.customerName}',
      body: '${order.total.toStringAsFixed(2)}  |  Tap to review',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'new_orders',
          'New orders',
          channelDescription: 'New customer orders',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(
              'accept_order',
              'Accept · 15 min',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'review_order',
              'Review / Reject',
              showsUserInterface: true,
            ),
          ],
          category: AndroidNotificationCategory.message,
          onlyAlertOnce: true,
        ),
      ),
      payload: jsonEncode({
        'type': 'new_order',
        'orderId': order.id,
        'profileId': order.ownerProfileId,
      }),
    );
  }

  Future<void> showOrderUpdate(LocalOrderRecord order) async {
    await initialize();
    await _plugin.show(
      id: _notificationId(order.id),
      title: order.shopName,
      body: _statusText(order),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'order_updates',
          'Order updates',
          channelDescription: 'Updates for active orders',
          importance: Importance.high,
          priority: Priority.high,
          onlyAlertOnce: true,
        ),
      ),
      payload: jsonEncode({
        'type': 'order_update',
        'orderId': order.id,
        'profileId': order.ownerProfileId,
      }),
    );
  }

  Future<void> showMessage({
    required String orderId,
    required String shopName,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id: _notificationId('$orderId-message'),
      title: 'Message from $shopName',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          'Order messages',
          channelDescription: 'Messages related to nearby orders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: jsonEncode({'type': 'message', 'orderId': orderId}),
    );
  }

  Future<void> showCustomerBuzz(CustomerBuzzEvent event) async {
    await initialize();
    await _plugin.show(
      id: _notificationId('${event.eventId}-buzz'),
      title: '${event.shopName} needs your attention',
      body:
          'Your phone will vibrate for 30 seconds each minute. Tap to respond.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'customer_buzz_sessions',
          'Active shopkeeper buzzes',
          channelDescription: 'Active vibration requests from nearby shops',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          enableVibration: false,
          playSound: false,
          silent: true,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.public,
          actions: [
            AndroidNotificationAction(
              'stop_buzz',
              'Stop buzzing',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'view_buzz_order',
              'View order',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: jsonEncode({
        'type': 'customer_buzz',
        'eventId': event.eventId,
        'orderId': event.orderId,
        'shopId': event.shopId,
      }),
    );
  }

  Future<void> cancelCustomerBuzz(String eventId) =>
      _plugin.cancel(id: _notificationId('$eventId-buzz'));

  /// Keeps Nearby Connections active only while there is nearby work.
  /// work (Shop visibility or a pending/active customer order). No-op
  /// outside Android.
  Future<void> startNearbyService(String body) =>
      _setNearbyService(running: true, body: body);

  Future<void> stopNearbyService() => _setNearbyService(running: false);

  Future<void> _setNearbyService({required bool running, String body = ''}) {
    final operation = _nearbyServiceOperation.then((_) async {
      await _setNearbyServiceNow(running: running, body: body);
    });
    _nearbyServiceOperation = operation.catchError((_) {});
    return operation;
  }

  Future<void> _setNearbyServiceNow({
    required bool running,
    String body = '',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    try {
      if (running) {
        if (_nearbyServiceRunning) return;
        await android.startForegroundService(
          id: _nearbyServiceId,
          title: 'LIMS nearby service',
          body: body.isEmpty ? 'Keeping nearby orders connected' : body,
          notificationDetails: const AndroidNotificationDetails(
            'nearby_service',
            'Nearby service',
            channelDescription: 'Keeps nearby orders connected in background',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            silent: true,
          ),
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeConnectedDevice,
          },
        );
        _nearbyServiceRunning = true;
      } else {
        if (!_nearbyServiceRunning) return;
        await android.stopForegroundService();
        _nearbyServiceRunning = false;
      }
    } catch (error) {
      debugPrint('Nearby foreground service failed: $error');
    }
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final orderId = payload['orderId'] as String?;
      if (payload['type'] == 'customer_buzz') {
        final eventId = payload['eventId'] as String?;
        if (eventId != null) {
          await NearbyConnectionService.instance.respondToCustomerBuzz(eventId);
        }
        if (response.actionId == 'stop_buzz') return;
      }
      // Store the destination before doing any action-specific work. This
      // preserves a body tap while the app is still starting up.
      if (orderId != null && response.actionId != 'accept_order') {
        _pendingOrderId = orderId;
      }
      if (response.actionId == 'accept_order' &&
          payload['type'] == 'new_order' &&
          orderId != null) {
        await AppDatabase.instance.open();
        final profileId = payload['profileId'] as String;
        final order = AppDatabase.instance.orderForProfile(profileId, orderId);
        // Guard against double-taps: only a still-pending order is accepted.
        if (order == null || order.status != 'pending') return;
        await NearbyConnectionService.instance.updateOrderStatus(
          order: order,
          status: 'accepted',
          pickupAt: DateTime.now().add(const Duration(minutes: 15)),
          shareStatus: order.shareStatus,
          chatEnabled: order.chatEnabled,
        );
        _pendingOrderId = orderId;
        _navigateController.add(orderId);
      } else if (orderId != null) {
        // Plain tap, Review / Reject, or order update: open the orders
        // screen. Rejection remains a confirmed action inside the UI.
        _navigateController.add(orderId);
      }
    } catch (error) {
      debugPrint('Notification action failed: $error');
    }
  }

  int _notificationId(String value) {
    var result = 17;
    for (final byte in utf8.encode(value)) {
      result = (result * 31 + byte) & 0x7fffffff;
    }
    return result == 0 ? 1 : result;
  }

  String _statusText(LocalOrderRecord order) => switch (order.status) {
    'accepted' =>
      order.pickupAt == null
          ? 'Order accepted'
          : 'Accepted  |  Pickup ${_time(order.pickupAt!)}',
    'preparing' => 'Your order is being prepared',
    'ready_for_pickup' => 'Your order is ready for pickup',
    'completed' => 'Order completed',
    'rejected' => 'Order rejected by the shop',
    'cancelled' => 'Order cancelled',
    _ => 'Order status: ${order.status.replaceAll('_', ' ')}',
  };

  String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}
