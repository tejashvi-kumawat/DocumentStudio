enum AppLayoutSize { compact, medium, expanded }

AppLayoutSize layoutSizeForWidth(double width) {
  if (width >= 1024) return AppLayoutSize.expanded;
  if (width >= 600) return AppLayoutSize.medium;
  return AppLayoutSize.compact;
}
