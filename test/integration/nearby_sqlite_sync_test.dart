import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/app_database.dart';
import 'package:lims/core/nearby/transfer_codec.dart';

void main() {
  const codec = BleTransferCodec();
  final now = DateTime.utc(2026, 1, 1);

  Future<AppDatabase> shopWithOrder() async {
    final store = await AppDatabase.openInMemoryForTest();
    final created = DateTime.now();
    store.saveLocalOrder(
      LocalOrderRecord(
        id: 'order-9',
        ownerProfileId: 'shop-9',
        sourceProfileId: 'customer-9',
        version: 1,
        shopId: 'shop-9',
        shopName: 'Shop',
        customerId: 'customer-9',
        customerName: 'Customer',
        status: 'pending',
        total: 42,
        createdAt: created,
        updatedAt: created,
        shareStatus: true,
        chatEnabled: true,
        syncStatus: 'synced',
      ),
      const [],
    );
    return store;
  }

  Future<AppDatabase> customerWithOrder() async {
    final store = await AppDatabase.openInMemoryForTest();
    final created = DateTime.now();
    store.saveLocalOrder(
      LocalOrderRecord(
        id: 'order-9',
        ownerProfileId: 'customer-9',
        sourceProfileId: 'customer-9',
        version: 1,
        shopId: 'shop-9',
        shopName: 'Shop',
        customerId: 'customer-9',
        customerName: 'Customer',
        status: 'waiting_to_send',
        total: 42,
        createdAt: created,
        updatedAt: created,
        shareStatus: true,
        chatEnabled: true,
        syncStatus: 'pending',
      ),
      const [],
    );
    return store;
  }

  test('disconnect mid-transfer loses nothing and resumes cleanly', () async {
    final shop = await shopWithOrder();
    final customer = await customerWithOrder();
    addTearDown(shop.closeForTest);
    addTearDown(customer.closeForTest);

    final message = shop.recordOrderStatusEvent(
      ownerProfileId: 'shop-9',
      orderId: 'order-9',
      eventId: 'event-9',
      peerId: 'customer-9',
      status: 'accepted',
      shareStatus: true,
      chatEnabled: true,
      updatedAt: now.millisecondsSinceEpoch,
    );
    final frames = codec.encode(
      transferId: 3,
      payload: Uint8List.fromList(utf8.encode(jsonEncode(message))),
      maxChunkPayloadBytes: 24,
    );
    expect(frames.length, greaterThan(1));

    // Simulate a disconnect after the first chunk: the receiver gets a
    // partial buffer which must be discarded without touching SQLite.
    final receiver = TransferReassembler();
    expect(receiver.addFrame('shop', frames.first, now), isNull);
    receiver.prune(now.add(const Duration(seconds: 30)));
    expect(receiver.pendingTransfers, 0);
    expect(
      customer.orderForProfile('customer-9', 'order-9')!.status,
      'waiting_to_send',
    );
    // Sender still holds the event as pending: nothing was ACKed.
    expect(customer.queuedSyncPayloads('customer-9'), isEmpty);
    expect(shop.queuedSyncPayloads('customer-9'), hasLength(1));

    // Reconnect: the full transfer arrives and applies exactly once.
    ReassembledTransfer? complete;
    for (final frame in frames) {
      complete = receiver.addFrame('shop', frame, now) ?? complete;
    }
    expect(complete, isNotNull);
    final decoded =
        jsonDecode(utf8.decode(complete!.payload)) as Map<String, dynamic>;
    final applied = customer.applyRemoteStatusEvent(
      ownerProfileId: 'customer-9',
      peerId: 'shop-9',
      eventId: decoded['eventId'] as String,
      orderId: decoded['orderId'] as String,
      status: decoded['status'] as String,
      version: decoded['version'] as int,
      shareStatus: true,
      chatEnabled: true,
      updatedAt: decoded['updatedAt'] as int,
      payloadHash: 'hash-9',
    );
    expect(applied, isTrue);
    expect(
      customer.orderForProfile('customer-9', 'order-9')!.status,
      'accepted',
    );

    // Replay of the same transfer is a side-effect-free duplicate.
    final replay = customer.applyRemoteStatusEvent(
      ownerProfileId: 'customer-9',
      peerId: 'shop-9',
      eventId: decoded['eventId'] as String,
      orderId: decoded['orderId'] as String,
      status: decoded['status'] as String,
      version: decoded['version'] as int,
      shareStatus: true,
      chatEnabled: true,
      updatedAt: decoded['updatedAt'] as int,
      payloadHash: 'hash-9',
    );
    expect(replay, isFalse);
    expect(
      customer.db.select('SELECT COUNT(*) c FROM status_updates').first['c'],
      1,
    );
  });

  test('delta acknowledgement does not hide an unsent order', () async {
    final customer = await customerWithOrder();
    addTearDown(customer.closeForTest);
    final order = customer.orderForProfile('customer-9', 'order-9')!;

    customer.updateLocalOrderSyncState(
      order.ownerProfileId,
      order.id,
      'synced',
    );

    final persisted = customer.orderForProfile('customer-9', 'order-9')!;
    expect(persisted.syncStatus, 'synced');
    expect(persisted.status, 'waiting_to_send');
    expect(customer.unsentOrdersForProfile('customer-9'), [
      isA<LocalOrderRecord>().having((value) => value.id, 'id', 'order-9'),
    ]);
  });
}
