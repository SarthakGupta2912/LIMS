import 'package:flutter_test/flutter_test.dart';
import 'package:lims/core/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'shopkeeper mode persists and existing shops default to counter billing',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);

      final counterProfile = store.createProfile(AppRole.shopkeeper, 'Counter');
      expect(
        store.shopForProfile(counterProfile.id)?.mode,
        ShopkeeperMode.counterBilling,
      );

      final nearbyProfile = store.createProfile(
        AppRole.shopkeeper,
        'Nearby',
        mode: ShopkeeperMode.nearbyOrders,
      );
      expect(
        store.shopForProfile(nearbyProfile.id)?.mode,
        ShopkeeperMode.nearbyOrders,
      );

      final shop = store.shopForProfile(counterProfile.id)!;
      store.saveShopProfile(
        ShopProfileRecord(
          id: shop.id,
          profileId: shop.profileId,
          name: shop.name,
          mode: ShopkeeperMode.nearbyOrders,
        ),
      );
      expect(
        store.shopForProfile(counterProfile.id)?.mode,
        ShopkeeperMode.nearbyOrders,
      );
    },
  );

  test(
    'catalog cache returns independent shops and ignores malformed rows',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);
      final customer = store.createProfile(AppRole.customer, 'Customer');
      final payload =
          '''{"products":[{"id":1,"uuid":"p1","name":"Tea","price":12,"available":true}]}''';
      store.saveCatalogCache(
        ownerProfileId: customer.id,
        shopId: 'shop-a',
        shopName: 'Shop A',
        revision: 3,
        payload: payload,
      );
      store.saveCatalogCache(
        ownerProfileId: customer.id,
        shopId: 'shop-b',
        shopName: 'Shop B',
        revision: 1,
        payload: payload,
      );
      store.db.execute(
        '''INSERT INTO catalog_cache(owner_profile_id, shop_id, shop_name, payload, catalog_revision, synced_at)
         VALUES(?, ?, ?, ?, ?, ?)''',
        [
          customer.id,
          'broken',
          'Broken',
          '{bad',
          1,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

      final shops = store.cachedShops(customer.id);
      expect(
        shops.map((shop) => shop.shop.shopId),
        containsAll(<String>['shop-a', 'shop-b']),
      );
      expect(shops.any((shop) => shop.shop.shopId == 'broken'), isFalse);
      expect(
        shops
            .singleWhere((shop) => shop.shop.shopId == 'shop-a')
            .products
            .single
            .name,
        'Tea',
      );
    },
  );

  test('durable sync migration backfills identity and versions', () async {
    final database = sqlite3.openInMemory();
    database.execute('''
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  price REAL NOT NULL,
  profit_percent REAL NOT NULL DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
INSERT INTO products(name, price, profit_percent, stock_quantity, created_at, updated_at)
VALUES('Paper', 10, 0, 1, 100, 100);
''');
    final store = AppDatabase.forTest(database);
    addTearDown(store.closeForTest);
    store.initializeSchemaForTest();

    final version =
        database.select('PRAGMA user_version').first.values.first as int;
    expect(version, 5);
    final row = database.select('SELECT * FROM products').single;
    expect(row['uuid'], isNotNull);
    expect(row['version'], 1);
    expect(row['sync_status'], 'synced');
    expect(
      database
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('sync_inbox', 'sync_peer_cursors', 'status_updates')",
          )
          .length,
      3,
    );
  });

  test('status event creation is atomic with its outbox entry', () async {
    final store = await AppDatabase.openInMemoryForTest();
    addTearDown(store.closeForTest);
    final now = DateTime.now();
    store.saveLocalOrder(
      LocalOrderRecord(
        id: 'order-1',
        ownerProfileId: 'shop-1',
        sourceProfileId: 'customer-1',
        version: 1,
        shopId: 'shop-1',
        shopName: 'Shop',
        customerId: 'customer-1',
        customerName: 'Customer',
        status: 'pending',
        total: 10,
        createdAt: now,
        updatedAt: now,
        shareStatus: true,
        chatEnabled: true,
        syncStatus: 'synced',
      ),
      const [],
    );
    final message = store.recordOrderStatusEvent(
      ownerProfileId: 'shop-1',
      orderId: 'order-1',
      eventId: 'event-1',
      peerId: 'customer-1',
      status: 'accepted',
      shareStatus: true,
      chatEnabled: true,
      updatedAt: now.millisecondsSinceEpoch,
    );
    expect(message['version'], 2);
    final order = store.orderForProfile('shop-1', 'order-1')!;
    expect(order.status, 'accepted');
    expect(order.version, 2);
    expect(order.syncStatus, 'pending');
    expect(store.queuedSyncPayloads('customer-1'), hasLength(1));
    expect(
      store.db.select('SELECT COUNT(*) c FROM status_updates').first['c'],
      1,
    );
  });

  test(
    'buzz session and post-stop cooldown are persisted atomically',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);
      final now = DateTime(2026, 9, 20, 10);
      store.saveLocalOrder(
        LocalOrderRecord(
          id: 'order-1',
          ownerProfileId: 'shop-1',
          shopId: 'shop-1',
          shopName: 'Shop',
          customerId: 'customer-1',
          customerName: 'Customer',
          status: 'accepted',
          total: 10,
          createdAt: now,
          updatedAt: now,
          shareStatus: true,
          chatEnabled: true,
        ),
        const [],
      );

      expect(
        store.reserveOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'buzz-1',
          now: now,
        ),
        isTrue,
      );
      expect(store.orderForProfile('shop-1', 'order-1')!.lastBuzzAt, now);
      final active = store.orderForProfile('shop-1', 'order-1')!;
      expect(active.buzzEventId, 'buzz-1');
      expect(active.buzzEndsAt, now.add(const Duration(minutes: 5)));
      expect(active.buzzStoppedAt, isNull);
      expect(
        store.reserveOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'buzz-2',
          now: now.add(const Duration(minutes: 5, seconds: 29)),
        ),
        isFalse,
      );
      expect(
        store.stopOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'stale-buzz',
          stoppedAt: now.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(
        store.stopOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'buzz-1',
          stoppedAt: now.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(
        store.reserveOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'buzz-2',
          now: now.add(const Duration(minutes: 1, seconds: 29)),
        ),
        isFalse,
      );
      expect(
        store.reserveOrderBuzz(
          profileId: 'shop-1',
          orderId: 'order-1',
          eventId: 'buzz-2',
          now: now.add(const Duration(minutes: 1, seconds: 30)),
        ),
        isTrue,
      );
      store.releaseOrderBuzz(
        profileId: 'shop-1',
        orderId: 'order-1',
        eventId: 'buzz-2',
      );
      final released = store.orderForProfile('shop-1', 'order-1')!;
      expect(released.lastBuzzAt, isNull);
      expect(released.buzzEventId, isNull);
      expect(released.buzzEndsAt, isNull);
    },
  );

  test('duplicate incoming buzzes are claimed only once', () async {
    final store = await AppDatabase.openInMemoryForTest();
    addTearDown(store.closeForTest);

    expect(
      store.claimIncomingBuzz(
        eventId: 'buzz-1',
        peerId: 'shop-1',
        orderId: 'order-1',
        payloadHash: 'hash',
      ),
      isTrue,
    );
    expect(
      store.claimIncomingBuzz(
        eventId: 'buzz-1',
        peerId: 'shop-1',
        orderId: 'order-1',
        payloadHash: 'hash',
      ),
      isFalse,
    );
  });

  test('status history is ordered and isolated by owner profile', () async {
    final store = await AppDatabase.openInMemoryForTest();
    addTearDown(store.closeForTest);
    final created = DateTime(2026, 9, 20, 10);
    for (final profileId in ['customer-1', 'customer-2']) {
      store.saveLocalOrder(
        LocalOrderRecord(
          id: 'order-1',
          ownerProfileId: profileId,
          sourceProfileId: profileId,
          shopId: 'shop-1',
          shopName: 'Shop',
          customerId: profileId,
          customerName: 'Customer',
          status: 'pending',
          total: 10,
          createdAt: created,
          updatedAt: created,
          shareStatus: true,
          chatEnabled: true,
        ),
        const [],
      );
    }
    store.applyRemoteStatusEvent(
      ownerProfileId: 'customer-1',
      peerId: 'shop-1',
      eventId: 'event-2',
      orderId: 'order-1',
      status: 'accepted',
      version: 2,
      shareStatus: true,
      chatEnabled: true,
      updatedAt: created.add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      payloadHash: 'hash-2',
    );
    store.applyRemoteStatusEvent(
      ownerProfileId: 'customer-1',
      peerId: 'shop-1',
      eventId: 'event-3',
      orderId: 'order-1',
      status: 'preparing',
      version: 3,
      shareStatus: true,
      chatEnabled: true,
      updatedAt: created.add(const Duration(minutes: 8)).millisecondsSinceEpoch,
      payloadHash: 'hash-3',
    );

    final history = store.orderStatusUpdates('customer-1', 'order-1');
    expect(history.map((event) => event.status), ['accepted', 'preparing']);
    expect(history.map((event) => event.version), [2, 3]);
    expect(history.first.updatedAt, created.add(const Duration(minutes: 3)));
    expect(store.orderStatusUpdates('customer-2', 'order-1'), isEmpty);
  });

  test(
    'shop receipt acknowledgment is stored as the first status event',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);
      final created = DateTime(2026, 9, 20, 10);
      store.saveLocalOrder(
        LocalOrderRecord(
          id: 'order-1',
          ownerProfileId: 'customer-1',
          sourceProfileId: 'customer-1',
          shopId: 'shop-1',
          shopName: 'Shop',
          customerId: 'customer-1',
          customerName: 'Customer',
          status: 'waiting_to_send',
          total: 10,
          createdAt: created,
          updatedAt: created,
          shareStatus: true,
          chatEnabled: true,
          syncStatus: 'pending',
        ),
        const [],
      );

      store.acknowledgeLocalOrder(profileId: 'customer-1', orderId: 'order-1');

      final order = store.orderForProfile('customer-1', 'order-1')!;
      final history = store.orderStatusUpdates('customer-1', 'order-1');
      expect(order.status, 'pending');
      expect(order.syncStatus, 'synced');
      expect(history, hasLength(1));
      expect(history.single.status, 'pending');
      expect(history.single.version, 1);
    },
  );

  test(
    'expired order cleanup removes items, messages, and status history',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);
      final created = DateTime(2024, 1, 1);
      store.saveLocalOrder(
        LocalOrderRecord(
          id: 'expired-order',
          ownerProfileId: 'customer-1',
          sourceProfileId: 'customer-1',
          shopId: 'shop-1',
          shopName: 'Shop',
          customerId: 'customer-1',
          customerName: 'Customer',
          status: 'completed',
          total: 10,
          createdAt: created,
          updatedAt: created,
          shareStatus: true,
          chatEnabled: true,
        ),
        const [
          LocalOrderItemRecord(
            id: 'item-1',
            orderId: 'expired-order',
            ownerProfileId: 'customer-1',
            productName: 'Tea',
            quantity: 1,
            unitPrice: 10,
            total: 10,
          ),
        ],
      );
      store.db.execute(
        '''INSERT INTO status_updates(
        id, order_id, owner_profile_id, shop_id, customer_id, status,
        share_status, chat_enabled, sync_status, updated_at, version
      ) VALUES('event-1', 'expired-order', 'customer-1', 'shop-1',
        'customer-1', 'completed', 1, 1, 'synced', ?, 2)''',
        [created.millisecondsSinceEpoch],
      );
      store.db.execute(
        '''INSERT INTO order_messages(
        id, order_id, owner_profile_id, sender_role, body, sent_at
      ) VALUES('message-1', 'expired-order', 'customer-1', 'shopkeeper',
        'Ready', ?)''',
        [created.millisecondsSinceEpoch],
      );

      expect(store.cleanupExpiredOrders(), 1);
      expect(store.orderForProfile('customer-1', 'expired-order'), isNull);
      expect(store.orderItems('customer-1', 'expired-order'), isEmpty);
      expect(store.orderStatusUpdates('customer-1', 'expired-order'), isEmpty);
      expect(store.count('order_messages'), 0);
    },
  );

  test(
    'duplicate remote events are idempotent and stale versions lose',
    () async {
      final store = await AppDatabase.openInMemoryForTest();
      addTearDown(store.closeForTest);
      final now = DateTime.now();
      store.saveLocalOrder(
        LocalOrderRecord(
          id: 'order-1',
          ownerProfileId: 'customer-1',
          sourceProfileId: 'customer-1',
          version: 1,
          shopId: 'shop-1',
          shopName: 'Shop',
          customerId: 'customer-1',
          customerName: 'Customer',
          status: 'pending',
          total: 10,
          createdAt: now,
          updatedAt: now,
          shareStatus: true,
          chatEnabled: true,
          syncStatus: 'pending',
        ),
        const [],
      );
      final first = store.applyRemoteStatusEvent(
        ownerProfileId: 'customer-1',
        peerId: 'shop-1',
        eventId: 'event-2',
        orderId: 'order-1',
        status: 'accepted',
        version: 2,
        shareStatus: true,
        chatEnabled: true,
        updatedAt: now.millisecondsSinceEpoch,
        payloadHash: 'hash-2',
      );
      final duplicate = store.applyRemoteStatusEvent(
        ownerProfileId: 'customer-1',
        peerId: 'shop-1',
        eventId: 'event-2',
        orderId: 'order-1',
        status: 'accepted',
        version: 2,
        shareStatus: true,
        chatEnabled: true,
        updatedAt: now.millisecondsSinceEpoch,
        payloadHash: 'hash-2',
      );
      final stale = store.applyRemoteStatusEvent(
        ownerProfileId: 'customer-1',
        peerId: 'shop-1',
        eventId: 'event-1',
        orderId: 'order-1',
        status: 'pending',
        version: 1,
        shareStatus: true,
        chatEnabled: true,
        updatedAt: now.millisecondsSinceEpoch - 1000,
        payloadHash: 'hash-1',
      );
      expect(first, isTrue);
      expect(duplicate, isFalse);
      expect(stale, isFalse);
      final order = store.orderForProfile('customer-1', 'order-1')!;
      expect(order.status, 'accepted');
      expect(order.version, 2);
      expect(
        store.db.select('SELECT COUNT(*) c FROM status_updates').first['c'],
        1,
      );
      expect(store.count('sync_inbox'), 2);
    },
  );

  test('outbox ACKs are scoped to the matching event id', () async {
    final store = await AppDatabase.openInMemoryForTest();
    addTearDown(store.closeForTest);
    store.enqueueSyncEvent(
      id: 'event-a',
      ownerProfileId: 'shop-1',
      peerId: 'customer-1',
      entityType: 'order_status',
      entityId: 'order-1',
      entityVersion: 2,
      kind: 'order_status',
      payload: '{}',
    );
    store.enqueueSyncEvent(
      id: 'event-b',
      ownerProfileId: 'shop-1',
      peerId: 'customer-1',
      entityType: 'order_status',
      entityId: 'order-1',
      entityVersion: 3,
      kind: 'order_status',
      payload: '{}',
    );
    store.removeSyncPayload('event-a');
    final remaining = store.queuedSyncPayloads('customer-1');
    expect(remaining, hasLength(1));
    expect(remaining.single['id'], 'event-b');
  });

  test('new sync infrastructure tables accept inbox and cursor rows', () async {
    final store = await AppDatabase.openInMemoryForTest();
    addTearDown(store.closeForTest);
    store.db.execute(
      '''INSERT INTO sync_inbox(event_id, peer_id, entity_type, entity_id, entity_version, payload_hash, applied_at)
         VALUES('event-1', 'peer-1', 'order_status', 'order-1', 2, 'hash', 100)''',
    );
    store.db.execute(
      '''INSERT INTO sync_peer_cursors(local_profile_id, peer_id, stream, last_updated_at, last_version, last_record_id, updated_at)
         VALUES('profile-1', 'peer-1', 'statuses', 100, 2, 'order-1', 101)''',
    );
    expect(store.count('sync_inbox'), 1);
    expect(store.count('sync_peer_cursors'), 1);
  });
}
