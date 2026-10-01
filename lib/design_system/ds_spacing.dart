import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Layout spacing scale (4dp base). See [docs/DESIGN-SYSTEM.md].
abstract final class DsSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Material window size classes (width). Use these consistently for shell,
  /// Home / Tools / Settings density, and PDF viewer chrome.
  ///
  /// - compact: &lt; [breakpointCompact] (phone) — bottom nav, dense controls
  /// - medium: [breakpointCompact]–[breakpointExpanded] (large phone / small tablet)
  /// - expanded: ≥ [breakpointExpanded] (tablet / desktop) — side navigation
  static const double breakpointCompact = 600;
  static const double breakpointExpanded = 840;

  /// Page padding on phone-width shell tabs.
  static const double pagePaddingCompact = lg;

  /// App bar / bottom navigation height on compact chrome.
  static const double appBarHeightCompact = 56;
  static const double bottomNavHeight = 56;

  /// Compact control height band (40–48dp).
  static const double controlHeightCompact = 40;
  static const double controlHeightComfortable = 48;

  /// Max content width for Home, Tools hub, and Settings shell pages.
  /// Soft cap for very wide monitors; below this the column grows with the window.
  static const double contentMaxWidth = 1820;

  /// Narrower column for single-task tool forms (do not stretch edge-to-edge).
  static const double formMaxWidth = 960;

  /// Vertical gap between major sections on shell tab pages (Home, Tools, Settings).
  static const double shellSectionGap = xl;

  /// Default bottom padding for shell tab scroll views.
  static const double shellPageBottom = xxxl;

  /// Corner radii (Apple-like continuous corners).
  static const double radiusButton = 8;
  static const double radiusCard = 12;
  static const double radiusGrouped = 10;
  static const double radiusHero = 14;
  static const double radiusDialog = 14;
  static const double radiusSidebar = 12;

  /// Desktop window corner radius when not maximized (Linux custom frame).
  static const double radiusWindow = 10;

  /// Title bar / tab strip height on desktop with a custom window frame.
  static const double titleBarHeight = 40;

  /// Dense document / recent row height (Home lists).
  static const double documentRowHeight = 44;

  /// Compact touch target for phone chrome / dense tool rows (~40–48dp).
  static const double compactTouchTarget = 44;

  /// Soft red-tinted icon well for tool cards.
  static const double iconWellSize = 36;

  /// Narrower icon well on phone-width tool grids.
  static const double iconWellSizeCompact = 28;

  /// Horizontal inset for inset grouped lists (iOS Settings).
  static const double groupedListInset = lg;

  /// Home hero open card vertical padding.
  static const double heroVertical = xl;

  /// Workspace ribbon horizontal padding.
  static const double ribbonHorizontal = sm;

  /// Inspector section label spacing.
  static const double inspectorSectionGap = sm;

  /// Soft card shadow for light-mode tool grids (single layer, calm).
  static List<BoxShadow> cardShadowLight({double opacity = 0.06}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: opacity),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static BoxDecoration groupedInsetDecoration({
    required bool isDark,
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(radiusGrouped);
    return BoxDecoration(
      color: isDark ? DsColors.groupedCellDark : DsColors.groupedCellLight,
      borderRadius: radius,
      border: Border.all(
        color: isDark ? DsColors.borderDark : DsColors.borderLight,
        width: isDark ? 1 : 0.5,
      ),
      boxShadow: isDark ? null : cardShadowLight(opacity: 0.04),
    );
  }
}
