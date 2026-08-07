import 'package:flutter/material.dart';

/// Цветовая палитра и типографика в стилистике hh.ru (дизайн-система Magritte).
class HhColors {
  HhColors._();

  /// Фирменный красный hh.ru (логотип, основные действия).
  static const Color red = Color(0xFFD6001C);
  static const Color redHover = Color(0xFFB00019);
  static const Color redPressed = Color(0xFF8F0015);

  /// Поверхности и фон.
  static const Color pageBackground = Color(0xFFF4F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDEEF0);

  /// Текст.
  static const Color textPrimary = Color(0xFF232529);
  static const Color textSecondary = Color(0xFF768694);
  static const Color textMuted = Color(0xFFACB3BC);

  /// Границы и разделители.
  static const Color border = Color(0xFFE4E7EB);

  /// Акценты.
  static const Color blue = Color(0xFF0F62FE);
  static const Color green = Color(0xFF0BAF5C);
  static const Color amber = Color(0xFFEEAF3A);
}

class HhTheme {
  HhTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: HhColors.red,
      brightness: Brightness.light,
    ).copyWith(
      primary: HhColors.red,
      onPrimary: Colors.white,
      surface: HhColors.surface,
      onSurface: HhColors.textPrimary,
      surfaceContainerHighest: HhColors.surfaceMuted,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: HhColors.pageBackground,
      dividerColor: HhColors.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: HhColors.textPrimary,
        displayColor: HhColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HhColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: HhColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: HhColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HhColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HhColors.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: HhColors.surfaceMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return HhColors.redPressed;
            if (states.contains(WidgetState.hovered)) return HhColors.redHover;
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HhColors.blue,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HhColors.textPrimary,
          side: const BorderSide(color: HhColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: HhColors.surfaceMuted,
        side: BorderSide.none,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: HhColors.red,
      ),
    );
  }
}
