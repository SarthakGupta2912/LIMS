# LIMS

LIMS is an offline-first invoice, shop ordering, and local device communication app for small businesses. It runs on Android and Windows, stores operational data locally in SQLite, and lets customers connect to a shop over a nearby Wi-Fi connection without requiring cloud infrastructure.

## Features

### Shopkeeper tools

- Responsive dashboard with revenue, pending amount, invoice count, product count, and recent activity.
- Product catalog management with search, add, edit, bulk selection, and delete actions.
- Counter billing with quantity controls, cart management, and local PDF invoice generation.
- Invoice history with local invoice records and generated PDF files.
- Invoice templates with logo path, currency, notes, terms, accent color, and selected-template support.
- Customer order management with New, Active, Ready, Completed, and All filters.
- Order status updates, pickup time estimates, customer reachability, order messaging, and optional buzz notifications.
- Shop menu publishing for nearby customers.
- Local connection controls for starting a shop hotspot, showing a connection QR code, and transferring files to connected devices.

### Customer tools

- Customer profiles stored locally on the device.
- QR-based connection to a shop's Wi-Fi hotspot.
- Shop menu synchronization over the local connection.
- Product browsing and order creation without an internet backend.
- Local order history and order detail screens.
- Order status updates while connected to the shop.

### Shared app features

- Role-based profiles for Shopkeeper and Customer users.
- Multiple local profiles on one device with profile switching.
- Offline-first SQLite storage for products, templates, invoices, customers, shops, profiles, orders, and synchronization metadata.
- Nearby transport support using Wi-Fi Direct, local network connections, and Bluetooth-compatible nearby discovery where supported.
- Delta synchronization for transferring only changed records between connected devices.
- Local notifications, vibration feedback, and foreground connection handling on Android.
- Adaptive Material 3 interface with a desktop/sidebar layout and compact Android bottom navigation.
- File picking and opening for invoice PDFs and transferred files.

## How local ordering works

1. A shopkeeper opens the local connection screen and starts the shop hotspot.
2. LIMS displays a QR code containing the shop connection information.
3. The customer scans the QR code from the Customer screen.
4. The customer device joins the shop's local Wi-Fi connection and synchronizes the shop menu.
5. The customer places an order from the synchronized menu.
6. The shopkeeper receives the order locally and updates its status through preparation and pickup.

The local workflow is designed for nearby communication. It does not require a hosted API or continuous internet access. Android permissions, Wi-Fi support, and device capabilities determine which nearby transport options are available.

## Project structure

```text
lib/
  app/                 App shell, theme, responsive helpers, and navigation
  core/                SQLite database, profiles, notifications, connection services
  core/nearby/         Nearby transports, sessions, reconnection, and protocols
  data/                Database migrations and synchronization data helpers
  Pages/               Dashboard, products, billing, invoices, templates,
                       customers, orders, profiles, and connection screens
  shared/              Reusable UI, help, file, and formatting helpers
  sync/                Delta store, sync messages, and synchronization logic
test/                  Unit, widget, and integration tests
android/               Android platform code and local connection implementation
third_party/           Local flutter_nearby_connections_plus plugin source
tools/                 Development and screenshot utilities
```

The app intentionally keeps its application logic close to the pages and service classes instead of introducing a large state-management framework. `AppDatabase` is the local source of truth, while nearby services coordinate connections and synchronization around the active profile.

## Local data and files

LIMS stores its SQLite database in the platform application-support directory. Profile data, shop data, products, customers, orders, invoices, templates, and synchronization state remain on the device unless explicitly transferred through a nearby connection.

Generated invoices are saved in the folder selected from Settings. If no folder has been selected, the app uses a local `invoices` directory beside the application data. Files received through the local transfer screen can be opened from the app after they are accepted.

## Requirements

- Flutter SDK compatible with Dart `^3.12.2`.
- Android Studio and an Android device or emulator for Android builds.
- A Windows desktop environment for Windows builds.
- Camera permission for scanning shop connection QR codes.
- Nearby Wi-Fi, Bluetooth, and notification permissions as requested by Android for local connection and order features.

The local `third_party/flutter_nearby_connections_plus` package is used through a dependency override in `pubspec.yaml`. Keep that directory available when running `flutter pub get`.

## Setup

```bash
flutter pub get
flutter analyze
flutter test
```

Run the application on a target platform:

```bash
flutter run -d windows
flutter run -d android
```

For local connection testing, use two physical Android devices when possible. Create a Shopkeeper profile on one device, start its hotspot, scan its QR code from a Customer profile on the second device, and then place a test order.

## Testing

The test suite covers invoice and order UI flows, customer QR and order behavior, SQLite synchronization, nearby transport codecs and routing, reconnection, Wi-Fi hotspot behavior, and local connection page interactions.

Run the complete suite with:

```bash
flutter test
```

Use static analysis before submitting changes:

```bash
flutter analyze
```

## Development notes

- The Android local connection bridge is implemented in `android/app/src/main/kotlin/com/Sarthak/lims/` and communicates with Flutter through a dedicated method channel and event channel.
- Android local communication uses cleartext local traffic and foreground connected-device services where required by the platform.
- Customer discovery currently uses the shop QR connection flow as the primary connection path.
- Local profile data is intentionally device-local. Switching profiles logs out of the active role without deleting the other profiles or their data.

## License

This project is currently maintained as a private application repository. Add the project license here when a distribution license is selected.
