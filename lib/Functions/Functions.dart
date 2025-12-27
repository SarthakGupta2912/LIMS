import 'package:flutter/material.dart';
// import 'package:invoice_management_system/Widgets/Widgets.dart'; // Removed unused import

import '../Modals.dart';

Size media = Size(0, 0);
final List<Product> products = [];
final String dataFileName = "products_data.json";
Future<void> push(BuildContext context, Widget page) async {
  await Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child; // No animation, just return the child widget.
      },
    ),
  );
}

// Replace the current route with a new one
Future<void> replace(BuildContext context, Widget page) async {
  await Navigator.pushReplacement(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child; // No animation, just return the child widget.
      },
    ),
  );
}

// Replace the current route with a new one and remove all the previous routes
Future<void> pushAndRemovePreviousRoutes(
  BuildContext context,
  Widget page,
) async {
  await Navigator.pushAndRemoveUntil(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child; // No animation, just return the child widget.
      },
    ),
    (Route<dynamic> route) => false, // Remove all previous routes
  );
}

// Pop the current route off the navigation stack
void pop(BuildContext context) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    debugPrint('No routes left to pop');
  }
}

void showToast(String msg, BuildContext context, {bool isShort = true}) {
  final duration = isShort ? Duration(seconds: 2) : Duration(seconds: 4);
  ScaffoldMessenger.of(
    context,
  ).removeCurrentSnackBar(); // Dismiss any active Snackbar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      width: media.width * 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A237E), // Deep Indigo
      elevation: 4,
    ),
  );
}
