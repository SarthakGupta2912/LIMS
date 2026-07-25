import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF7DEBFF);
  final glassFill = Colors.white.withValues(alpha: .13);
  final glassBorder = Colors.white.withValues(alpha: .24);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );
  final textTheme =
      GoogleFonts.poppinsTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
        bodyColor: const Color(0xFFF7FBFF),
        displayColor: const Color(0xFFF7FBFF),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: seed,
      surface: const Color(0xFF0F2226),
    ),
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: GoogleFonts.poppins().fontFamily,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Color(0xFFF7FBFF),
    ),
    cardTheme: CardThemeData(
      color: glassFill,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glassFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: .72)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: .48)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: seed, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: glassFill,
      selectedColor: seed.withValues(alpha: .20),
      disabledColor: Colors.white.withValues(alpha: .08),
      side: BorderSide(color: glassBorder),
      labelStyle: const TextStyle(
        color: Color(0xFFF7FBFF),
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Colors.white.withValues(alpha: .82),
      textColor: const Color(0xFFF7FBFF),
      tileColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(
        Colors.white.withValues(alpha: .08),
      ),
      dataRowColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? seed.withValues(alpha: .12)
            : Colors.transparent,
      ),
      dividerThickness: .6,
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: .18),
      thickness: .7,
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: seed),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: const Color(0xFF5EDCFF),
        foregroundColor: const Color(0xFF062026),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: .36)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size(44, 44),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: Colors.white.withValues(alpha: .12),
      indicatorColor: seed.withValues(alpha: .20),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? seed
              : Colors.white.withValues(alpha: .72),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
  );
}
