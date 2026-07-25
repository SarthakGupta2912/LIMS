import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../app/responsive.dart';
import '../widgets.dart';

export '../widgets.dart';

String money(double value, [String currency = 'Rs.']) =>
    '$currency ${value.toStringAsFixed(2)}';

class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF10181B)),
      child: child,
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color color;
  final Border? border;
  final Color? glassColor;
  final Color? backerColor;
  final Color? platformViewFallbackColor;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
    this.blur = 16,
    this.color = const Color(0x2EFFFFFF),
    this.border,
    this.glassColor,
    this.backerColor,
    this.platformViewFallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = AppSize.radius(context, radius);
    final mobileOrTablet = Breakpoints.mobileOrTablet;
    final effectiveBlur = mobileOrTablet ? blur.clamp(8, 14).toDouble() : blur;
    final effectiveColor =
        glassColor ??
        Color.alphaBlend(
          mobileOrTablet ? const Color(0x1410181B) : Colors.transparent,
          color,
        );
    final glass = lgw.GlassContainer(
      padding: padding,
      useOwnLayer: true,
      quality: lgw.GlassQuality.standard,
      clipBehavior: Clip.antiAlias,
      shape: lgw.LiquidRoundedSuperellipse(borderRadius: effectiveRadius),
      settings: lgw.LiquidGlassSettings(
        glassColor: effectiveColor,
        blur: effectiveBlur,
        thickness: 28,
        chromaticAberration: 0,
        lightIntensity: .18,
        ambientStrength: .04,
        ambientRim: .08,
        refractiveIndex: 1.14,
        saturation: 1.05,
        glowIntensity: 0,
        specularSharpness: lgw.GlassSpecularSharpness.sharp,
        standardOpacityMultiplier: .92,
        shadowElevation: .45,
        backerColor: backerColor ?? const Color(0x6610181B),
        platformViewFallbackColor:
            platformViewFallbackColor ?? const Color(0xCC10181B),
      ),
      child: child,
    );

    if (border == null) return RepaintBoundary(child: glass);

    return RepaintBoundary(
      child: Stack(
        children: [
          glass,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(effectiveRadius),
                  border: border,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlassDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  const GlassDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.maxWidth = 520,
  });

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final size = MediaQuery.sizeOf(context);
        final media = MediaQuery.of(context);
        final keyboardInset = media.viewInsets.bottom;
        final landscape = orientation == Orientation.landscape;
        final tightHeight = size.height < 560;
        final horizontalInset = AppSize.space(context, landscape ? 10 : 16);
        final verticalInset = AppSize.space(context, landscape ? 8 : 18);
        final availableHeight =
            (size.height -
                    keyboardInset -
                    media.padding.vertical -
                    (verticalInset * 2))
                .clamp(160, size.height)
                .toDouble();
        final panelPadding = AppSize.space(
          context,
          landscape ? 12 : (tightHeight ? 14 : 24),
        );
        final contentMaxHeight = (availableHeight - (panelPadding * 2))
            .clamp(80, size.height)
            .toDouble();
        final gap = AppSize.space(context, tightHeight ? 12 : 22);
        final content = _GlassDialogContent(
          title: title,
          actions: actions,
          tightHeight: tightHeight,
          gap: gap,
          child: child,
        );

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: horizontalInset,
            vertical: verticalInset,
          ),
          child: Align(
            alignment: Alignment.center,
            child: GlassContainer(
              radius: 22,
              blur: 20,
              color: Colors.transparent,
              glassColor: Colors.transparent,
              backerColor: Colors.transparent,
              platformViewFallbackColor: Colors.transparent,
              border: Border.all(
                color: Colors.white.withValues(alpha: .32),
                width: 1.1,
              ),
              padding: EdgeInsets.all(panelPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: contentMaxHeight,
                ),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassDialogContent extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool tightHeight;
  final double gap;

  const _GlassDialogContent({
    required this.title,
    required this.child,
    required this.actions,
    required this.tightHeight,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    final titleText = CustomText(
      title,
      variant: tightHeight ? CustomTextStyle.title : CustomTextStyle.display,
    );
    final actionBar = actions.isEmpty
        ? null
        : Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: AppSize.space(context, 10),
              runSpacing: AppSize.space(context, 10),
              children: actions,
            ),
          );

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleText,
          SizedBox(height: gap),
          child,
          if (actionBar != null) ...[SizedBox(height: gap), actionBar],
        ],
      ),
    );
  }
}

void closeAppDialog<T>(BuildContext context, [T? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) Navigator.of(context).pop<T>(result);
  });
}

class PageFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget child;

  const PageFrame({
    super.key,
    required this.title,
    this.subtitle = '',
    this.actions = const [],
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 620;
        final needsFrameScroll =
            constraints.maxHeight.isFinite && constraints.maxHeight < 560;
        final frameHeight = constraints.maxHeight.isFinite
            ? (needsFrameScroll ? 560.0 : constraints.maxHeight)
            : 560.0;
        final basePadding = Breakpoints.pagePadding(context);
        final padding = basePadding.add(
          EdgeInsets.only(bottom: Breakpoints.compact(context) ? 92 : 0),
        );
        final frame = SizedBox(
          height: frameHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Breakpoints.maxWidth(context),
              ),
              child: Padding(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: tight
                              ? double.infinity
                              : constraints.maxWidth.clamp(280, 520).toDouble(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                title,
                                variant: CustomTextStyle.display,
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                CustomText(
                                  subtitle,
                                  variant: CustomTextStyle.subtitle,
                                  color: Colors.white.withValues(alpha: .74),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (actions.isNotEmpty)
                          Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        );
        return needsFrameScroll ? SingleChildScrollView(child: frame) : frame;
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      blur: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryTight = constraints.maxWidth < 220;
          final iconBox = Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .64)),
            ),
            child: Icon(icon, color: color),
          );
          final texts = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: veryTight
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              CustomText(
                label,
                variant: CustomTextStyle.label,
                color: Colors.white.withValues(alpha: .72),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              CustomText(
                value,
                variant: CustomTextStyle.title,
                fontWeight: FontWeight.w900,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );

          if (veryTight) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconBox,
                const SizedBox(height: 8),
                Flexible(child: texts),
              ],
            );
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(child: texts),
            ],
          );
        },
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              CustomText(
                title,
                variant: CustomTextStyle.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              CustomText(
                message,
                color: Colors.white.withValues(alpha: .74),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _activeAppSnack;

void showAppSnack(BuildContext context, String message) {
  final theme = Theme.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  _activeAppSnack?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final media = MediaQuery.of(overlayContext);
      return Positioned(
        left: 12,
        right: 12,
        bottom: media.viewInsets.bottom + media.padding.bottom + 12,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  radius: 20,
                  blur: 24,
                  color: Colors.white.withValues(alpha: .18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .34),
                    width: 1.1,
                  ),
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 34,
                          width: 34,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: .16,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .46),
                            ),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.primary,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomText(
                            message,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  _activeAppSnack = entry;
  Future<void>.delayed(const Duration(seconds: 4), () {
    if (entry.mounted) {
      entry.remove();
    }
    if (identical(_activeAppSnack, entry)) {
      _activeAppSnack = null;
    }
  });
}
