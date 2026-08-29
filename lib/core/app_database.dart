import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class ProductRecord {
  final int? id;
  final String name;
  final double price;
  final double profitPercent;
  final int stockQuantity;

  const ProductRecord({
    this.id,
    required this.name,
    required this.price,
    this.profitPercent = 0,
    this.stockQuantity = 0,
  });

  factory ProductRecord.fromRow(Row row) => ProductRecord(
    id: row['id'] as int,
    name: row['name'] as String,
    price: (row['price'] as num).toDouble(),
    profitPercent: (row['profit_percent'] as num).toDouble(),
    stockQuantity: row['stock_quantity'] as int,
  );
}

class CustomerRecord {
  final int? id;
  final String name;
  final String phone;
  final String email;
  final String address;

  const CustomerRecord({
    this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
  });
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
    _migrateProductSkuColumn();
    _ensureColumn('products', 'profit_percent', 'REAL NOT NULL DEFAULT 0');
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
    await _migrateLegacyDefaultInvoiceDir(appDir.path);
    await _migrateLegacyJsonOnce();
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
    final location = prefs.getString('save_location');
    if (location != null && location.isNotEmpty) {
      await _migrateProducts(File(p.join(location, 'products_data.json')));
      await _migrateTemplates(File(p.join(location, 'invoice_templates.json')));
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
        ? db.select('SELECT * FROM products ORDER BY updated_at DESC')
        : db.select('SELECT * FROM products WHERE name LIKE ? ORDER BY name', [
            term,
          ]);
    return rows.map(ProductRecord.fromRow).toList();
  }

  bool productNameExists(String name, {int? exceptId}) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final rows = exceptId == null
        ? db.select('SELECT id FROM products WHERE lower(name) = ? LIMIT 1', [
            normalized,
          ])
        : db.select(
            'SELECT id FROM products WHERE lower(name) = ? AND id != ? LIMIT 1',
            [normalized, exceptId],
          );
    return rows.isNotEmpty;
  }

  void saveProduct(ProductRecord product) {
    if (productNameExists(product.name, exceptId: product.id)) {
      throw ArgumentError('A product with this name already exists.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (product.id == null) {
      db.execute(
        'INSERT INTO products(name, price, profit_percent, stock_quantity, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?)',
        [
          product.name,
          product.price,
          product.profitPercent,
          product.stockQuantity,
          now,
          now,
        ],
      );
    } else {
      db.execute(
        'UPDATE products SET name = ?, price = ?, profit_percent = ?, stock_quantity = ?, updated_at = ? WHERE id = ?',
        [
          product.name,
          product.price,
          product.profitPercent,
          product.stockQuantity,
          now,
          product.id,
        ],
      );
    }
  }

  void deleteProducts(Iterable<int> ids) {
    db.execute('BEGIN');
    final statement = db.prepare('DELETE FROM products WHERE id = ?');
    final clearInvoiceItems = db.prepare(
      'UPDATE invoice_items SET product_id = NULL WHERE product_id = ?',
    );
    try {
      for (final id in ids) {
        clearInvoiceItems.execute([id]);
        statement.execute([id]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      clearInvoiceItems.close();
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
  }) {
    if (lines.isEmpty) {
      throw ArgumentError('Invoice must contain at least one item.');
    }
    if (total < 0) throw ArgumentError('Invoice total cannot be negative.');
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('BEGIN');
    try {
      db.execute(
        'INSERT INTO invoices(invoice_number, template_id, subtotal, total, status, pdf_path, created_at, upi_payee_name, upi_id, payment_method) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          invoiceNumber,
          templateId,
          total,
          total,
          'payment_pending',
          pdfPath,
          now,
          upiPayeeName,
          upiId,
          paymentMethod,
        ],
      );
      final invoiceId = db.lastInsertRowId;
      final statement = db.prepare(
        'INSERT INTO invoice_items(invoice_id, product_id, product_name, quantity, unit_price, total, profit_total) VALUES(?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final line in lines) {
          final profitTotal = line.total * line.product.profitPercent / 100;
          statement.execute([
            invoiceId,
            line.product.id,
            line.product.name,
            line.quantity,
            line.product.price,
            line.total,
            profitTotal,
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
      'UPDATE invoices SET status = ?, payment_note = ? WHERE invoice_number = ?',
      [status, note, invoiceNumber],
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
    db.execute('BEGIN');
    try {
      db.execute(
        'INSERT INTO payments(invoice_id, amount, method, paid_at, note) VALUES(?, ?, ?, ?, ?)',
        [
          rows.first['id'],
          amount,
          method,
          DateTime.now().millisecondsSinceEpoch,
          note,
        ],
      );
      db.execute(
        'UPDATE invoices SET status = ?, payment_note = ? WHERE invoice_number = ?',
        ['paid', note, invoiceNumber],
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
          "SELECT invoice_number, total, status, created_at, pdf_path, upi_id, upi_payee_name, payment_note, payment_method FROM invoices ORDER BY CASE WHEN status = 'payment_pending' THEN 0 ELSE 1 END, created_at DESC LIMIT 5",
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

    return DashboardStats(
      products: count('products'),
      customers: count('customers'),
      invoices: count('invoices'),
      revenue: sum(
        "SELECT SUM(total) value FROM invoices WHERE status = 'paid'",
      ),
      profit: sum('SELECT SUM(profit_total) value FROM invoice_items'),
      pending: sum(
        "SELECT SUM(total) value FROM invoices WHERE status != 'paid'",
      ),
      recentInvoices: recent,
    );
  }
}
