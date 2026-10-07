import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/compare/compare_models.dart';

const _kHashes = 48;
const _kMatchThreshold = 0.1;

/// MinHash signature of a page's word-bigram set (unigrams for 1-word pages),
/// i.e. a text fingerprint whose agreement estimates Jaccard similarity.
/// Empty pages return null.
Uint32List? pageSignature(List<int> tokens) {
  if (tokens.isEmpty) return null;
  final sig = Uint32List(_kHashes)..fillRange(0, _kHashes, 0xFFFFFFFF);
  void feed(int shingle) {
    for (var h = 0; h < _kHashes; h++) {
      var x = (shingle ^ (0x9E3779B9 * (h + 1))) & 0xFFFFFFFF;
      x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
      x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
      x = x ^ (x >> 16);
      if (x < sig[h]) sig[h] = x;
    }
  }

  if (tokens.length == 1) {
    feed(tokens.first);
  } else {
    final seen = <int>{};
    for (var i = 0; i + 1 < tokens.length; i++) {
      final s = (tokens[i] * 1000003 + tokens[i + 1]) & 0x3FFFFFFF;
      if (seen.add(s)) feed(s);
    }
  }
  return sig;
}

/// Estimated Jaccard similarity of two pages.
double pageSimilarity(Uint32List? a, Uint32List? b) {
  if (a == null && b == null) return 0.5;
  if (a == null || b == null) return 0;
  var same = 0;
  for (var h = 0; h < _kHashes; h++) {
    if (a[h] == b[h]) same++;
  }
  return same / _kHashes;
}

/// Monotonic page alignment maximizing total similarity of matched pages
/// (Needleman–Wunsch with zero gap cost). Unmatched pages become
/// inserted/deleted rows; equally sized unmatched runs between two matches are
/// paired so a heavily rewritten page is still diffed rather than reported as
/// delete + insert.
List<ComparePagePair> alignPages(List<Uint32List?> a, List<Uint32List?> b) {
  final n = a.length;
  final m = b.length;
  if (n == 0 || m == 0) {
    return [
      for (var i = 0; i < n; i++) ComparePagePair(i, null),
      for (var j = 0; j < m; j++) ComparePagePair(null, j),
    ];
  }
  if (n == m) {
    var diagonal = true;
    for (var i = 0; i < n && diagonal; i++) {
      if (pageSimilarity(a[i], b[i]) < 0.5) diagonal = false;
    }
    if (diagonal) return [for (var i = 0; i < n; i++) ComparePagePair(i, i)];
  }
  if (n * m > 16000000) {
    return _pairGaps([
      for (var i = 0; i < math.max(n, m); i++)
        ComparePagePair(i < n ? i : null, i < m ? i : null),
    ]);
  }

  // Band limit for large documents keeps the DP near-linear.
  final band = n * m > 1000000 ? (n - m).abs() + 60 : 1 << 30;
  final w = m + 1;
  final score = Float32List((n + 1) * w);
  final dir = Uint8List(
    (n + 1) * w,
  ); // 0 diag, 1 up (delete a), 2 left (insert b)
  for (var i = 1; i <= n; i++) {
    dir[i * w] = 1;
  }
  for (var j = 1; j <= m; j++) {
    dir[j] = 2;
  }
  for (var i = 1; i <= n; i++) {
    final center = (i * m / n).round();
    for (var j = 1; j <= m; j++) {
      final up = score[(i - 1) * w + j];
      final left = score[i * w + j - 1];
      var best = up;
      var d = 1;
      if (left > best) {
        best = left;
        d = 2;
      }
      if ((j - center).abs() <= band) {
        final sim = pageSimilarity(a[i - 1], b[j - 1]);
        if (sim >= _kMatchThreshold) {
          final diag = score[(i - 1) * w + j - 1] + sim + 0.05;
          if (diag >= best) {
            best = diag;
            d = 0;
          }
        }
      }
      score[i * w + j] = best;
      dir[i * w + j] = d;
    }
  }

  final rows = <ComparePagePair>[];
  var i = n;
  var j = m;
  while (i > 0 || j > 0) {
    final d = dir[i * w + j];
    if (i > 0 && j > 0 && d == 0) {
      rows.add(ComparePagePair(i - 1, j - 1));
      i--;
      j--;
    } else if (i > 0 && (d == 1 || j == 0)) {
      rows.add(ComparePagePair(i - 1, null));
      i--;
    } else {
      rows.add(ComparePagePair(null, j - 1));
      j--;
    }
  }
  return _pairGaps(rows.reversed.toList());
}

/// Pairs pages that were deleted at one position and inserted at another but
/// are still similar ([minSimilarity]), i.e. pages that moved. Greedy by
/// similarity, one-to-one. Returns old page -> new page.
Map<int, int> detectMovedPages(
  List<ComparePagePair> rows,
  List<Uint32List?> a,
  List<Uint32List?> b, {
  double minSimilarity = 0.5,
}) {
  final dels = [
    for (final r in rows)
      if (r.b == null) r.a!,
  ];
  final ins = [
    for (final r in rows)
      if (r.a == null) r.b!,
  ];
  if (dels.isEmpty || ins.isEmpty || dels.length * ins.length > 250000) {
    return const {};
  }
  final cand = <(double, int, int)>[];
  for (final i in dels) {
    if (a[i] == null) continue;
    for (final j in ins) {
      final s = pageSimilarity(a[i], b[j]);
      if (s >= minSimilarity) cand.add((s, i, j));
    }
  }
  cand.sort((x, y) => y.$1.compareTo(x.$1));
  final out = <int, int>{};
  final usedB = <int>{};
  for (final (_, i, j) in cand) {
    if (out.containsKey(i) || usedB.contains(j)) continue;
    out[i] = j;
    usedB.add(j);
  }
  return out;
}

/// Within each run between matched rows, deletions are listed before
/// insertions; equal-length runs are zipped into modified-page pairs.
List<ComparePagePair> _pairGaps(List<ComparePagePair> rows) {
  final out = <ComparePagePair>[];
  var k = 0;
  while (k < rows.length) {
    if (rows[k].a != null && rows[k].b != null) {
      out.add(rows[k++]);
      continue;
    }
    final dels = <int>[];
    final ins = <int>[];
    while (k < rows.length && (rows[k].a == null || rows[k].b == null)) {
      final r = rows[k++];
      if (r.a != null) dels.add(r.a!);
      if (r.b != null) ins.add(r.b!);
    }
    if (dels.length == ins.length) {
      for (var t = 0; t < dels.length; t++) {
        out.add(ComparePagePair(dels[t], ins[t]));
      }
    } else {
      for (final d in dels) {
        out.add(ComparePagePair(d, null));
      }
      for (final s in ins) {
        out.add(ComparePagePair(null, s));
      }
    }
  }
  return out;
}
