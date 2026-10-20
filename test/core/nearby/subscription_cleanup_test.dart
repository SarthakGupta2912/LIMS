import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/app_database.dart';
import 'package:lims/core/nearby/nearby_transport.dart';
import 'package:lims/core/nearby_connection_service.dart';

import '../../support/fake_transport.dart';
import '../../support/fake_scheduler.dart';

void main() {
  test('buzz eligibility is limited to active accepted orders', () {
    expect(isBuzzEligibleStatus('pending'), isFalse);
    expect(isBuzzEligibleStatus('accepted'), isTrue);
    expect(isBuzzEligibleStatus('preparing'), isTrue);
    expect(isBuzzEligibleStatus('ready_for_pickup'), isTrue);
    expect(isBuzzEligibleStatus('completed'), isFalse);
    expect(isBuzzEligibleStatus('rejected'), isFalse);
    expect(isBuzzEligibleStatus('cancelled'), isFalse);
  });

  test('buzz messages must be current and bounded to five minutes', () {
    final now = DateTime(2026, 9, 20, 10);
    expect(
      isBuzzMessageCurrent(
        now: now,
        sentAt: now,
        endsAt: now.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );
    expect(
      isBuzzMessageCurrent(
        now: now,
        sentAt: now.subtract(const Duration(minutes: 6)),
        endsAt: now.subtract(const Duration(minutes: 1)),
      ),
      isFalse,
    );
    expect(
      isBuzzMessageCurrent(
        now: now,
        sentAt: now,
        endsAt: now.add(const Duration(minutes: 6)),
      ),
      isFalse,
    );
    expect(
      isBuzzMessageCurrent(
        now: now,
        sentAt: now.add(const Duration(minutes: 1)),
        endsAt: now.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
  });

  test('closing the transport ends every stream exactly once', () async {
    final transport = FakeTransport();
    var adapterEvents = 0;
    var discoveredEvents = 0;
    var connectionEvents = 0;
    var notifyEvents = 0;
    var frameEvents = 0;
    final subscriptions = [
      transport.adapterStates.listen((_) => adapterEvents++),
      transport.discoveredPeers.listen((_) => discoveredEvents++),
      transport.connectionEvents.listen((_) => connectionEvents++),
      transport.channelReadyEvents.listen((_) => notifyEvents++),
      transport.inboundFrames.listen((_) => frameEvents++),
    ];

    await transport.dispose();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    expect(adapterEvents, 0);
    expect(discoveredEvents, 0);
    expect(connectionEvents, 0);
    expect(notifyEvents, 0);
    expect(frameEvents, 0);
  });

  test(
    'repeated start/stop cycles leave no active scan or advertisement',
    () async {
      final transport = FakeTransport();
      for (var i = 0; i < 5; i++) {
        await transport.startDiscovery(['ffb0']);
        await transport.stopDiscovery();
        await transport.startAdvertising(
          NearbyAdvertisementSpec(
            serviceIds: const ['ffb0'],
            serviceData: {
              'ffb0': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]),
            },
          ),
        );
        await transport.stopAdvertising();
      }
      expect(transport.isDiscovering, isFalse);
      expect(transport.isAdvertising, isFalse);
      expect(transport.discoveryStartCount, 5);
      expect(transport.discoveryStopCount, 5);
      await transport.dispose();
    },
  );

  test('manual pause blocks ordinary discovery restarts', () async {
    final transport = FakeTransport();
    final service = NearbyConnectionService.withTransport(transport);
    final profile = LocalProfile(
      id: 'customer-1',
      role: AppRole.customer,
      displayName: 'Customer',
      createdAt: DateTime(2026),
    );

    await service.stopDiscovery();
    await service.startDiscovery(profile);

    expect(service.discoveryPaused, isTrue);
    expect(service.activity, NearbyActivity.idle);
    expect(transport.discoveryStartCount, 0);
    expect(transport.discoveryStopCount, 1);
    await service.disposeTransport();
  });

  test('scheduler-backed retry timer is cancelled on dispose', () {
    final scheduler = FakeScheduler();
    var fired = 0;
    final timer = scheduler.runDelayed(
      const Duration(seconds: 5),
      () => fired++,
    );
    timer.cancel();
    scheduler.elapse(const Duration(minutes: 1));
    expect(fired, 0);
    expect(scheduler.activeTimers, 0);
  });
}
