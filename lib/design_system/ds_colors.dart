import 'package:flutter/material.dart';

abstract final class DsColors {
  static const primary = Color(0xFFE4002B);
  static const primaryDark = Color(0xFFC41230);
  static const onPrimary = Color(0xFFFFFFFF);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceContainerLight = Color(0xFFF8FAFC);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF64748B);
  static const borderLight = Color(0xFFE2E8F0);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);

  /// Alias used by Fill & Sign / validation chrome.
  static const danger = error;

  static const surfaceDark = Color(0xFF0F172A);
  static const surfaceContainerDark = Color(0xFF1E293B);
  static const textPrimaryDark = Color(0xFFF1F5F9);

  /// Slightly lifted from slate-400 for AA on grouped dark surfaces.
  static const textSecondaryDark = Color(0xFFA8B4C8);
  static const borderDark = Color(0xFF334155);

  /// iOS Settings–style screen backdrop (home grouped lists).
  static const groupedBackgroundLight = Color(0xFFF4F4F4);
  static const groupedBackgroundDark = Color(0xFF0B1220);

  /// Elevated inset group fill (vibrancy-adjacent flat surface).
  static const groupedCellLight = Color(0xFFFFFFFF);
  static const groupedCellDark = Color(0xFF1E293B);

  /// Window chrome (title bar / tab strip) behind the floating sidebar.
  static const windowChromeLight = Color(0xFFECECEE);
  static const windowChromeDark = Color(0xFF080E1A);

  /// Translucent sidebar material (vibrancy-adjacent over window chrome).
  static const sidebarLight = Color(0xB8FFFFFF);
  static const sidebarDark = Color(0x991E293B);

  static Color windowChrome(Brightness brightness) =>
      brightness == Brightness.dark ? windowChromeDark : windowChromeLight;

  static Color sidebar(Brightness brightness) =>
      brightness == Brightness.dark ? sidebarDark : sidebarLight;

  static Color border(Brightness brightness) =>
      brightness == Brightness.dark ? borderDark : borderLight;

  static Color textPrimary(Brightness brightness) =>
      brightness == Brightness.dark ? textPrimaryDark : textPrimaryLight;

  static Color groupedBackground(Brightness brightness) =>
      brightness == Brightness.dark
      ? groupedBackgroundDark
      : groupedBackgroundLight;

  static Color groupedCell(Brightness brightness) =>
      brightness == Brightness.dark ? groupedCellDark : groupedCellLight;

  static Color textSecondary(Brightness brightness) =>
      brightness == Brightness.dark ? textSecondaryDark : textSecondaryLight;
}
