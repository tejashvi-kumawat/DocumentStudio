import 'package:document_studio/design_system/ds_spacing.dart';

/// Shared column counts for Home / Tools hub launch grids.
///
/// compact (&lt;600): 2 columns · medium (600–839): 3 · expanded: 3+
int homeToolGridCrossAxisCount(double width) {
  if (width >= DsSpacing.breakpointExpanded) return 3;
  if (width >= DsSpacing.breakpointCompact) return 3;
  // Phone / narrow: 2 columns; never a single full-width stack of giant tiles.
  return 2;
}

/// Aspect ratio for bordered home tool launch tiles.
double homeToolGridChildAspectRatio(double width) {
  final columns = homeToolGridCrossAxisCount(width);
  if (columns >= 3) return 3.6;
  return 3.2;
}

/// Case-insensitive label/subtitle match for the Tools hub search field.
bool homeToolMatchesQuery({
  required String label,
  required String subtitle,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return label.toLowerCase().contains(q) || subtitle.toLowerCase().contains(q);
}

/// Splits [tools] into rows of [columns] for bordered grid layouts.
List<List<T>> homeToolGridRows<T>(List<T> tools, int columns) {
  if (columns <= 0) return const [];
  final rows = <List<T>>[];
  for (var i = 0; i < tools.length; i += columns) {
    final end = (i + columns > tools.length) ? tools.length : i + columns;
    rows.add(tools.sublist(i, end));
  }
  return rows;
}
