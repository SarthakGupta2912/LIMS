import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../data/sync_columns_migration.dart';

enum AppRole { customer, shopkeeper }

enum ShopkeeperMode { counterBilling, nearbyOrders }

class LocalProfile {
  final String id;
  final AppRole role;
  final String displayName;
  final DateTime createdAt;

  const LocalProfile({
    required this.id,
    required this.role,
    required this.displayName,
    required this.createdAt,
  });

  factory LocalProfile.fromRow(Row row) => LocalProfile(
    id: row['id'] as String,
    role: AppRole.values.byName(row['role'] as String),
    displayName: row['display_name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );
}

class ShopProfileRecord {
  final String id;
  final String profileId;
  final String name;
  final String category;
  final String contact;
  final bool visible;
  final bool orderingEnabled;
  final bool statusEnabled;
  final bool chatEnabled;
  final ShopkeeperMode mode;
  final int catalogRevision;

  const ShopProfileRecord({
    required this.id,
    required this.profileId,
    required this.name,
    this.category = 'General',
    this.contact = '',
    this.visible = false,
    this.orderingEnabled = true,
    this.statusEnabled = true,
    this.chatEnabled = true,
    this.mode = ShopkeeperMode.counterBilling,
    this.catalogRevision = 1,
  });

  factory ShopProfileRecord.fromRow(Row row) => ShopProfileRecord(
    id: row['id'] as String,
    profileId: row['profile_id'] as String,
    name: row['name'] as String,
    category: row['category'] as String,
    contact: row['contact'] as String,
    visible: (row['visible'] as int) == 1,
    orderingEnabled: (row['ordering_enabled'] as int) == 1,
    statusEnabled: (row['status_enabled'] as int) == 1,
    chatEnabled: (row['chat_enabled'] as int) == 1,
    mode: ShopkeeperMode.values.byName(
      (row['mode'] as String?) ?? ShopkeeperMode.counterBilling.name,
    ),
    catalogRevision: row['catalog_revision'] as int,
  );
}

class ProductRecord {
  final int? id;
  final String uuid;
  final String? ownerProfileId;
  final String? sourceProfileId;
  final String name;
  final double price;
  final double profitPercent;
  final int stockQuantity;
  final String description;
  final String category;
  final String? imagePath;
  final bool isAvailable;
  final bool isPublished;
  final String syncStatus;
  final int version;
  final DateTime? deletedAt;

  const ProductRecord({
    this.id,
    this.uuid = '',
    this.ownerProfileId,
    this.sourceProfileId,
    required this.name,
    required this.price,
    this.profitPercent = 0,
    this.stockQuantity = 0,
    this.description = '',
    this.category = 'General',
    this.imagePath,
    this.isAvailable = true,
    this.isPublished = false,
    this.syncStatus = 'pending',
    this.version = 1,
    this.deletedAt,
  });

  factory ProductRecord.fromRow(Row row) => ProductRecord(
    id: row['id'] as int,
    uuid: (row['uuid'] as String?) ?? '',
    ownerProfileId: row['owner_profile_id'] as String?,
    sourceProfileId: row['source_profile_id'] as String?,
    name: row['name'] as String,
    price: (row['price'] as num).toDouble(),
    profitPercent: (row['profit_percent'] as num).toDouble(),
    stockQuantity: row['stock_quantity'] as int,
    description: (row['description'] as String?) ?? '',
    category: (row['category'] as String?) ?? 'General',
    imagePath: row['image_path'] as String?,
    isAvailable: ((row['is_available'] as int?) ?? 1) == 1,
    isPublished: ((row['is_published'] as int?) ?? 0) == 1,
    syncStatus: (row['sync_status'] as String?) ?? 'pending',
    version: (row['version'] as int?) ?? 1,
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int),
  );
}

class NearbyShopRecord {
  final String shopId;
  final String name;
  final String category;
  final bool orderingEnabled;
  final bool statusEnabled;
  final bool chatEnabled;
  final int catalogRevision;
  final DateTime lastSeen;

  const NearbyShopRecord({
    required this.shopId,
    required this.name,
    required this.category,
    required this.orderingEnabled,
    required this.statusEnabled,
    required this.chatEnabled,
    required this.catalogRevision,
    required this.lastSeen,
  });
}

class CachedShopRecord {
  final NearbyShopRecord shop;
  final List<ProductRecord> products;
  final DateTime syncedAt;

  const CachedShopRecord({
    required this.shop,
    required this.products,
    required this.syncedAt,
  });
}

class LocalOrderRecord {
  final String id;
  final String ownerProfileId;
  final String? sourceProfileId;
  final int version;
  final String shopId;
  final String shopName;
  final String customerId;
  final String customerName;
  final String status;
  final double total;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? pickupAt;
  final bool shareStatus;
  final bool chatEnabled;
  final String note;
  final String syncStatus;
  final DateTime? lastBuzzAt;
  final String? buzzEventId;
  final DateTime? buzzEndsAt;
  final DateTime? buzzStoppedAt;

  const LocalOrderRecord({
    required this.id,
    required this.ownerProfileId,
    this.sourceProfileId,
    this.version = 1,
    required this.shopId,
    required this.shopName,
    required this.customerId,
    required this.customerName,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
    this.pickupAt,
    required this.shareStatus,
    required this.chatEnabled,
    this.note = '',
    this.syncStatus = 'synced',
    this.lastBuzzAt,
    this.buzzEventId,
    this.buzzEndsAt,
    this.buzzStoppedAt,
  });

