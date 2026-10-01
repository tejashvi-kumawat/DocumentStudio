import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

abstract final class DsTypography {
  /// [apple] applies SF-style optical tracking (tighter display sizes). The
  /// font family itself comes from the platform typography (SF on Apple).
  static TextTheme textTheme(Brightness brightness, {bool apple = false}) {
    final primary = brightness == Brightness.dark
        ? DsColors.textPrimaryDark
        : DsColors.textPrimaryLight;
    final secondary = DsColors.textSecondary(brightness);
    double track(double material, double sf) => apple ? sf : material;

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: track(-0.6, -0.8),
        height: 1.15,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: track(-0.3, -0.5),
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: track(-0.3, -0.45),
        height: 1.2,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: track(0, -0.35),
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: track(0, -0.2),
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: track(0, -0.1),
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        letterSpacing: track(0, -0.2),
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        letterSpacing: track(0, -0.1),
        color: primary,
      ),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: secondary),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: track(0, -0.05),
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: primary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: secondary,
      ),
    );
  }
}
