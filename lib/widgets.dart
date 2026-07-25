import 'package:flutter/material.dart';

import 'app/responsive.dart';

enum CustomTextStyle { display, title, subtitle, body, label, caption }

class CustomText extends StatelessWidget {
  final String text;
  final CustomTextStyle variant;
  final Color? color;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const CustomText(
    this.text, {
    super.key,
    this.variant = CustomTextStyle.body,
    this.color,
    this.fontWeight,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final base = switch (variant) {
      CustomTextStyle.display => 30.0,
      CustomTextStyle.title => 20.0,
      CustomTextStyle.subtitle => 16.0,
      CustomTextStyle.body => 14.0,
      CustomTextStyle.label => 13.0,
      CustomTextStyle.caption => 12.0,
    };
    final weight =
        fontWeight ??
        switch (variant) {
          CustomTextStyle.display => FontWeight.w900,
          CustomTextStyle.title => FontWeight.w800,
          CustomTextStyle.subtitle => FontWeight.w600,
          CustomTextStyle.body => FontWeight.w500,
          CustomTextStyle.label => FontWeight.w700,
          CustomTextStyle.caption => FontWeight.w500,
        };

    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: AppSize.text(context, base),
        fontWeight: weight,
        color: color ?? const Color(0xFFF7FBFF),
        height: 1.25,
        letterSpacing: 0,
      ),
    );
  }
}

class CustomSelectableText extends StatelessWidget {
  final String text;
  final CustomTextStyle variant;
  final Color? color;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final int? maxLines;

  const CustomSelectableText(
    this.text, {
    super.key,
    this.variant = CustomTextStyle.body,
    this.color,
    this.fontWeight,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final base = switch (variant) {
      CustomTextStyle.display => 30.0,
      CustomTextStyle.title => 20.0,
      CustomTextStyle.subtitle => 16.0,
      CustomTextStyle.body => 14.0,
      CustomTextStyle.label => 13.0,
      CustomTextStyle.caption => 12.0,
    };
    final weight =
        fontWeight ??
        switch (variant) {
          CustomTextStyle.display => FontWeight.w900,
          CustomTextStyle.title => FontWeight.w800,
          CustomTextStyle.subtitle => FontWeight.w600,
          CustomTextStyle.body => FontWeight.w500,
          CustomTextStyle.label => FontWeight.w700,
          CustomTextStyle.caption => FontWeight.w500,
        };

    return SelectableText(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: AppSize.text(context, base),
        fontWeight: weight,
        color: color ?? const Color(0xFFF7FBFF),
        height: 1.25,
        letterSpacing: 0,
      ),
    );
  }
}

class ResponsiveGap extends StatelessWidget {
  final double size;
  final Axis axis;

  const ResponsiveGap(this.size, {super.key, this.axis = Axis.vertical});

  @override
  Widget build(BuildContext context) {
    final value = AppSize.space(context, size);
    return SizedBox(
      width: axis == Axis.horizontal ? value : null,
      height: axis == Axis.vertical ? value : null,
    );
  }
}
