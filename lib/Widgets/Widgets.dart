import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invoice_management_system/Pages/Billing/BillingMode.dart';

import '../Functions/Functions.dart';

// 🔹 Reusable method for text field theme
InputDecoration customInputDecoration({
  required String label,
  required String hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    // Theme is handled by InputDecorationTheme in main.dart
  );
}

// Custom formatter to disallow leading & trailing spaces
class NoLeadingTrailingSpaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String trimmed = newValue.text;

    // Prevent leading space
    if (trimmed.startsWith(' ')) {
      trimmed = trimmed.trimLeft();
    }
    // Prevent trailing space
    if (trimmed.endsWith(' ')) {
      trimmed = trimmed.trimRight();
    }

    return TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }
}

TextStyle myInputFieldTextStyle() {
  return TextStyle(fontSize: media.height * 0.024);
}

Future<void> showErrorDialog(
  BuildContext context,
  String title,
  String errorDescription,
  IconData icon,
  Widget pageToLoad,
) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(icon, size: 50, color: Colors.red),
          title: Text(title, style: Theme.of(context).textTheme.titleLarge),
          content: Text(
            errorDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          actions: <Widget>[
            Center(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text('Retry'),
                onPressed: () async {
                  await pushAndRemovePreviousRoutes(context, pageToLoad);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class MyAppbar extends StatelessWidget implements PreferredSizeWidget {
  final double height;
  final Widget? page;
  final VoidCallback? onBackPressed;
  final String appBarTitle;
  final bool isFirstPage;
  final List<Widget>? actions;
  const MyAppbar({
    super.key,
    this.height = kToolbarHeight,
    this.page,
    this.onBackPressed,
    this.appBarTitle = '',
    this.isFirstPage = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(appBarTitle),
      actions: actions,
      leading: (isFirstPage)
          ? IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            )
          : IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                if (onBackPressed != null) {
                  onBackPressed!();
                } else {
                  (page == null) ? pop(context) : replace(context, page!);
                }
              },
            ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
}

class MyTextWidget extends StatelessWidget {
  final String text;
  final String? textType;
  final TextAlign? textAlign;
  final int? maxLines;

  const MyTextWidget({
    super.key,
    required this.text,
    this.textType,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    TextStyle? style;

    if (textType == 'AppBar') {
      style = theme.titleLarge?.copyWith(color: Colors.white);
    } else if (textType == 'Heading') {
      style = theme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);
    } else {
      style = theme.bodyLarge;
    }

    return Text(
      text,
      textAlign: textAlign,
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: maxLines,
    );
  }
}

class Button extends StatelessWidget {
  final VoidCallback onTap;
  final String text;
  final Color? color;
  final Color? textcolor;
  final double? width;
  final double? height;
  final IconData? icon;
  final IconData? icon2;
  final double? fontsize;
  final bool isTextBold;
  final bool isLoading;

  const Button({
    super.key,
    required this.onTap,
    required this.text,
    this.color,
    this.textcolor,
    this.width,
    this.height,
    this.icon,
    this.icon2,
    this.fontsize,
    this.isTextBold = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height ?? 50,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, // Uses theme default if null
          foregroundColor: textcolor, // Uses theme default if null
          textStyle: TextStyle(
            fontSize: fontsize,
            fontWeight: isTextBold ? FontWeight.bold : FontWeight.normal,
          ),
          padding: EdgeInsets.symmetric(horizontal: 16),
        ),
        child: isLoading
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: textcolor ?? Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon), SizedBox(width: 8)],
                  Text(text),
                  if (icon2 != null) ...[SizedBox(width: 8), Icon(icon2)],
                ],
              ),
      ),
    );
  }
}

class DeleteConfirmationDialog {
  static void show({
    required BuildContext context,
    required String productName,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete"),
          content: Text("Are you sure you want to delete '$productName'?"),
          actions: [
            TextButton(
              onPressed: () => pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                onConfirm();
                pop(context);
              },
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
  }
}

class DrawerCard extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color color;

  const DrawerCard({
    super.key,
    required this.onTap,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      color: color,
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Icon(icon, color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// 🔹 Success Dialog with Auto-Close
Future<void> showSuccessDialog(
  BuildContext context,
  String message, {
  Widget? pageToLoad,
}) async {
  Timer? timer;

  // Start timer to auto-close
  timer = Timer(const Duration(seconds: 5), () {
    if (context.mounted && Navigator.canPop(context)) {
      pop(context);
      if (pageToLoad != null) {
        replace(context, pageToLoad);
      }
    }
  });

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            Text(
              "Success!",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    },
  ).then((_) {
    // Ensure timer is cancelled if dialog is dismissed manually
    if (timer?.isActive ?? false) {
      timer?.cancel();
    }
  });
}
