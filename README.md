# Invoice Management System

Offline-first invoice software for small businesses that need a simple, local, and affordable way to manage products, invoice templates, billing, and PDF invoices across Android and Windows.

## Current Features

- Professional responsive dashboard with revenue, pending amount, invoice count, and product count.
- SQLite local database for products, invoice templates, invoices, invoice items, payments, customers, and app settings.
- One-time migration from the older JSON product/template files when a previous save location exists.
- Product management with search, add, edit, bulk selection, and delete.
- Fast billing mode with quantity steppers, adaptive cart panel, and local PDF generation.
- Invoice template manager with logo path, currency, notes, terms, accent color, and selected-template support.
- Settings screen for choosing or resetting the invoice PDF save folder.
- Adaptive Material 3 UI: desktop sidebar on Windows/tablets and bottom navigation on compact Android screens.

## Architecture

```text
lib/
  app/          App shell, theme, responsive helpers
  core/         SQLite database and data models
  features/     Dashboard, products, billing, templates
  shared/       Reusable UI helpers and widgets
```

The app intentionally avoids heavy state-management frameworks for now. Pages read/write through `AppDatabase` and refresh the shell after mutations. This keeps the codebase approachable for contributors and lightweight for low-end devices.

## Local Data

Data is stored in a portable SQLite database under the platform application-support directory. Generated invoices are saved in the folder selected from Settings, with a default `invoices` folder beside the database.

Planned portability features:

- Export/import backup ZIP containing the database, logos, and PDFs.
- CSV import/export for products and customers.
- Invoice history restore on another device.

## Setup

```bash
flutter pub get
flutter analyze
flutter run -d windows
flutter run -d android
```

## Roadmap

- Customer management.
- Invoice history screen with open/share/export actions.
- Tax, discount, due date, payment status, and overdue tracking.
- Backup and restore.
- CSV import/export.
- UPI QR support.
- Dashboard charts.
- Light/dark theme toggle.
- Widget and database tests.
- CI workflow for `flutter analyze` and builds.
