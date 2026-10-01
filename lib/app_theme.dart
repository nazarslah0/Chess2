import 'package:flutter/material.dart';

/// Visual system for Chess2: deep navy surfaces, electric blue actions,
/// restrained borders and large rounded cards inspired by the reference UI.
class Chess2Theme {
  static const Color navy = Color(0xFF07111F);
  static const Color surface = Color(0xFF0D1A2A);
  static const Color surface2 = Color(0xFF122338);
  static const Color blue = Color(0xFF238BFF);
  static const Color blue2 = Color(0xFF1266D6);
  static const Color text = Color(0xFFF4F7FB);
  static const Color muted = Color(0xFF9EADBF);
  static const Color border = Color(0xFF20334A);
  static const Color green = Color(0xFF39D98A);
  static const Color red = Color(0xFFFF5B63);
  static const Color orange = Color(0xFFFFB84D);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
      surface: surface,
      primary: blue,
      secondary: green,
      error: red,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: navy,
      canvasColor: navy,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: blue.withOpacity(.20),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: blue,
        thumbColor: blue,
        inactiveTrackColor: border,
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: blue,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