  factory LocalOrderRecord.fromRow(Row row) => LocalOrderRecord(
    id: row['id'] as String,
    ownerProfileId: row['owner_profile_id'] as String,
    sourceProfileId: row['source_profile_id'] as String?,
    version: (row['version'] as int?) ?? 1,
    shopId: row['shop_id'] as String,
    shopName: row['shop_name'] as String,
    customerId: row['customer_id'] as String,
    customerName: row['customer_name'] as String,
    status: row['status'] as String,
    total: (row['total'] as num).toDouble(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    pickupAt: row['pickup_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['pickup_at'] as int),
    shareStatus: (row['share_status'] as int) == 1,
    chatEnabled: (row['chat_enabled'] as int) == 1,
    note: (row['note'] as String?) ?? '',
    syncStatus: (row['sync_status'] as String?) ?? 'synced',
    lastBuzzAt: row['last_buzz_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['last_buzz_at'] as int),
    buzzEventId: row['buzz_event_id'] as String?,
    buzzEndsAt: row['buzz_ends_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['buzz_ends_at'] as int),
    buzzStoppedAt: row['buzz_stopped_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['buzz_stopped_at'] as int),
  );
}

class LocalOrderItemRecord {
  final String id;
  final String orderId;
  final String ownerProfileId;
  final String? productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double total;
  final String syncStatus;
  final int version;

  const LocalOrderItemRecord({
    required this.id,
    required this.orderId,
    required this.ownerProfileId,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.syncStatus = 'pending',
    this.version = 1,
  });

  factory LocalOrderItemRecord.fromRow(Row row) => LocalOrderItemRecord(
    id: row['id'] as String,
    orderId: row['order_id'] as String,
    ownerProfileId: row['owner_profile_id'] as String,
    productId: row['product_id'] as String?,
    productName: row['product_name'] as String,
    quantity: row['quantity'] as int,
    unitPrice: (row['unit_price'] as num).toDouble(),
    total: (row['total'] as num).toDouble(),
    syncStatus: (row['sync_status'] as String?) ?? 'pending',
    version: (row['version'] as int?) ?? 1,
  );
}

class OrderStatusUpdateRecord {
  final String id;
  final String orderId;
  final String ownerProfileId;
  final String status;
  final DateTime updatedAt;
  final DateTime? pickupAt;
  final int version;
  final String syncStatus;

  const OrderStatusUpdateRecord({
    required this.id,
    required this.orderId,
    required this.ownerProfileId,
    required this.status,
    required this.updatedAt,
    this.pickupAt,
    required this.version,
    required this.syncStatus,
  });

  factory OrderStatusUpdateRecord.fromRow(Row row) => OrderStatusUpdateRecord(
    id: row['id'] as String,
    orderId: row['order_id'] as String,
    ownerProfileId: row['owner_profile_id'] as String,
    status: row['status'] as String,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    pickupAt: row['pickup_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['pickup_at'] as int),
    version: (row['version'] as int?) ?? 1,
    syncStatus: (row['sync_status'] as String?) ?? 'synced',
  );
}

class CustomerRecord {
  final int? id;
  final String uuid;
  final String? ownerProfileId;
  final String? sourceProfileId;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String syncStatus;
  final int version;
  final DateTime? deletedAt;

  const CustomerRecord({
    this.id,
    this.uuid = '',
    this.ownerProfileId,
    this.sourceProfileId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.syncStatus = 'pending',
    this.version = 1,
    this.deletedAt,
  });

  factory CustomerRecord.fromRow(Row row) => CustomerRecord(
    id: row['id'] as int,
    uuid: (row['uuid'] as String?) ?? '',
    ownerProfileId: row['owner_profile_id'] as String?,
    sourceProfileId: row['source_profile_id'] as String?,
    name: row['name'] as String,
    phone: (row['phone'] as String?) ?? '',
    email: (row['email'] as String?) ?? '',
    address: (row['address'] as String?) ?? '',
    syncStatus: (row['sync_status'] as String?) ?? 'pending',
    version: (row['version'] as int?) ?? 1,
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int),
  );
}

class InvoiceTemplateRecord {
  final int? id;
  final String organizationName;
  final String? logoPath;
  final String currency;
  final int accentColor;
  final String notes;
  final String terms;
  final String upiPayeeName;
  final String upiId;
  final bool upiEnabled;
  final bool isSelected;

  const InvoiceTemplateRecord({
    this.id,
    required this.organizationName,
    this.logoPath,
    this.currency = 'Rs.',
    this.accentColor = 0xFF2563EB,
    this.notes = '',
    this.terms = '',
    this.upiPayeeName = '',
    this.upiId = '',
    this.upiEnabled = false,
    this.isSelected = false,
  });

  factory InvoiceTemplateRecord.fromRow(Row row) => InvoiceTemplateRecord(
    id: row['id'] as int,
    organizationName: row['organization_name'] as String,
    logoPath: row['logo_path'] as String?,
    currency: row['currency'] as String,
    accentColor: row['accent_color'] as int,
    notes: row['notes'] as String,
    terms: row['terms'] as String,
    upiPayeeName: row['upi_payee_name'] as String,
    upiId: row['upi_id'] as String,
    upiEnabled: (row['upi_enabled'] as int) == 1,
    isSelected: (row['is_selected'] as int) == 1,
  );
}

class CartLine {
  final ProductRecord product;
  final int quantity;

  const CartLine({required this.product, required this.quantity});

  double get total => product.price * quantity;
}

class DashboardStats {
  final int products;
  final int customers;
  final int invoices;
  final double revenue;
  final double profit;
  final double pending;
  final List<RecentInvoice> recentInvoices;

  const DashboardStats({
    required this.products,
    required this.customers,
    required this.invoices,
    required this.revenue,
    required this.profit,
    required this.pending,
    required this.recentInvoices,
  });

  double get profitMargin => revenue <= 0 ? 0 : (profit / revenue) * 100;
}

class RecentInvoice {
  final String number;
  final double total;
  final String status;
  final DateTime createdAt;
  final String pdfPath;
  final String upiId;
  final String upiPayeeName;
  final String paymentNote;
  final String paymentMethod;

  const RecentInvoice({
    required this.number,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.pdfPath,
    required this.upiId,
    required this.upiPayeeName,
    required this.paymentNote,
    required this.paymentMethod,
  });
}

class InvoiceRecoveryData {
  final String number;
  final double total;
  final String upiPayeeName;
  final String upiId;
  final String paymentMethod;
  final InvoiceTemplateRecord template;
  final List<CartLine> lines;

  const InvoiceRecoveryData({
    required this.number,
    required this.total,
    required this.upiPayeeName,
    required this.upiId,
    required this.paymentMethod,
    required this.template,
    required this.lines,
  });
}

class InvoicePageResult {
  final List<RecentInvoice> invoices;
  final int total;

  const InvoicePageResult({required this.invoices, required this.total});

  int get pageCount => total == 0 ? 1 : (total / 10).ceil();
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  /// Test-only constructor around an already-open SQLite database.
  AppDatabase.forTest(Database database) : _db = database;

  /// Creates an isolated in-memory database with the production schema.
  static Future<AppDatabase> openInMemoryForTest() async {
    final database = sqlite3.openInMemory();
    final instance = AppDatabase.forTest(database);
    instance.initializeSchemaForTest();
    return instance;
  }

  void initializeSchemaForTest() {
    _createTables();
    _createNearbyTables();
    _ensureColumn(
      'shop_profiles',
      'mode',
      "TEXT NOT NULL DEFAULT 'counterBilling'",
    );
    _applyDurableSyncSchema();
    applyNearbySyncColumns(db);
    _applyOrderBuzzSchema();
  }

  void closeForTest() {
    _db?.close();
    _db = null;
    _dataDir = null;
    _defaultInvoiceDir = null;
  }

  Database? _db;
  String? _dataDir;
  String? _defaultInvoiceDir;

  Database get db {
    final database = _db;
    if (database == null) throw StateError('Database is not open');
    return database;
  }

  String get dataDir {
    final dir = _dataDir;
    if (dir == null) throw StateError('Database is not open');
    return dir;
  }

  String get defaultInvoiceDir {
    final dir = _defaultInvoiceDir;
    if (dir == null) throw StateError('Database is not open');
    return dir;
  }

  Future<void> open() async {
    if (_db != null) return;
    final supportDir = await getApplicationSupportDirectory();
    final appDir = Directory(p.join(supportDir.path, 'invoice_manager'));
    if (!await appDir.exists()) await appDir.create(recursive: true);
    _dataDir = appDir.path;
    final resolvedDefault = await _resolveDefaultInvoiceDir(appDir.path);
    try {
      final defaultDir = Directory(resolvedDefault);
      if (!await defaultDir.exists()) await defaultDir.create(recursive: true);
      _defaultInvoiceDir = resolvedDefault;
    } catch (_) {
      _defaultInvoiceDir = p.join(appDir.path, 'invoices');
      final fallbackDir = Directory(_defaultInvoiceDir!);
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
    }

    _db = sqlite3.open(p.join(appDir.path, 'invoice_manager.db'));
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _createTables();
    _createNearbyTables();
    _migrateProductSkuColumn();
    _ensureColumn('products', 'profit_percent', 'REAL NOT NULL DEFAULT 0');
    _ensureColumn('products', 'description', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn('products', 'category', "TEXT NOT NULL DEFAULT 'General'");
    _ensureColumn('products', 'image_path', 'TEXT');
    _ensureColumn('products', 'is_available', 'INTEGER NOT NULL DEFAULT 1');
    _ensureColumn('products', 'is_published', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn(
      'shop_profiles',
      'mode',
      "TEXT NOT NULL DEFAULT 'counterBilling'",
    );
    _ensureColumn('invoice_items', 'profit_total', 'REAL NOT NULL DEFAULT 0');
    _ensureColumn(
      'invoice_templates',
      'upi_payee_name',
      "TEXT NOT NULL DEFAULT ''",
    );
    _ensureColumn('invoice_templates', 'upi_id', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn(
      'invoice_templates',
      'upi_enabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn('invoices', 'upi_payee_name', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn('invoices', 'upi_id', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn('invoices', 'payment_note', "TEXT NOT NULL DEFAULT ''");
    _ensureColumn('invoices', 'payment_method', "TEXT NOT NULL DEFAULT 'upi'");
    _applyDurableSyncSchema();
    applyNearbySyncColumns(db);
    _applyOrderBuzzSchema();
    await _migrateLegacyDefaultInvoiceDir(appDir.path);
    await _migrateLegacyJsonOnce();
    _ensureLegacyShopkeeperProfile();
    cleanupExpiredOrders();
  }

  Future<void> _migrateLegacyDefaultInvoiceDir(String appDataDir) async {
    final configured = setting('invoice_save_dir');
    if (configured != null && configured.trim().isNotEmpty) return;
    final legacyPath = p.join(appDataDir, 'invoices');
    if (_samePath(legacyPath, defaultInvoiceDir)) return;
    await _movePdfFiles(legacyPath, defaultInvoiceDir);
  }

  Future<String> _resolveDefaultInvoiceDir(String appDataDir) async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final downloadsDir = await _mobileDownloadsDirectory();
        if (downloadsDir != null && await downloadsDir.exists()) {
          return p.join(downloadsDir.path, 'LIMS');
        }
      } catch (_) {
        // Some platforms/providers do not expose a downloads directory.
      }
    }
    return p.join(appDataDir, 'invoices');
  }

  Future<Directory?> _mobileDownloadsDirectory() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final path = await const MethodChannel(
        'lims/storage',
      ).invokeMethod<String>('publicDownloadsPath');
      return path == null ? null : Directory(path);
    }
    return getDownloadsDirectory();
  }

  void _createTables() {
    db.execute('''
CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  price REAL NOT NULL,
  profit_percent REAL NOT NULL DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS invoice_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  organization_name TEXT NOT NULL,
  logo_path TEXT,
  currency TEXT NOT NULL DEFAULT 'Rs.',
  accent_color INTEGER NOT NULL DEFAULT 4280648683,
  notes TEXT NOT NULL DEFAULT '',
  terms TEXT NOT NULL DEFAULT '',
  upi_payee_name TEXT NOT NULL DEFAULT '',
  upi_id TEXT NOT NULL DEFAULT '',
  upi_enabled INTEGER NOT NULL DEFAULT 0,
  is_selected INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_number TEXT NOT NULL UNIQUE,
  customer_id INTEGER,
  template_id INTEGER,
  subtotal REAL NOT NULL,
  discount REAL NOT NULL DEFAULT 0,
  tax REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'paid',
  pdf_path TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  due_at INTEGER,
  upi_payee_name TEXT NOT NULL DEFAULT '',
  upi_id TEXT NOT NULL DEFAULT '',
  payment_note TEXT NOT NULL DEFAULT '',
  payment_method TEXT NOT NULL DEFAULT 'upi',
  FOREIGN KEY(customer_id) REFERENCES customers(id),
  FOREIGN KEY(template_id) REFERENCES invoice_templates(id)
);
CREATE TABLE IF NOT EXISTS invoice_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id INTEGER NOT NULL,
  product_id INTEGER,
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  total REAL NOT NULL,
  profit_total REAL NOT NULL DEFAULT 0,
  FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
  FOREIGN KEY(product_id) REFERENCES products(id)
);
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  invoice_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  method TEXT NOT NULL DEFAULT 'cash',
  paid_at INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_invoices_created ON invoices(created_at DESC);
''');
  }

  void _applyDurableSyncSchema() {
    final version =
        (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    db.execute('BEGIN');
    try {
      if (version < 2) {
        db.execute('''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_inbox (
  event_id TEXT PRIMARY KEY,
  peer_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  entity_version INTEGER NOT NULL,
  payload_hash TEXT NOT NULL,
  applied_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sync_peer_cursors (
  local_profile_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  stream TEXT NOT NULL,
  last_updated_at INTEGER NOT NULL DEFAULT 0,
  last_version INTEGER NOT NULL DEFAULT 0,
  last_record_id TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(local_profile_id, peer_id, stream)
);
CREATE TABLE IF NOT EXISTS status_updates (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  owner_profile_id TEXT NOT NULL,
  shop_id TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  status TEXT NOT NULL,
  pickup_at INTEGER,
  share_status INTEGER NOT NULL DEFAULT 1,
  chat_enabled INTEGER NOT NULL DEFAULT 1,
  sync_status TEXT NOT NULL DEFAULT 'pending'
    CHECK(sync_status IN ('pending', 'synced', 'failed')),
  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  deleted_at INTEGER,
  UNIQUE(owner_profile_id, order_id, version)
);
CREATE INDEX IF NOT EXISTS idx_status_updates_order
  ON status_updates(owner_profile_id, order_id, version);
CREATE INDEX IF NOT EXISTS idx_sync_inbox_entity
  ON sync_inbox(peer_id, entity_type, entity_id, entity_version);
''');
        _ensureSyncColumns('products');
        _ensureSyncColumns('customers');
        _ensureSyncColumns('invoices');
        _ensureSyncColumns('invoice_items');
        _ensureSyncColumns('payments');
        _ensureSyncColumns('local_orders');
        _ensureSyncColumns('local_order_items');
        _ensureColumn('invoices', 'updated_at', 'INTEGER NOT NULL DEFAULT 0');
        _ensureColumn('sync_queue', 'entity_type', "TEXT NOT NULL DEFAULT ''");
        _ensureColumn('sync_queue', 'entity_id', "TEXT NOT NULL DEFAULT ''");
        _ensureColumn(
          'sync_queue',
          'entity_version',
          'INTEGER NOT NULL DEFAULT 0',
        );
        _ensureColumn(
          'sync_queue',
          'state',
          "TEXT NOT NULL DEFAULT 'queued' CHECK(state IN ('queued', 'sending', 'failed'))",
        );
        _ensureColumn('sync_queue', 'updated_at', 'INTEGER NOT NULL DEFAULT 0');
        _ensureColumn(
          'sync_queue',
          'next_attempt_at',
          'INTEGER NOT NULL DEFAULT 0',
        );
        _ensureColumn('sync_queue', 'acked_at', 'INTEGER');
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_outbox ON sync_queue(owner_profile_id, peer_id, state, next_attempt_at)',
        );
        _backfillSyncIdentity('products');
        _backfillSyncIdentity('customers');
        _backfillSyncIdentity('invoices');
        _backfillSyncIdentity('invoice_items');
        _backfillSyncIdentity('payments');
        _backfillSyncIdentity('local_orders');
        _backfillSyncIdentity('local_order_items');
        for (final table in [
          'products',
          'customers',
          'invoices',
          'invoice_items',
          'payments',
          'local_orders',
          'local_order_items',
        ]) {
          db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_uuid ON $table(uuid)',
          );
        }
        db.execute(
          'UPDATE invoices SET updated_at = created_at WHERE updated_at = 0',
        );
        for (final table in [
          'products',
          'customers',
          'invoices',
          'invoice_items',
          'payments',
          'local_orders',
          'local_order_items',
        ]) {
          db.execute(
            "UPDATE $table SET sync_status = 'synced' WHERE sync_status = 'pending'",
          );
        }
        db.execute(
          'INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES(2, ?)',
          [DateTime.now().millisecondsSinceEpoch],
        );
        db.execute('PRAGMA user_version = 2');
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _applyOrderBuzzSchema() {
    final version =
        (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    if (version >= 5) return;
    db.execute('BEGIN');
    try {
      _ensureColumn('local_orders', 'last_buzz_at', 'INTEGER');
      _ensureColumn('local_orders', 'buzz_event_id', 'TEXT');
      _ensureColumn('local_orders', 'buzz_ends_at', 'INTEGER');
      _ensureColumn('local_orders', 'buzz_stopped_at', 'INTEGER');
      db.execute(
        'INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES(5, ?)',
        [DateTime.now().millisecondsSinceEpoch],
      );
      db.execute('PRAGMA user_version = 5');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _ensureSyncColumns(String table) {
    _ensureColumn(table, 'uuid', 'TEXT');
    _ensureColumn(table, 'owner_profile_id', 'TEXT');
    _ensureColumn(table, 'source_profile_id', 'TEXT');
    _ensureColumn(
      table,
      'sync_status',
      "TEXT NOT NULL DEFAULT 'pending' CHECK(sync_status IN ('pending', 'synced', 'failed'))",
    );
    _ensureColumn(table, 'version', 'INTEGER NOT NULL DEFAULT 1');
    _ensureColumn(table, 'deleted_at', 'INTEGER');
  }

  void _backfillSyncIdentity(String table) {
    db.execute('''
UPDATE $table SET uuid = substr(lower(hex(randomblob(4))), 1, 8) || '-' ||
  substr(lower(hex(randomblob(2))), 1, 4) || '-4' ||
  substr(lower(hex(randomblob(2))), 2, 3) || '-' ||
  substr('89ab', abs(random()) % 4 + 1, 1) ||
  substr(lower(hex(randomblob(2))), 2, 3) || '-' ||
  lower(hex(randomblob(6)))
WHERE uuid IS NULL
''');
  }

  void _createNearbyTables() {
    db.execute('''
CREATE TABLE IF NOT EXISTS local_profiles (
  id TEXT PRIMARY KEY,
  role TEXT NOT NULL CHECK(role IN ('customer', 'shopkeeper')),
  display_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS shop_profiles (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'General',
  contact TEXT NOT NULL DEFAULT '',
  visible INTEGER NOT NULL DEFAULT 0,
  ordering_enabled INTEGER NOT NULL DEFAULT 1,
  status_enabled INTEGER NOT NULL DEFAULT 1,
  chat_enabled INTEGER NOT NULL DEFAULT 1,
  mode TEXT NOT NULL DEFAULT 'counterBilling',
  catalog_revision INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(profile_id) REFERENCES local_profiles(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS catalog_cache (
  owner_profile_id TEXT NOT NULL,
  shop_id TEXT NOT NULL,
  shop_name TEXT NOT NULL,
  payload TEXT NOT NULL,
  catalog_revision INTEGER NOT NULL,
  synced_at INTEGER NOT NULL,
  PRIMARY KEY(owner_profile_id, shop_id)
);
CREATE TABLE IF NOT EXISTS local_orders (
  id TEXT NOT NULL,
  owner_profile_id TEXT NOT NULL,
  shop_id TEXT NOT NULL,
  shop_name TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  customer_name TEXT NOT NULL,
  status TEXT NOT NULL,
  total REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  pickup_at INTEGER,
  share_status INTEGER NOT NULL DEFAULT 1,
  chat_enabled INTEGER NOT NULL DEFAULT 1,
  note TEXT NOT NULL DEFAULT '',
  sync_status TEXT NOT NULL DEFAULT 'synced',
  expires_at INTEGER,
  last_buzz_at INTEGER,
  buzz_event_id TEXT,
  buzz_ends_at INTEGER,
  buzz_stopped_at INTEGER,
  PRIMARY KEY(id, owner_profile_id)
);
CREATE TABLE IF NOT EXISTS local_order_items (
  id TEXT NOT NULL,
  order_id TEXT NOT NULL,
  owner_profile_id TEXT NOT NULL,
  product_id TEXT,
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  total REAL NOT NULL,
  PRIMARY KEY(id, owner_profile_id)
);
CREATE TABLE IF NOT EXISTS order_messages (
  id TEXT NOT NULL,
  order_id TEXT NOT NULL,
  owner_profile_id TEXT NOT NULL,
  sender_role TEXT NOT NULL,
  body TEXT NOT NULL,
  sent_at INTEGER NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'waiting_to_send',
  expires_at INTEGER,
  PRIMARY KEY(id, owner_profile_id)
);
CREATE TABLE IF NOT EXISTS sync_queue (
  id TEXT PRIMARY KEY,
  owner_profile_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS transfer_sessions (
  id TEXT PRIMARY KEY,
  direction TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  temporary_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_local_orders_owner_updated
  ON local_orders(owner_profile_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_messages_order
  ON order_messages(owner_profile_id, order_id, sent_at);
''');
  }

  void _ensureLegacyShopkeeperProfile() {
    if (count('local_profiles') > 0) return;
    final hasBusinessData =
        count('products') > 0 ||
        count('invoices') > 0 ||
        count('invoice_templates') > 0;
    if (!hasBusinessData) return;
    createProfile(AppRole.shopkeeper, 'Shopkeeper');
  }

  void _migrateProductSkuColumn() {
    final columns = db.select('PRAGMA table_info(products)');
    final hasSku = columns.any((column) => column['name'] == 'sku');
    if (hasSku) {
      db.execute('ALTER TABLE products DROP COLUMN sku');
    }
  }

  void _ensureColumn(String table, String column, String definition) {
    final columns = db.select('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _migrateLegacyJsonOnce() async {
    if (setting('legacy_json_migrated') == '1') return;
    final prefs = await SharedPreferences.getInstance();
    final savedDir = prefs.getString('save_location');
    if (savedDir != null && savedDir.isNotEmpty) {
      await _migrateProducts(File(p.join(savedDir, 'products_data.json')));
      await _migrateTemplates(File(p.join(savedDir, 'invoice_templates.json')));
    }
    setSetting('legacy_json_migrated', '1');
  }

  Future<void> _migrateProducts(File file) async {
    if (!await file.exists() || count('products') > 0) return;
    final items = jsonDecode(await file.readAsString()) as List<dynamic>;
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      saveProduct(
        ProductRecord(
          name: '${map['name'] ?? ''}'.trim(),
          price: (map['price'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
  }

  Future<void> _migrateTemplates(File file) async {
    if (!await file.exists() || count('invoice_templates') > 0) return;
    final items = jsonDecode(await file.readAsString()) as List<dynamic>;
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      saveTemplate(
        InvoiceTemplateRecord(
          organizationName: '${map['organizationName'] ?? ''}'.trim(),
          logoPath: '${map['logoPath'] ?? ''}'.trim().isEmpty
              ? null
              : '${map['logoPath']}',
          currency: '${map['currency'] ?? 'Rs.'}'.trim().isEmpty
              ? 'Rs.'
              : '${map['currency']}',
          upiPayeeName: '${map['upiPayeeName'] ?? ''}'.trim(),
          upiId: '${map['upiId'] ?? ''}'.trim(),
          upiEnabled: map['upiEnabled'] == true,
          isSelected: map['isSelected'] == true,
        ),
      );
    }
  }

  int count(String table) =>
      db.select('SELECT COUNT(*) c FROM $table').first['c'] as int;

  String? setting(String key) {
    final rows = db.select('SELECT value FROM app_settings WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  String invoiceSaveDir() {
    final custom = setting('invoice_save_dir');
    return custom == null || custom.trim().isEmpty ? defaultInvoiceDir : custom;
  }

  Future<Directory> ensureInvoiceSaveDir() async {
    final dir = Directory(invoiceSaveDir());
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void setInvoiceSaveDir(String path) => setSetting('invoice_save_dir', path);

  void resetInvoiceSaveDir() => db.execute(
    'DELETE FROM app_settings WHERE key = ?',
    ['invoice_save_dir'],
  );

  Future<int> updateInvoiceSaveDir(String? path) async {
    final oldPath = invoiceSaveDir();
    final newPath = path == null || path.trim().isEmpty
        ? defaultInvoiceDir
        : path.trim();
    if (_samePath(oldPath, newPath)) return 0;

    final newDir = Directory(newPath);
    if (!await newDir.exists()) await newDir.create(recursive: true);
    final moved = await _movePdfFiles(oldPath, newPath);

    if (path == null || path.trim().isEmpty) {
      resetInvoiceSaveDir();
    } else {
      setInvoiceSaveDir(newPath);
    }
    return moved;
  }

  Future<int> _movePdfFiles(String oldDirPath, String newDirPath) async {
    final oldDir = Directory(oldDirPath);
    if (!await oldDir.exists()) return 0;

    var moved = 0;
    await for (final entity in oldDir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.pdf') continue;
      final targetPath = await _availablePdfPath(
        p.join(newDirPath, p.basename(entity.path)),
      );
      if (_samePath(entity.path, targetPath)) continue;
      await _moveFile(entity, targetPath);
      db.execute('UPDATE invoices SET pdf_path = ? WHERE pdf_path = ?', [
        targetPath,
        entity.path,
      ]);
      moved++;
    }
    return moved;
  }

  Future<String> _availablePdfPath(String path) async {
    if (!await File(path).exists()) return path;
    final dir = p.dirname(path);
    final name = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    var index = 2;
    while (true) {
      final candidate = p.join(dir, '$name-$index$ext');
      if (!await File(candidate).exists()) return candidate;
      index++;
    }
  }

  Future<void> _moveFile(File source, String targetPath) async {
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      await source.copy(targetPath);
      await source.delete();
    }
  }

  bool _samePath(String a, String b) =>
      p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase();

  void setSetting(String key, String value) => db.execute(
    'INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)',
    [key, value],
  );

  List<ProductRecord> products({String query = ''}) {
    final term = '%${query.trim()}%';
    final rows = query.trim().isEmpty
        ? db.select(
            'SELECT * FROM products WHERE deleted_at IS NULL ORDER BY updated_at DESC',
          )
        : db.select(
            'SELECT * FROM products WHERE deleted_at IS NULL AND name LIKE ? ORDER BY name',
            [term],
          );
    return rows.map(ProductRecord.fromRow).toList();
  }

  bool productNameExists(String name, {int? exceptId}) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final rows = exceptId == null
        ? db.select(
            'SELECT id FROM products WHERE deleted_at IS NULL AND lower(name) = ? LIMIT 1',
            [normalized],
          )
        : db.select(
            'SELECT id FROM products WHERE deleted_at IS NULL AND lower(name) = ? AND id != ? LIMIT 1',
            [normalized, exceptId],
          );
    return rows.isNotEmpty;
  }

  void saveProduct(ProductRecord product) {
    if (productNameExists(product.name, exceptId: product.id)) {
      throw ArgumentError('A product with this name already exists.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = activeProfile();
    final ownerId = product.ownerProfileId ?? profile?.id;
    final sourceId = product.sourceProfileId ?? ownerId;
    if (product.id == null) {
      db.execute(
        'INSERT INTO products(uuid, owner_profile_id, source_profile_id, name, price, profit_percent, stock_quantity, description, category, image_path, is_available, is_published, sync_status, version, deleted_at, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          product.uuid.isEmpty ? const Uuid().v4() : product.uuid,
          ownerId,
          sourceId,
          product.name,
          product.price,
          product.profitPercent,
          product.stockQuantity,
          product.description,
          product.category,
          product.imagePath,
          product.isAvailable ? 1 : 0,
          product.isPublished ? 1 : 0,
          'pending',
          1,
          null,
          now,
          now,
        ],
      );
    } else {
      final current = db.select(
        'SELECT uuid, version FROM products WHERE id = ? LIMIT 1',
        [product.id],
      );
      final uuid = product.uuid.isNotEmpty
          ? product.uuid
          : (current.isEmpty
                ? const Uuid().v4()
                : current.first['uuid'] as String);
      final version = current.isEmpty
          ? 1
          : ((current.first['version'] as int?) ?? 0) + 1;
      db.execute(
        'UPDATE products SET uuid = ?, owner_profile_id = ?, source_profile_id = ?, name = ?, price = ?, profit_percent = ?, stock_quantity = ?, description = ?, category = ?, image_path = ?, is_available = ?, is_published = ?, sync_status = ?, version = ?, deleted_at = ?, updated_at = ? WHERE id = ?',
        [
          uuid,
          ownerId,
          sourceId,
          product.name,
          product.price,
          product.profitPercent,
          product.stockQuantity,
          product.description,
          product.category,
          product.imagePath,
          product.isAvailable ? 1 : 0,
          product.isPublished ? 1 : 0,
          'pending',
          version,
          null,
          now,
          product.id,
        ],
      );
    }
    if (profile?.role == AppRole.shopkeeper) {
      incrementCatalogRevision(profile!.id);
    }
  }

  int incrementCatalogRevision(String profileId) {
    db.execute(
      'UPDATE shop_profiles SET catalog_revision = catalog_revision + 1 WHERE profile_id = ?',
      [profileId],
    );
    return shopForProfile(profileId)?.catalogRevision ?? 1;
  }

  List<ProductRecord> publishedProducts() => db
      .select(
        'SELECT * FROM products WHERE deleted_at IS NULL AND is_published = 1 ORDER BY category, name',
      )
      .map(ProductRecord.fromRow)
      .toList();

  List<CustomerRecord> customers({String query = ''}) {
    final term = '%${query.trim()}%';
    final rows = query.trim().isEmpty
        ? db.select(
            'SELECT * FROM customers WHERE deleted_at IS NULL ORDER BY updated_at DESC',
          )
        : db.select(
            'SELECT * FROM customers WHERE deleted_at IS NULL AND name LIKE ? ORDER BY name',
            [term],
          );
    return rows.map(CustomerRecord.fromRow).toList();
  }

  void saveCustomer(CustomerRecord customer) {
    if (customer.name.trim().isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = activeProfile();
    final ownerId = customer.ownerProfileId ?? profile?.id;
    final sourceId = customer.sourceProfileId ?? ownerId;
    if (customer.id == null) {
      db.execute(
        'INSERT INTO customers(uuid, owner_profile_id, source_profile_id, name, phone, email, address, created_at, updated_at, sync_status, version, deleted_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          customer.uuid.isEmpty ? const Uuid().v4() : customer.uuid,
          ownerId,
          sourceId,
          customer.name.trim(),
          customer.phone,
          customer.email,
          customer.address,
          now,
          now,
          'pending',
          1,
          null,
        ],
      );
    } else {
      final current = db.select(
        'SELECT uuid, version FROM customers WHERE id = ? LIMIT 1',
        [customer.id],
      );
      final uuid = customer.uuid.isNotEmpty
          ? customer.uuid
          : (current.isEmpty
                ? const Uuid().v4()
                : current.first['uuid'] as String);
      final version = current.isEmpty
          ? 1
          : ((current.first['version'] as int?) ?? 0) + 1;
      db.execute(
        'UPDATE customers SET uuid = ?, owner_profile_id = ?, source_profile_id = ?, name = ?, phone = ?, email = ?, address = ?, updated_at = ?, sync_status = ?, version = ?, deleted_at = ? WHERE id = ?',
        [
          uuid,
          ownerId,
          sourceId,
          customer.name.trim(),
          customer.phone,
          customer.email,
          customer.address,
          now,
          'pending',
          version,
          null,
          customer.id,
        ],
      );
    }
  }

  void deleteCustomer(int id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''UPDATE customers SET deleted_at = ?, sync_status = ?, version = version + 1,
         updated_at = ? WHERE id = ? AND deleted_at IS NULL''',
      [now, 'pending', now, id],
    );
  }

  List<LocalProfile> profiles() => db
      .select('SELECT * FROM local_profiles ORDER BY last_used_at DESC')
      .map(LocalProfile.fromRow)
      .toList();

  LocalProfile? activeProfile() {
    final id = setting('active_profile_id');
    if (id == null) return null;
    final rows = db.select(
      'SELECT * FROM local_profiles WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : LocalProfile.fromRow(rows.first);
  }

  LocalProfile createProfile(
    AppRole role,
    String displayName, {
    ShopkeeperMode mode = ShopkeeperMode.counterBilling,
  }) {
    final uuid = Uuid();
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = LocalProfile(
      id: uuid.v4(),
      role: role,
      displayName: displayName.trim(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
    db.execute(
      'INSERT INTO local_profiles(id, role, display_name, created_at, last_used_at) VALUES(?, ?, ?, ?, ?)',
      [profile.id, role.name, profile.displayName, now, now],
    );
    if (role == AppRole.shopkeeper) {
      db.execute(
        'INSERT INTO shop_profiles(id, profile_id, name, mode) VALUES(?, ?, ?, ?)',
        [uuid.v4(), profile.id, profile.displayName, mode.name],
      );
    }
    selectProfile(profile.id);
    return profile;
  }

  void selectProfile(String id) {
    setSetting('active_profile_id', id);
    db.execute('UPDATE local_profiles SET last_used_at = ? WHERE id = ?', [
      DateTime.now().millisecondsSinceEpoch,
      id,
    ]);
  }

  LocalProfile? updateProfileName(String profileId, String displayName) {
    final name = displayName.trim();
    if (name.isEmpty) return null;
    db.execute('UPDATE local_profiles SET display_name = ? WHERE id = ?', [
      name,
      profileId,
    ]);
    db.execute('UPDATE shop_profiles SET name = ? WHERE profile_id = ?', [
      name,
      profileId,
    ]);
    final rows = db.select(
      'SELECT * FROM local_profiles WHERE id = ? LIMIT 1',
      [profileId],
    );
    return rows.isEmpty ? null : LocalProfile.fromRow(rows.first);
  }

  void logout() => db.execute('DELETE FROM app_settings WHERE key = ?', [
    'active_profile_id',
  ]);

  ShopProfileRecord? shopForProfile(String profileId) {
    final rows = db.select(
      'SELECT * FROM shop_profiles WHERE profile_id = ? LIMIT 1',
      [profileId],
    );
    return rows.isEmpty ? null : ShopProfileRecord.fromRow(rows.first);
  }

  void saveShopProfile(ShopProfileRecord shop) => db.execute(
    '''UPDATE shop_profiles SET name = ?, category = ?, contact = ?, visible = ?,
       ordering_enabled = ?, status_enabled = ?, chat_enabled = ?, mode = ?, catalog_revision = ?
       WHERE id = ?''',
    [
      shop.name,
      shop.category,
      shop.contact,
      shop.visible ? 1 : 0,
      shop.orderingEnabled ? 1 : 0,
      shop.statusEnabled ? 1 : 0,
      shop.chatEnabled ? 1 : 0,
      shop.mode.name,
      shop.catalogRevision,
      shop.id,
    ],
  );

  List<LocalOrderRecord> ordersForProfile(String profileId) => db
      .select(
        'SELECT * FROM local_orders WHERE owner_profile_id = ? ORDER BY updated_at DESC',
        [profileId],
      )
      .map(LocalOrderRecord.fromRow)
      .toList();

  List<LocalOrderRecord> unsentOrdersForProfile(String profileId) => db
      .select(
        '''SELECT * FROM local_orders
           WHERE owner_profile_id = ? AND status = 'waiting_to_send'
           ORDER BY created_at''',
        [profileId],
      )
      .map(LocalOrderRecord.fromRow)
      .toList();

  List<LocalOrderItemRecord> orderItems(String profileId, String orderId) => db
      .select(
        'SELECT * FROM local_order_items WHERE owner_profile_id = ? AND order_id = ? ORDER BY rowid',
        [profileId, orderId],
      )
      .map(LocalOrderItemRecord.fromRow)
      .toList();

  List<OrderStatusUpdateRecord> orderStatusUpdates(
    String profileId,
    String orderId,
  ) => db
      .select(
        '''SELECT * FROM status_updates
           WHERE owner_profile_id = ? AND order_id = ? AND deleted_at IS NULL
           ORDER BY version, updated_at, id''',
        [profileId, orderId],
      )
      .map(OrderStatusUpdateRecord.fromRow)
      .toList();

  bool orderExists(String profileId, String orderId) => db.select(
    'SELECT 1 FROM local_orders WHERE owner_profile_id = ? AND id = ? LIMIT 1',
    [profileId, orderId],
  ).isNotEmpty;

  LocalOrderRecord? orderForProfile(String profileId, String orderId) {
    final rows = db.select(
      'SELECT * FROM local_orders WHERE owner_profile_id = ? AND id = ? LIMIT 1',
      [profileId, orderId],
    );
    return rows.isEmpty ? null : LocalOrderRecord.fromRow(rows.first);
  }

  bool saveLocalOrder(
    LocalOrderRecord order,
    List<LocalOrderItemRecord> items,
  ) {
    db.execute('BEGIN');
    try {
      final applied = _saveLocalOrderTx(order, items);
      db.execute('COMMIT');
      return applied;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  bool _saveLocalOrderTx(
    LocalOrderRecord order,
    List<LocalOrderItemRecord> items,
  ) {
    final existing = orderForProfile(order.ownerProfileId, order.id);
    if (existing != null && order.version < existing.version) {
      return false;
    }
    final expiresAt =
        order.status == 'completed' ||
            order.status == 'rejected' ||
            order.status == 'cancelled'
        ? order.updatedAt.add(const Duration(days: 365)).millisecondsSinceEpoch
        : null;
    db.execute(
      '''INSERT INTO local_orders(
          id, owner_profile_id, source_profile_id, version, shop_id, shop_name,
          customer_id, customer_name, status, total, created_at, updated_at,
          pickup_at, share_status, chat_enabled, note, sync_status, expires_at,
          last_buzz_at, buzz_event_id, buzz_ends_at, buzz_stopped_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id, owner_profile_id) DO UPDATE SET
          source_profile_id = excluded.source_profile_id,
          version = excluded.version,
          shop_id = excluded.shop_id,
          shop_name = excluded.shop_name,
          customer_id = excluded.customer_id,
          customer_name = excluded.customer_name,
          status = excluded.status,
          total = excluded.total,
          updated_at = excluded.updated_at,
          pickup_at = excluded.pickup_at,
          share_status = excluded.share_status,
          chat_enabled = excluded.chat_enabled,
          note = excluded.note,
          sync_status = excluded.sync_status,
          expires_at = excluded.expires_at,
          last_buzz_at = COALESCE(local_orders.last_buzz_at, excluded.last_buzz_at),
          buzz_event_id = COALESCE(local_orders.buzz_event_id, excluded.buzz_event_id),
          buzz_ends_at = COALESCE(local_orders.buzz_ends_at, excluded.buzz_ends_at),
          buzz_stopped_at = COALESCE(local_orders.buzz_stopped_at, excluded.buzz_stopped_at)
        WHERE excluded.version >= local_orders.version''',
      [
        order.id,
        order.ownerProfileId,
        order.sourceProfileId ?? order.ownerProfileId,
        order.version,
        order.shopId,
        order.shopName,
        order.customerId,
        order.customerName,
        order.status,
        order.total,
        order.createdAt.millisecondsSinceEpoch,
        order.updatedAt.millisecondsSinceEpoch,
        order.pickupAt?.millisecondsSinceEpoch,
        order.shareStatus ? 1 : 0,
        order.chatEnabled ? 1 : 0,
        order.note,
        order.syncStatus,
        expiresAt,
        order.lastBuzzAt?.millisecondsSinceEpoch,
        order.buzzEventId,
        order.buzzEndsAt?.millisecondsSinceEpoch,
        order.buzzStoppedAt?.millisecondsSinceEpoch,
      ],
    );
    if (db.updatedRows == 0 && existing != null) {
      return false;
    }
    db.execute(
      'DELETE FROM local_order_items WHERE owner_profile_id = ? AND order_id = ?',
      [order.ownerProfileId, order.id],
    );
    for (final item in items) {
      db.execute(
        '''INSERT INTO local_order_items(
            id, order_id, owner_profile_id, product_id, product_name,
            quantity, unit_price, total, sync_status, version
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          item.id,
          item.orderId,
          item.ownerProfileId,
          item.productId,
          item.productName,
          item.quantity,
          item.unitPrice,
          item.total,
          item.syncStatus,
          item.version,
        ],
      );
    }
    return true;
  }

  bool reserveOrderBuzz({
    required String profileId,
    required String orderId,
    required String eventId,
    required DateTime now,
    Duration sessionDuration = const Duration(minutes: 5),
    Duration cooldown = const Duration(seconds: 30),
  }) {
    final nowMs = now.millisecondsSinceEpoch;
    final endsAt = now.add(sessionDuration).millisecondsSinceEpoch;
    db.execute(
      '''UPDATE local_orders
         SET last_buzz_at = ?, buzz_event_id = ?, buzz_ends_at = ?, buzz_stopped_at = NULL
         WHERE owner_profile_id = ? AND id = ?
           AND status IN ('accepted', 'preparing', 'ready_for_pickup')
           AND (buzz_ends_at IS NULL OR
                COALESCE(buzz_stopped_at, buzz_ends_at) + ? <= ?)''',
      [
        nowMs,
        eventId,
        endsAt,
        profileId,
        orderId,
        cooldown.inMilliseconds,
        nowMs,
      ],
    );
    return db.updatedRows == 1;
  }

  void releaseOrderBuzz({
    required String profileId,
    required String orderId,
    required String eventId,
  }) => db.execute(
    '''UPDATE local_orders
       SET last_buzz_at = NULL, buzz_event_id = NULL,
           buzz_ends_at = NULL, buzz_stopped_at = NULL
       WHERE owner_profile_id = ? AND id = ? AND buzz_event_id = ?''',
    [profileId, orderId, eventId],
  );

  bool stopOrderBuzz({
    required String profileId,
    required String orderId,
    required String eventId,
    required DateTime stoppedAt,
  }) {
    db.execute(
      '''UPDATE local_orders SET buzz_stopped_at = ?
         WHERE owner_profile_id = ? AND id = ? AND buzz_event_id = ?
           AND buzz_stopped_at IS NULL AND buzz_ends_at > ?''',
      [
        stoppedAt.millisecondsSinceEpoch,
        profileId,
        orderId,
        eventId,
        stoppedAt.millisecondsSinceEpoch,
      ],
    );
    return db.updatedRows == 1;
  }

  bool claimIncomingBuzz({
    required String eventId,
    required String peerId,
    required String orderId,
    required String payloadHash,
  }) {
    db.execute(
      '''INSERT OR IGNORE INTO sync_inbox(
        event_id, peer_id, entity_type, entity_id, entity_version,
        payload_hash, applied_at
      ) VALUES(?, ?, 'customer_buzz', ?, 1, ?, ?)''',
      [
        eventId,
        peerId,
        orderId,
        payloadHash,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return db.updatedRows == 1;
  }

  bool recordRemoteOrderCreate({
    required String ownerProfileId,
    required String peerId,
    required String eventId,
    required LocalOrderRecord order,
    required List<LocalOrderItemRecord> items,
    required String payloadHash,
  }) {
    db.execute('BEGIN');
    try {
      final seen = db.select(
        'SELECT 1 FROM sync_inbox WHERE event_id = ? LIMIT 1',
        [eventId],
      ).isNotEmpty;
      if (seen || orderExists(ownerProfileId, order.id)) {
        db.execute(
          '''INSERT OR IGNORE INTO sync_inbox(
            event_id, peer_id, entity_type, entity_id, entity_version,
            payload_hash, applied_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?)''',
          [
            eventId,
            peerId,
            'order_create',
            order.id,
            order.version,
            payloadHash,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        db.execute('COMMIT');
        return false;
      }
      db.execute(
        '''INSERT INTO sync_inbox(
          event_id, peer_id, entity_type, entity_id, entity_version,
          payload_hash, applied_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?)''',
        [
          eventId,
          peerId,
          'order_create',
          order.id,
          order.version,
          payloadHash,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      final applied = _saveLocalOrderTx(order, items);
      db.execute('COMMIT');
      return applied;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  bool applyRemoteStatusEvent({
    required String ownerProfileId,
    required String peerId,
    required String eventId,
    required String orderId,
    required String status,
    required int version,
    DateTime? pickupAt,
    required bool shareStatus,
    required bool chatEnabled,
    required int updatedAt,
    required String payloadHash,
  }) {
    db.execute('BEGIN');
    try {
      final seen = db.select(
        'SELECT 1 FROM sync_inbox WHERE event_id = ? LIMIT 1',
        [eventId],
      ).isNotEmpty;
      if (seen) {
        db.execute('COMMIT');
        return false;
      }
      final existing = orderForProfile(ownerProfileId, orderId);
      if (existing == null || version <= existing.version) {
        db.execute(
          '''INSERT OR IGNORE INTO sync_inbox(
            event_id, peer_id, entity_type, entity_id, entity_version,
            payload_hash, applied_at
          ) VALUES(?, ?, ?, ?, ?, ?, ?)''',
          [
            eventId,
            peerId,
            'order_status',
            orderId,
            version,
            payloadHash,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        db.execute('COMMIT');
        return false;
      }
      final terminal =
          status == 'completed' ||
          status == 'rejected' ||
          status == 'cancelled';
      db.execute(
        '''UPDATE local_orders SET status = ?, pickup_at = ?, share_status = ?,
           chat_enabled = ?, sync_status = ?, version = ?, updated_at = ?,
           expires_at = ? WHERE owner_profile_id = ? AND id = ?''',
        [
          status,
          pickupAt?.millisecondsSinceEpoch,
          shareStatus ? 1 : 0,
          chatEnabled ? 1 : 0,
          'synced',
          version,
          updatedAt,
          terminal
              ? DateTime.fromMillisecondsSinceEpoch(
                  updatedAt,
                ).add(const Duration(days: 365)).millisecondsSinceEpoch
              : null,
          ownerProfileId,
          orderId,
        ],
      );
      db.execute(
        '''INSERT INTO status_updates(
          id, order_id, owner_profile_id, shop_id, customer_id, status,
          pickup_at, share_status, chat_enabled, sync_status, updated_at,
          version, deleted_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          eventId,
          orderId,
          ownerProfileId,
          existing.shopId,
          existing.customerId,
          status,
          pickupAt?.millisecondsSinceEpoch,
          shareStatus ? 1 : 0,
          chatEnabled ? 1 : 0,
          'synced',
          updatedAt,
          version,
          null,
        ],
      );
      db.execute(
        '''INSERT INTO sync_inbox(
          event_id, peer_id, entity_type, entity_id, entity_version,
          payload_hash, applied_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?)''',
        [
          eventId,
          peerId,
          'order_status',
          orderId,
          version,
          payloadHash,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      db.execute('COMMIT');
      return true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updateLocalOrderSyncState(
    String profileId,
    String orderId,
    String syncStatus, {
    String? status,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (status == null) {
      db.execute(
        'UPDATE local_orders SET sync_status = ?, updated_at = ? WHERE owner_profile_id = ? AND id = ?',
        [syncStatus, now, profileId, orderId],
      );
    } else {
      db.execute(
        'UPDATE local_orders SET sync_status = ?, status = ?, updated_at = ? WHERE owner_profile_id = ? AND id = ?',
        [syncStatus, status, now, profileId, orderId],
      );
    }
  }

  void acknowledgeLocalOrder({
    required String profileId,
    required String orderId,
    String status = 'pending',
  }) {
    final order = orderForProfile(profileId, orderId);
    if (order == null || order.status != 'waiting_to_send') return;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('BEGIN');
    try {
      db.execute(
        '''UPDATE local_orders SET sync_status = 'synced', status = ?,
           updated_at = ? WHERE owner_profile_id = ? AND id = ?''',
        [status, now, profileId, orderId],
      );
      db.execute(
        '''INSERT OR IGNORE INTO status_updates(
          id, order_id, owner_profile_id, shop_id, customer_id, status,
          pickup_at, share_status, chat_enabled, sync_status, updated_at,
          version, deleted_at
        ) VALUES(?, ?, ?, ?, ?, ?, NULL, ?, ?, 'synced', ?, 1, NULL)''',
        [
          'ack-$orderId',
          orderId,
          profileId,
          order.shopId,
          order.customerId,
          status,
          order.shareStatus ? 1 : 0,
          order.chatEnabled ? 1 : 0,
          now,
        ],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updateLocalOrderStatus({
    required String profileId,
    required String orderId,
    required String status,
    DateTime? pickupAt,
    required bool shareStatus,
    required bool chatEnabled,
    String syncStatus = 'waiting_to_send',
  }) {
    final now = DateTime.now();
    final terminal =
        status == 'completed' || status == 'rejected' || status == 'cancelled';
    db.execute(
      '''UPDATE local_orders SET status = ?, pickup_at = ?, share_status = ?,
         chat_enabled = ?, sync_status = ?, updated_at = ?, expires_at = ?
         WHERE owner_profile_id = ? AND id = ?''',
      [
        status,
        pickupAt?.millisecondsSinceEpoch,
        shareStatus ? 1 : 0,
        chatEnabled ? 1 : 0,
        syncStatus,
        now.millisecondsSinceEpoch,
        terminal
            ? now.add(const Duration(days: 365)).millisecondsSinceEpoch
            : null,
        profileId,
        orderId,
      ],
    );
  }

  void queueSyncPayload({
    required String id,
    required String ownerProfileId,
    required String peerId,
    required String kind,
    required String payload,
  }) => enqueueSyncEvent(
    id: id,
    ownerProfileId: ownerProfileId,
    peerId: peerId,
    entityType: kind,
    entityId: id,
    entityVersion: 1,
    kind: kind,
    payload: payload,
  );

  void enqueueSyncEvent({
    required String id,
    required String ownerProfileId,
    required String peerId,
    required String entityType,
    required String entityId,
    required int entityVersion,
    required String kind,
    required String payload,
    int? nextAttemptAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''INSERT OR IGNORE INTO sync_queue(
        id, owner_profile_id, peer_id, entity_type, entity_id, entity_version,
        kind, payload, created_at, updated_at, attempts, next_attempt_at,
        last_error, state
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, '', 'queued')''',
      [
        id,
        ownerProfileId,
        peerId,
        entityType,
        entityId,
        entityVersion,
        kind,
        payload,
        now,
        now,
        nextAttemptAt ?? now,
      ],
    );
  }

  Map<String, Object?> recordOrderStatusEvent({
    required String ownerProfileId,
    required String orderId,
    required String eventId,
    required String peerId,
    required String status,
    DateTime? pickupAt,
    required bool shareStatus,
    required bool chatEnabled,
    required int updatedAt,
  }) {
    db.execute('BEGIN');
    try {
      final rows = db.select(
        'SELECT * FROM local_orders WHERE owner_profile_id = ? AND id = ? LIMIT 1',
        [ownerProfileId, orderId],
      );
      if (rows.isEmpty) throw StateError('Order not found');
      final order = LocalOrderRecord.fromRow(rows.first);
      final version = order.version + 1;
      final terminal =
          status == 'completed' ||
          status == 'rejected' ||
          status == 'cancelled';
      db.execute(
        '''UPDATE local_orders SET status = ?, pickup_at = ?, share_status = ?,
           chat_enabled = ?, sync_status = ?, version = ?, updated_at = ?,
           expires_at = ? WHERE owner_profile_id = ? AND id = ?''',
        [
          status,
          pickupAt?.millisecondsSinceEpoch,
          shareStatus ? 1 : 0,
          chatEnabled ? 1 : 0,
          'pending',
          version,
          updatedAt,
          terminal
              ? DateTime.fromMillisecondsSinceEpoch(
                  updatedAt,
                ).add(const Duration(days: 365)).millisecondsSinceEpoch
              : null,
          ownerProfileId,
          orderId,
        ],
      );
      db.execute(
        '''INSERT INTO status_updates(
          id, order_id, owner_profile_id, shop_id, customer_id, status,
          pickup_at, share_status, chat_enabled, sync_status, updated_at,
          version, deleted_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          eventId,
          orderId,
          ownerProfileId,
          order.shopId,
          order.customerId,
          status,
          pickupAt?.millisecondsSinceEpoch,
          shareStatus ? 1 : 0,
          chatEnabled ? 1 : 0,
          'pending',
          updatedAt,
          version,
          null,
        ],
      );
      final message = <String, Object?>{
        'type': 'order_status',
        'eventId': eventId,
        'orderId': orderId,
        'customerId': order.customerId,
        'shopId': order.shopId,
        'status': status,
        'pickupAt': pickupAt?.millisecondsSinceEpoch,
        'shareStatus': shareStatus,
        'chatEnabled': chatEnabled,
        'version': version,
        'updatedAt': updatedAt,
      };
      enqueueSyncEvent(
        id: eventId,
        ownerProfileId: ownerProfileId,
        peerId: peerId,
        entityType: 'order_status',
        entityId: orderId,
        entityVersion: version,
        kind: 'order_status',
        payload: jsonEncode(message),
      );
      db.execute('COMMIT');
      return message;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, Object?>> queuedSyncPayloads(String peerId) => db
      .select(
        'SELECT * FROM sync_queue WHERE peer_id = ? ORDER BY created_at',
        [peerId],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  bool hasQueuedSync(String peerId) => db.select(
    'SELECT 1 FROM sync_queue WHERE peer_id = ? LIMIT 1',
    [peerId],
  ).isNotEmpty;

  void markSyncAttempt(String id, String error) => db.execute(
    '''UPDATE sync_queue SET attempts = attempts + 1, last_error = ?
       WHERE id = ?''',
    [error, id],
  );

  void removeSyncPayload(String id) =>
      db.execute('DELETE FROM sync_queue WHERE id = ?', [id]);

  Map<String, Object?>? peerCursor(
    String localProfileId,
    String peerId,
    String stream,
  ) {
    final rows = db.select(
      '''SELECT last_updated_at, last_version, last_record_id FROM sync_peer_cursors
         WHERE local_profile_id = ? AND peer_id = ? AND stream = ? LIMIT 1''',
      [localProfileId, peerId, stream],
    );
    if (rows.isEmpty) return null;
    return {
      'updatedAt': rows.first['last_updated_at'] as int,
      'version': rows.first['last_version'] as int,
      'recordId': rows.first['last_record_id'] as String,
    };
  }

  void setPeerCursor({
    required String localProfileId,
    required String peerId,
    required String stream,
    required int updatedAt,
    required int version,
    required String recordId,
  }) => db.execute(
    '''INSERT INTO sync_peer_cursors(
      local_profile_id, peer_id, stream, last_updated_at, last_version,
      last_record_id, updated_at
    ) VALUES(?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(local_profile_id, peer_id, stream) DO UPDATE SET
      last_updated_at = excluded.last_updated_at,
      last_version = excluded.last_version,
      last_record_id = excluded.last_record_id,
      updated_at = excluded.updated_at''',
    [
      localProfileId,
      peerId,
      stream,
      updatedAt,
      version,
      recordId,
      DateTime.now().millisecondsSinceEpoch,
    ],
  );

  List<Map<String, Object?>> statusDeltas({
    required String ownerProfileId,
    required String customerId,
    int afterUpdatedAt = 0,
    int afterVersion = 0,
    String afterRecordId = '',
    int limit = 50,
  }) => db
      .select(
        '''SELECT * FROM status_updates
           WHERE owner_profile_id = ? AND customer_id = ?
             AND (updated_at > ? OR (updated_at = ? AND (version > ? OR (version = ? AND id > ?))))
           ORDER BY updated_at, version, id LIMIT ?''',
        [
          ownerProfileId,
          customerId,
          afterUpdatedAt,
          afterUpdatedAt,
          afterVersion,
          afterVersion,
          afterRecordId,
          limit,
        ],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> orderDeltas({
    required String ownerProfileId,
    required String shopId,
    int afterUpdatedAt = 0,
    int afterVersion = 0,
    String afterRecordId = '',
    int limit = 50,
  }) => db
      .select(
        '''SELECT * FROM local_orders
           WHERE owner_profile_id = ? AND shop_id = ?
             AND (updated_at > ? OR (updated_at = ? AND (version > ? OR (version = ? AND id > ?))))
           ORDER BY updated_at, version, id LIMIT ?''',
        [
          ownerProfileId,
          shopId,
          afterUpdatedAt,
          afterUpdatedAt,
          afterVersion,
          afterVersion,
          afterRecordId,
          limit,
        ],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  void upsertCustomerReplica({
    required String ownerProfileId,
    required String uuid,
    required String sourceProfileId,
    required String name,
    String phone = '',
    String email = '',
    String address = '',
    required int version,
    required int updatedAt,
  }) {
    db.execute(
      '''INSERT INTO customers(
        uuid, owner_profile_id, source_profile_id, name, phone, email,
        address, created_at, updated_at, sync_status, version, deleted_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(uuid) DO UPDATE SET
        name = excluded.name,
        phone = excluded.phone,
        email = excluded.email,
        address = excluded.address,
        updated_at = excluded.updated_at,
        sync_status = excluded.sync_status,
        version = excluded.version
      WHERE excluded.version >= customers.version''',
      [
        uuid,
        ownerProfileId,
        sourceProfileId,
        name,
        phone,
        email,
        address,
        updatedAt,
        updatedAt,
        'synced',
        version,
        null,
      ],
    );
  }

  static String syncPayloadHash(String payload) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(payload)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void saveCatalogCache({
    required String ownerProfileId,
    required String shopId,
    required String shopName,
    required int revision,
    required String payload,
  }) => db.execute(
    '''INSERT OR REPLACE INTO catalog_cache(
      owner_profile_id, shop_id, shop_name, payload, catalog_revision, synced_at
    ) VALUES(?, ?, ?, ?, ?, ?)''',
    [
      ownerProfileId,
      shopId,
      shopName,
      payload,
      revision,
      DateTime.now().millisecondsSinceEpoch,
    ],
  );

  List<CachedShopRecord> cachedShops(String ownerProfileId) {
    final rows = db.select(
      '''SELECT shop_id, shop_name, payload, catalog_revision, synced_at
         FROM catalog_cache WHERE owner_profile_id = ? ORDER BY synced_at DESC''',
      [ownerProfileId],
    );
    final result = <CachedShopRecord>[];
    for (final row in rows) {
      try {
        final payload =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        final products = (payload['products'] as List<dynamic>? ?? []).map((
          item,
        ) {
          final map = Map<String, dynamic>.from(item as Map);
          return ProductRecord(
            id: map['id'] as int?,
            uuid: map['uuid'] as String? ?? '',
            name: map['name'] as String? ?? 'Product',
            description: map['description'] as String? ?? '',
            category: map['category'] as String? ?? 'General',
            price: (map['price'] as num?)?.toDouble() ?? 0,
            isAvailable: map['available'] as bool? ?? true,
            isPublished: true,
            version: map['version'] as int? ?? 1,
          );
        }).toList();
        final syncedAt = DateTime.fromMillisecondsSinceEpoch(
          row['synced_at'] as int,
        );
        result.add(
          CachedShopRecord(
            shop: NearbyShopRecord(
              shopId: row['shop_id'] as String,
              name: row['shop_name'] as String,
              category: 'Previously visited',
              orderingEnabled: true,
              statusEnabled: true,
              chatEnabled: true,
              catalogRevision: row['catalog_revision'] as int,
              lastSeen: syncedAt,
            ),
            products: products,
            syncedAt: syncedAt,
          ),
        );
      } catch (_) {
        // Ignore malformed cache rows; a live sync can repopulate them.
      }
    }
    return result;
  }

  int cleanupExpiredOrders() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = db.select(
      'SELECT id, owner_profile_id FROM local_orders WHERE expires_at IS NOT NULL AND expires_at <= ?',
      [now],
    );
    if (expired.isEmpty) return 0;
    db.execute('BEGIN');
    try {
      for (final order in expired) {
        final args = [order['id'], order['owner_profile_id']];
        db.execute(
          'DELETE FROM status_updates WHERE order_id = ? AND owner_profile_id = ?',
          args,
        );
        db.execute(
          'DELETE FROM order_messages WHERE order_id = ? AND owner_profile_id = ?',
          args,
        );
        db.execute(
          'DELETE FROM local_order_items WHERE order_id = ? AND owner_profile_id = ?',
          args,
        );
        db.execute(
          'DELETE FROM local_orders WHERE id = ? AND owner_profile_id = ?',
          args,
        );
      }
      db.execute('COMMIT');
      return expired.length;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteProducts(Iterable<int> ids) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('BEGIN');
    final statement = db.prepare(
      '''UPDATE products SET deleted_at = ?, sync_status = ?, version = version + 1,
         updated_at = ? WHERE id = ? AND deleted_at IS NULL''',
    );
    try {
      for (final id in ids) {
        statement.execute([now, 'pending', now, id]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      statement.close();
    }
  }

  List<InvoiceTemplateRecord> templates() => db
      .select(
        'SELECT * FROM invoice_templates ORDER BY is_selected DESC, updated_at DESC',
      )
      .map(InvoiceTemplateRecord.fromRow)
      .toList();

  InvoiceTemplateRecord? selectedTemplate() {
    final rows = db.select(
      'SELECT * FROM invoice_templates WHERE is_selected = 1 ORDER BY updated_at DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return InvoiceTemplateRecord.fromRow(rows.first);
  }

  void saveTemplate(InvoiceTemplateRecord template) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('BEGIN');
    try {
      if (template.id == null && count('invoice_templates') >= 5) {
        throw StateError('A maximum of 5 invoice templates is allowed.');
      }
      if (template.isSelected) {
        db.execute('UPDATE invoice_templates SET is_selected = 0');
      }
      if (template.id == null) {
        final shouldSelect =
            template.isSelected || count('invoice_templates') == 0;
        db.execute(
          'INSERT INTO invoice_templates(organization_name, logo_path, currency, accent_color, notes, terms, upi_payee_name, upi_id, upi_enabled, is_selected, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            template.organizationName,
            template.logoPath,
            template.currency,
            template.accentColor,
            template.notes,
            template.terms,
            template.upiPayeeName,
            template.upiId,
            template.upiEnabled ? 1 : 0,
            shouldSelect ? 1 : 0,
            now,
            now,
          ],
        );
      } else {
        db.execute(
          'UPDATE invoice_templates SET organization_name = ?, logo_path = ?, currency = ?, accent_color = ?, notes = ?, terms = ?, upi_payee_name = ?, upi_id = ?, upi_enabled = ?, is_selected = ?, updated_at = ? WHERE id = ?',
          [
            template.organizationName,
            template.logoPath,
            template.currency,
            template.accentColor,
            template.notes,
            template.terms,
            template.upiPayeeName,
            template.upiId,
            template.upiEnabled ? 1 : 0,
            template.isSelected ? 1 : 0,
            now,
            template.id,
          ],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void selectTemplate(int id) {
    db.execute('BEGIN');
    try {
      db.execute('UPDATE invoice_templates SET is_selected = 0');
      db.execute('UPDATE invoice_templates SET is_selected = 1 WHERE id = ?', [
        id,
      ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteTemplate(int id) {
    db.execute('BEGIN');
    try {
      db.execute(
        'UPDATE invoices SET template_id = NULL WHERE template_id = ?',
        [id],
      );
      db.execute('DELETE FROM invoice_templates WHERE id = ?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  String saveInvoice({
    required String invoiceNumber,
    required List<CartLine> lines,
    required int? templateId,
    required double total,
    required String pdfPath,
    String upiPayeeName = '',
    String upiId = '',
    String paymentMethod = 'upi',
    String? invoiceUuid,
    String? customerUuid,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError('Invoice must contain at least one item.');
    }
    if (total < 0) throw ArgumentError('Invoice total cannot be negative.');
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = activeProfile();
    final uuid = invoiceUuid ?? const Uuid().v4();
    db.execute('BEGIN');
    try {
      db.execute(
        'INSERT INTO invoices(uuid, owner_profile_id, source_profile_id, customer_uuid, invoice_number, template_id, subtotal, total, status, pdf_path, created_at, updated_at, upi_payee_name, upi_id, payment_method, sync_status, version, deleted_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          uuid,
          profile?.id,
          profile?.id,
          customerUuid,
          invoiceNumber,
          templateId,
          total,
          total,
          'payment_pending',
          pdfPath,
          now,
          now,
          upiPayeeName,
          upiId,
          paymentMethod,
          'pending',
          1,
          null,
        ],
      );
      final invoiceId = db.lastInsertRowId;
      final statement = db.prepare(
        'INSERT INTO invoice_items(uuid, invoice_id, invoice_uuid, owner_profile_id, source_profile_id, product_id, product_name, quantity, unit_price, total, profit_total, sync_status, version, deleted_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final line in lines) {
          final profitTotal = line.total * line.product.profitPercent / 100;
          statement.execute([
            const Uuid().v4(),
            invoiceId,
            uuid,
            profile?.id,
            profile?.id,
            line.product.id,
            line.product.name,
            line.quantity,
            line.product.price,
            line.total,
            profitTotal,
            'pending',
            1,
            null,
          ]);
        }
      } finally {
        statement.close();
      }
      db.execute('COMMIT');
      return invoiceNumber;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updateInvoicePayment(
    String invoiceNumber,
    String status, {
    String note = '',
  }) {
    db.execute(
      '''UPDATE invoices SET status = ?, payment_note = ?, updated_at = ?,
         version = version + 1, sync_status = ? WHERE invoice_number = ?''',
      [
        status,
        note,
        DateTime.now().millisecondsSinceEpoch,
        'pending',
        invoiceNumber,
      ],
    );
  }

  InvoiceRecoveryData? invoiceRecoveryData(String invoiceNumber) {
    final invoiceRows = db.select(
      'SELECT invoice_number, total, template_id, upi_payee_name, upi_id, payment_method FROM invoices WHERE invoice_number = ? LIMIT 1',
      [invoiceNumber],
    );
    if (invoiceRows.isEmpty) return null;
    final invoice = invoiceRows.first;
    final templateRows = invoice['template_id'] == null
        ? <Row>[]
        : db.select('SELECT * FROM invoice_templates WHERE id = ? LIMIT 1', [
            invoice['template_id'],
          ]);
    final template = templateRows.isNotEmpty
        ? InvoiceTemplateRecord.fromRow(templateRows.first)
        : selectedTemplate();
    if (template == null) return null;

    final invoiceIdRows = db.select(
      'SELECT id FROM invoices WHERE invoice_number = ? LIMIT 1',
      [invoiceNumber],
    );
    if (invoiceIdRows.isEmpty) return null;
    final itemRows = db.select(
      'SELECT product_id, product_name, quantity, unit_price, profit_total FROM invoice_items WHERE invoice_id = ? ORDER BY id',
      [invoiceIdRows.first['id']],
    );
    final lines = itemRows.map((row) {
      final quantity = row['quantity'] as int;
      final unitPrice = (row['unit_price'] as num).toDouble();
      final lineTotal = unitPrice * quantity;
      final profitTotal = (row['profit_total'] as num).toDouble();
      return CartLine(
        product: ProductRecord(
          id: row['product_id'] as int?,
          name: row['product_name'] as String,
          price: unitPrice,
          profitPercent: lineTotal == 0 ? 0 : profitTotal / lineTotal * 100,
        ),
        quantity: quantity,
      );
    }).toList();
    if (lines.isEmpty) return null;
    return InvoiceRecoveryData(
      number: invoiceNumber,
      total: (invoice['total'] as num).toDouble(),
      upiPayeeName: invoice['upi_payee_name'] as String,
      upiId: invoice['upi_id'] as String,
      paymentMethod: invoice['payment_method'] as String,
      template: template,
      lines: lines,
    );
  }

  void updateInvoicePdfPath(String invoiceNumber, String path) {
    db.execute('UPDATE invoices SET pdf_path = ? WHERE invoice_number = ?', [
      path,
      invoiceNumber,
    ]);
  }

  void recordPayment({
    required String invoiceNumber,
    required double amount,
    required String method,
    String note = '',
  }) {
    final rows = db.select(
      'SELECT id, status FROM invoices WHERE invoice_number = ? LIMIT 1',
      [invoiceNumber],
    );
    if (rows.isEmpty) return;
    if (rows.first['status'] == 'paid') return;
    final paidAt = DateTime.now().millisecondsSinceEpoch;
    final profile = activeProfile();
    final invoiceUuid =
        db.select('SELECT uuid FROM invoices WHERE id = ? LIMIT 1', [
              rows.first['id'],
            ]).first['uuid']
            as String?;
    db.execute('BEGIN');
    try {
      db.execute(
        'INSERT INTO payments(uuid, invoice_id, invoice_uuid, owner_profile_id, source_profile_id, amount, method, paid_at, note, sync_status, version, deleted_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          const Uuid().v4(),
          rows.first['id'],
          invoiceUuid,
          profile?.id,
          profile?.id,
          amount,
          method,
          paidAt,
          note,
          'pending',
          1,
          null,
        ],
      );
      db.execute(
        '''UPDATE invoices SET status = ?, payment_note = ?, updated_at = ?,
           version = version + 1, sync_status = ? WHERE invoice_number = ?''',
        ['paid', note, paidAt, 'pending', invoiceNumber],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  InvoicePageResult invoicePage({
    int page = 0,
    String query = '',
    String status = 'all',
    String sort = 'newest',
  }) {
    final filters = <String>[];
    final args = <Object?>[];
    final term = query.trim();
    filters.add('deleted_at IS NULL');
    if (term.isNotEmpty) {
      filters.add('(invoice_number LIKE ? OR payment_note LIKE ?)');
      args.addAll(['%$term%', '%$term%']);
    }
    if (status != 'all') {
      filters.add('status = ?');
      args.add(status);
    }
    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final order = switch (sort) {
      'oldest' => 'created_at ASC',
      'amount_high' => 'total DESC, created_at DESC',
      'amount_low' => 'total ASC, created_at DESC',
      _ =>
        "CASE WHEN status = 'payment_pending' THEN 0 ELSE 1 END, created_at DESC",
    };
    final total =
        db
                .select('SELECT COUNT(*) AS total FROM invoices $where', args)
                .first['total']
            as int;
    final rows = db.select(
      'SELECT invoice_number, total, status, created_at, pdf_path, upi_id, upi_payee_name, payment_note, payment_method FROM invoices $where ORDER BY $order LIMIT 10 OFFSET ?',
      [...args, page * 10],
    );
    return InvoicePageResult(
      total: total,
      invoices: rows.map(_invoiceFromRow).toList(),
    );
  }

  RecentInvoice _invoiceFromRow(Row row) => RecentInvoice(
    number: row['invoice_number'] as String,
    total: (row['total'] as num).toDouble(),
    status: row['status'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    pdfPath: row['pdf_path'] as String,
    upiId: row['upi_id'] as String,
    upiPayeeName: row['upi_payee_name'] as String,
    paymentNote: row['payment_note'] as String,
    paymentMethod: row['payment_method'] as String,
  );

  DashboardStats dashboardStats() {
    double sum(String sql) =>
        ((db.select(sql).first['value'] as num?) ?? 0).toDouble();
    final recent = db
        .select(
          "SELECT invoice_number, total, status, created_at, pdf_path, upi_id, upi_payee_name, payment_note, payment_method FROM invoices WHERE deleted_at IS NULL ORDER BY CASE WHEN status = 'payment_pending' THEN 0 ELSE 1 END, created_at DESC LIMIT 5",
        )
        .map(
          (row) => RecentInvoice(
            number: row['invoice_number'] as String,
            total: (row['total'] as num).toDouble(),
            status: row['status'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            pdfPath: row['pdf_path'] as String,
            upiId: row['upi_id'] as String,
            upiPayeeName: row['upi_payee_name'] as String,
            paymentNote: row['payment_note'] as String,
            paymentMethod: row['payment_method'] as String,
          ),
        )
        .toList();

    final activeProducts =
        db
                .select(
                  'SELECT COUNT(*) value FROM products WHERE deleted_at IS NULL',
                )
                .first['value']
            as int;
    final activeCustomers =
        db
                .select(
                  'SELECT COUNT(*) value FROM customers WHERE deleted_at IS NULL',
                )
                .first['value']
            as int;
    final activeInvoices =
        db
                .select(
                  'SELECT COUNT(*) value FROM invoices WHERE deleted_at IS NULL',
                )
                .first['value']
            as int;
    return DashboardStats(
      products: activeProducts,
      customers: activeCustomers,
      invoices: activeInvoices,
      revenue: sum(
        "SELECT SUM(total) value FROM invoices WHERE deleted_at IS NULL AND status = 'paid'",
      ),
      profit: sum(
        'SELECT SUM(profit_total) value FROM invoice_items WHERE deleted_at IS NULL',
      ),
      pending: sum(
        "SELECT SUM(total) value FROM invoices WHERE deleted_at IS NULL AND status != 'paid'",
      ),
      recentInvoices: recent,
    );
  }
}
