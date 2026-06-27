import 'package:document_studio/features/command_palette/ds_command_palette.dart';

/// Lightweight command ranking for [DS-SHELL-002] (prefix beats substring).
int commandPaletteMatchScore(CommandPaletteItem item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;

  final label = item.label.toLowerCase();
  if (label.startsWith(q)) return 100;
  if (label.contains(q)) return 80;

  final subtitle = item.subtitle.toLowerCase();
  if (subtitle.startsWith(q)) return 60;
  if (subtitle.contains(q)) return 40;

  var best = -1;
  for (final keyword in item.keywords) {
    final k = keyword.toLowerCase();
    if (k.startsWith(q)) {
      best = best < 50 ? 50 : best;
    } else if (k.contains(q)) {
      best = best < 30 ? 30 : best;
    }
  }
  return best;
}

List<CommandPaletteItem> filterRankedCommandPaletteItems(
  List<CommandPaletteItem> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;

  final scored = <({CommandPaletteItem item, int score})>[];
  for (final item in items) {
    final score = commandPaletteMatchScore(item, q);
    if (score >= 0) scored.add((item: item, score: score));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.item.label.compareTo(b.item.label);
  });
  return [for (final entry in scored) entry.item];
}
