import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class Breakpoints {
  static bool get mobileOrTablet {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 720;
  static bool narrowDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 1020;
  static bool wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100;
  static double maxWidth(BuildContext context) =>
      wide(context) ? 1180 : double.infinity;
  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1100) return const EdgeInsets.all(28);
    if (width >= 700) return const EdgeInsets.all(22);
    return const EdgeInsets.all(16);
  }
}

class AppSize {
  static double scale(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    if (size.width >= 1100) return 1;
    return (shortest / 390).clamp(.88, 1.08).toDouble();
  }

  static double text(BuildContext context, double value) =>
      value * scale(context);
  static double space(BuildContext context, double value) =>
      value * scale(context);
  static double icon(BuildContext context, double value) =>
      value * scale(context);
  static double radius(BuildContext context, double value) =>
      value * scale(context);

  static double width(BuildContext context, double percent) =>
      MediaQuery.sizeOf(context).width * percent;
  static double height(BuildContext context, double percent) =>
      MediaQuery.sizeOf(context).height * percent;
}
