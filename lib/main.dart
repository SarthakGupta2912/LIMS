import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lims/app/app.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await lgw.LiquidGlassWidgets.initialize();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final windowSize = _initialWindowSize(primaryDisplay);
    final windowOptions = WindowOptions(
      size: windowSize,
      minimumSize: Size(
        windowSize.width < 760 ? windowSize.width : 760,
        windowSize.height < 520 ? windowSize.height : 520,
      ),
      center: true,
      backgroundColor: const Color(0xFFF6F8FB),
      skipTaskbar: false,
      title: 'LIMS',
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    lgw.LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      theme: lgw.GlassThemeData.simple(
        blur: 10,
        thickness: 28,
        chromaticAberration: 0,
        lightIntensity: .18,
        ambientStrength: .04,
        refractiveIndex: 1.14,
        saturation: 1.05,
        quality: lgw.GlassQuality.standard,
        brightness: Brightness.dark,
      ),
      child: const InvoiceApp(),
    ),
  );
}

Size _initialWindowSize(Display display) {
  final visibleSize = display.visibleSize ?? display.size;
  final availableWidth = (visibleSize.width - 80).clamp(640, 1120).toDouble();
  final availableHeight = (visibleSize.height - 80).clamp(480, 680).toDouble();
  return Size(availableWidth, availableHeight);
}
