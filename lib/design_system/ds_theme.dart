import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/ds_typography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class DsTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: DsColors.primary,
      onPrimary: DsColors.onPrimary,
      secondary: DsColors.primaryDark,
      onSecondary: DsColors.onPrimary,
      secondaryContainer: Color(0xFFFFE5EA),
      onSecondaryContainer: DsColors.primaryDark,
      tertiary: DsColors.primary,
      onTertiary: DsColors.onPrimary,
      tertiaryContainer: Color(0xFFFFE5EA),
      onTertiaryContainer: DsColors.primaryDark,
      surface: DsColors.surfaceLight,
      onSurface: DsColors.textPrimaryLight,
      error: DsColors.error,
    );
    return _base(scheme, brightness: Brightness.light);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: DsColors.primary,
      onPrimary: DsColors.onPrimary,
      secondary: Color(0xFFFF8A9A),
      onSecondary: DsColors.textPrimaryDark,
      secondaryContainer: Color(0xFF5C1524),
      onSecondaryContainer: Color(0xFFFFCDD4),
      tertiary: Color(0xFFFF8A9A),
      onTertiary: DsColors.textPrimaryDark,
      tertiaryContainer: Color(0xFF5C1524),
      onTertiaryContainer: Color(0xFFFFCDD4),
      surface: DsColors.surfaceDark,
      onSurface: DsColors.textPrimaryDark,
      error: Color(0xFFF87171),
    );
    return _base(scheme, brightness: Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, {required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final apple = dsIsApplePlatform(defaultTargetPlatform);
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final menuSurface = isDark
        ? const Color(0xF21E293B)
        : const Color(0xF7FFFFFF);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: DsTypography.textTheme(brightness, apple: apple),
      // Apple controls highlight instead of rippling.
      // InkSparkle requires shaders/ink_sparkle.frag; use InkRipple on desktop.
      splashFactory: apple ? NoSplash.splashFactory : InkRipple.splashFactory,
      highlightColor: apple
          ? scheme.onSurface.withValues(alpha: 0.06)
          : null,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: DsColors.primary,
        scaffoldBackgroundColor: isDark
            ? DsColors.groupedBackgroundDark
            : DsColors.groupedBackgroundLight,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(apple ? 12 : 14),
        ),
        backgroundColor: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceLight,
        elevation: apple ? 12 : 6,
        titleTextStyle: TextStyle(
          fontSize: apple ? 15 : 18,
          fontWeight: FontWeight.w600,
          letterSpacing: apple ? -0.2 : 0,
          color: scheme.onSurface,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: menuSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        menuPadding: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(apple ? 8 : 10),
          side: BorderSide(color: border.withValues(alpha: 0.6), width: 0.5),
        ),
        textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 13, color: scheme.onSurface),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 5),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(apple ? 8 : 10),
              side: BorderSide(color: border.withValues(alpha: 0.6), width: 0.5),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xE6202633),
          borderRadius: BorderRadius.circular(apple ? 5 : 6),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 8 : 6,
        ),
        radius: const Radius.circular(4),
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.28),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return DsColors.primary;
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return DsColors.primary;
          return null;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: DsColors.primary,
        linearTrackColor: border,
        linearMinHeight: 3,
        borderRadius: BorderRadius.circular(2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsSpacing.radiusCard),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
          ),
        ),
      ),
      scaffoldBackgroundColor: isDark
          ? DsColors.groupedBackgroundDark
          : DsColors.groupedBackgroundLight,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceContainerLight,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDark ? DsColors.borderDark : DsColors.borderLight,
          ),
        ),
        color: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceLight,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return DsColors.primary;
            }
            return isDark
                ? DsColors.surfaceContainerDark
                : DsColors.surfaceLight;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return DsColors.onPrimary;
            }
            return scheme.onSurface;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: isDark ? DsColors.borderDark : DsColors.borderLight,
            ),
          ),
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DsColors.primary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return DsColors.primary.withValues(alpha: 0.45);
          }
          return null;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: DsColors.primary,
        thumbColor: DsColors.primary,
        overlayColor: DsColors.primary.withValues(alpha: 0.12),
        inactiveTrackColor: isDark
            ? DsColors.borderDark
            : DsColors.borderLight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? DsColors.borderDark : DsColors.borderLight,
      ),
    );
  }
}
