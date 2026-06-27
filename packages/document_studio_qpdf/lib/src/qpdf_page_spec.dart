/// Builds qpdf page-range strings from 1-based page numbers (e.g. `1,3,5-7`).
String buildQpdfPageSpec(Iterable<int> pages1Based) {
  final sorted = pages1Based.toSet().where((p) => p > 0).toList()..sort();
  if (sorted.isEmpty) {
    throw ArgumentError('No pages selected');
  }
  final parts = <String>[];
  var start = sorted.first;
  var prev = start;
  for (var i = 1; i < sorted.length; i++) {
    final p = sorted[i];
    if (p == prev + 1) {
      prev = p;
      continue;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    start = p;
    prev = p;
  }
  parts.add(start == prev ? '$start' : '$start-$prev');
  return parts.join(',');
}
