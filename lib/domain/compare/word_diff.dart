import 'dart:math' as math;
import 'dart:typed_data';

enum DiffOp { equal, delete, insert }

/// Half-open token ranges. Equal hunks have equal lengths; delete hunks have an
/// empty b-range positioned where the deletion happened (and vice versa).
class DiffHunk {
  const DiffHunk(this.op, this.aStart, this.aEnd, this.bStart, this.bEnd);

  final DiffOp op;
  final int aStart;
  final int aEnd;
  final int bStart;
  final int bEnd;

  int get aLen => aEnd - aStart;
  int get bLen => bEnd - bStart;

  @override
  String toString() => '$op[$aStart,$aEnd)[$bStart,$bEnd)';
}

/// Diffs interned token sequences.
///
/// Patience diff first: common prefix/suffix are trimmed, tokens unique in both
/// sides become anchors (longest increasing subsequence), and the gaps between
/// anchors are diffed recursively. Gaps without unique anchors fall back to
/// Myers O((N+M)·D); when D exceeds [maxEditDistance] the gap is reported as a
/// single replacement so pathological inputs stay bounded.
List<DiffHunk> diffTokens(
  List<int> a,
  List<int> b, {
  int maxEditDistance = 2000,
}) {
  final out = _HunkBuilder();
  _diff(a, 0, a.length, b, 0, b.length, out, maxEditDistance);
  return out.hunks;
}

class _HunkBuilder {
  final hunks = <DiffHunk>[];

  void add(DiffOp op, int a0, int a1, int b0, int b1) {
    if (a0 == a1 && b0 == b1) return;
    if (hunks.isNotEmpty) {
      final last = hunks.last;
      if (last.op == op && last.aEnd == a0 && last.bEnd == b0) {
        hunks[hunks.length - 1] = DiffHunk(op, last.aStart, a1, last.bStart, b1);
        return;
      }
    }
    hunks.add(DiffHunk(op, a0, a1, b0, b1));
  }

  void change(int a0, int a1, int b0, int b1) {
    if (a1 > a0) add(DiffOp.delete, a0, a1, b0, b0);
    if (b1 > b0) add(DiffOp.insert, a1, a1, b0, b1);
  }
}

void _diff(
  List<int> a,
  int aLo,
  int aHi,
  List<int> b,
  int bLo,
  int bHi,
  _HunkBuilder out,
  int maxD,
) {
  var p = 0;
  while (aLo + p < aHi && bLo + p < bHi && a[aLo + p] == b[bLo + p]) {
    p++;
  }
  if (p > 0) out.add(DiffOp.equal, aLo, aLo + p, bLo, bLo + p);
  aLo += p;
  bLo += p;

  var s = 0;
  while (aHi - s > aLo && bHi - s > bLo && a[aHi - 1 - s] == b[bHi - 1 - s]) {
    s++;
  }
  final sufA = aHi - s;
  final sufB = bHi - s;

  if (aLo == sufA || bLo == sufB) {
    out.change(aLo, sufA, bLo, sufB);
  } else {
    final anchors = _patienceAnchors(a, aLo, sufA, b, bLo, sufB);
    if (anchors.isEmpty) {
      _myers(a, aLo, sufA, b, bLo, sufB, out, maxD);
    } else {
      var pa = aLo;
      var pb = bLo;
      for (final (ai, bi) in anchors) {
        _diff(a, pa, ai, b, pb, bi, out, maxD);
        out.add(DiffOp.equal, ai, ai + 1, bi, bi + 1);
        pa = ai + 1;
        pb = bi + 1;
      }
      _diff(a, pa, sufA, b, pb, sufB, out, maxD);
    }
  }
  if (s > 0) out.add(DiffOp.equal, sufA, aHi, sufB, bHi);
}

/// Tokens occurring exactly once in each range, reduced to the longest chain
/// that is increasing on both sides.
List<(int, int)> _patienceAnchors(
  List<int> a,
  int aLo,
  int aHi,
  List<int> b,
  int bLo,
  int bHi,
) {
  final countA = <int, int>{};
  final posA = <int, int>{};
  for (var i = aLo; i < aHi; i++) {
    final t = a[i];
    countA[t] = (countA[t] ?? 0) + 1;
    posA[t] = i;
  }
  final countB = <int, int>{};
  final posB = <int, int>{};
  for (var j = bLo; j < bHi; j++) {
    final t = b[j];
    if (countA[t] != 1) continue;
    countB[t] = (countB[t] ?? 0) + 1;
    posB[t] = j;
  }
  final pairs = <(int, int)>[];
  for (var i = aLo; i < aHi; i++) {
    final t = a[i];
    if (countA[t] == 1 && countB[t] == 1) pairs.add((i, posB[t]!));
  }
  if (pairs.isEmpty) return const [];

  // LIS on b positions (pairs already sorted by a), O(n log n).
  final tails = <int>[];
  final prev = List<int>.filled(pairs.length, -1);
  for (var k = 0; k < pairs.length; k++) {
    final v = pairs[k].$2;
    var lo = 0;
    var hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (pairs[tails[mid]].$2 < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[k] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(k);
    } else {
      tails[lo] = k;
    }
  }
  final chain = <(int, int)>[];
  var k = tails.last;
  while (k >= 0) {
    chain.add(pairs[k]);
    k = prev[k];
  }
  return chain.reversed.toList(growable: false);
}

void _myers(
  List<int> a,
  int aLo,
  int aHi,
  List<int> b,
  int bLo,
  int bHi,
  _HunkBuilder out,
  int maxD,
) {
  final n = aHi - aLo;
  final m = bHi - bLo;
  final limit = math.min(n + m, maxD);
  final off = limit + 1;
  final v = Int32List(2 * limit + 3);
  // trace[d] holds v before step d for k in [-(d+1), d+1].
  final trace = <Int32List>[];
  var found = -1;
  for (var d = 0; d <= limit && found < 0; d++) {
    trace.add(Int32List.fromList(v.sublist(off - d - 1, off + d + 2)));
    for (var k = -d; k <= d; k += 2) {
      var x = (k == -d || (k != d && v[off + k - 1] < v[off + k + 1]))
          ? v[off + k + 1]
          : v[off + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[aLo + x] == b[bLo + y]) {
        x++;
        y++;
      }
      v[off + k] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
  }
  if (found < 0) {
    out.change(aLo, aHi, bLo, bHi);
    return;
  }

  // Backtrack into reversed unit edits.
  final ops = <(DiffOp, int, int)>[];
  var x = n;
  var y = m;
  for (var d = found; d > 0; d--) {
    final vd = trace[d];
    int at(int k) => vd[k + d + 1];
    final k = x - y;
    final prevK =
        (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
    final prevX = at(prevK);
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.add((DiffOp.equal, x - 1, y - 1));
      x--;
      y--;
    }
    if (x == prevX) {
      ops.add((DiffOp.insert, x, prevY));
    } else {
      ops.add((DiffOp.delete, prevX, y));
    }
    x = prevX;
    y = prevY;
  }
  while (x > 0 && y > 0) {
    ops.add((DiffOp.equal, x - 1, y - 1));
    x--;
    y--;
  }
  for (var i = ops.length - 1; i >= 0; i--) {
    final (op, ox, oy) = ops[i];
    final ax = aLo + ox;
    final by = bLo + oy;
    switch (op) {
      case DiffOp.equal:
        out.add(op, ax, ax + 1, by, by + 1);
      case DiffOp.delete:
        out.add(op, ax, ax + 1, by, by);
      case DiffOp.insert:
        out.add(op, ax, ax, by, by + 1);
    }
  }
}
