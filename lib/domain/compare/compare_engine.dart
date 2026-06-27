import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/domain/compare/page_alignment.dart';
import 'package:document_studio/domain/compare/word_diff.dart';

/// Pure-Dart compare pipeline; run it off the UI isolate (see
/// `runCompareInIsolate`).
///
/// 1. Interns normalized words and aligns pages by MinHash similarity of
///    their text fingerprints (image hashes for text-less pages), then pairs
///    deleted/inserted pages that are still similar as moved pages.
/// 2. Diffs the word streams of aligned pages as one document-level sequence
///    (so text reflowing across a page break is not a change).
/// 3. Reports formatting changes on equal words, and image / annotation /
///    page-level changes per aligned pair.
CompareResult computeCompare(
  CompareDocData oldDoc,
  CompareDocData newDoc, {
  void Function(double progress)? onProgress,
}) {
  final sw = Stopwatch()..start();
  final intern = <String, int>{};
  int tok(String s) => intern.putIfAbsent(s, () => intern.length);
  List<int> tokensOf(ComparePageData p) => [
        for (final w in p.words) tok(normalizeCompareWord(w.text)),
      ];
  Uint32List? signatureOf(ComparePageData p, List<int> tokens) {
    if (tokens.isNotEmpty) return pageSignature(tokens);
    final imgs = [
      for (final im in p.images)
        tok('\u0000img:${im.hash}:${im.pixelWidth}x${im.pixelHeight}'),
    ];
    return pageSignature(imgs);
  }

  final aTok = [for (final p in oldDoc.pages) tokensOf(p)];
  final bTok = [for (final p in newDoc.pages) tokensOf(p)];
  final aSig = [
    for (var i = 0; i < aTok.length; i++) signatureOf(oldDoc.pages[i], aTok[i]),
  ];
  final bSig = [
    for (var i = 0; i < bTok.length; i++) signatureOf(newDoc.pages[i], bTok[i]),
  ];
  onProgress?.call(0.05);
  final rows = alignPages(aSig, bSig);
  final moved = detectMovedPages(rows, aSig, bSig);
  onProgress?.call(0.15);
  final rowOfA = <int, int>{};
  final rowOfB = <int, int>{};
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].a != null) rowOfA[rows[i].a!] = i;
    if (rows[i].b != null) rowOfB[rows[i].b!] = i;
  }
  var lastReported = 0.15;
  void report(double p) {
    if (onProgress == null || p - lastReported < 0.01) return;
    lastReported = p;
    onProgress(p);
  }

  // Word streams over aligned pages only, diffed pair by pair (small ranges
  // keep patience anchors plentiful and Myers bounded).
  final aStream = <int>[];
  final bStream = <int>[];
  final aRef = <_WordRef>[];
  final bRef = <_WordRef>[];
  final hunks = <DiffHunk>[];
  var prevPairEnd = -1;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    report(0.15 + 0.7 * r / rows.length);
    if (row.a == null || row.b == null) continue;
    final pa = row.a!;
    final pb = row.b!;
    final a0 = aStream.length;
    final b0 = bStream.length;
    for (var k = 0; k < aTok[pa].length; k++) {
      aStream.add(aTok[pa][k]);
      aRef.add(_WordRef(pa, k));
    }
    for (var k = 0; k < bTok[pb].length; k++) {
      bStream.add(bTok[pb][k]);
      bRef.add(_WordRef(pb, k));
    }
    final firstOfPair = hunks.length;
    for (final h in diffTokens(aTok[pa], bTok[pb])) {
      hunks.add(DiffHunk(
          h.op, a0 + h.aStart, a0 + h.aEnd, b0 + h.bStart, b0 + h.bEnd));
    }
    if (prevPairEnd >= 0) {
      _cancelReflow(hunks, prevPairEnd, firstOfPair, aStream, bStream);
    }
    prevPairEnd = hunks.length > firstOfPair ? hunks.length - 1 : -1;
  }
  hunks.removeWhere((h) => h.aLen == 0 && h.bLen == 0);

  final formatting = oldDoc.hasFontInfo && newDoc.hasFontInfo;
  final drafts = <_Draft>[];
  _collectTextChanges(hunks, oldDoc, newDoc, aRef, bRef, rowOfA, rowOfB, drafts);
  if (formatting) {
    _collectFormatting(hunks, oldDoc, newDoc, aRef, bRef, rowOfA, drafts);
  }

  // Moved pages: diffed as their own pair so edits inside them still show.
  for (final MapEntry(key: pa, value: pb) in moved.entries) {
    final ar = [for (var k = 0; k < aTok[pa].length; k++) _WordRef(pa, k)];
    final br = [for (var k = 0; k < bTok[pb].length; k++) _WordRef(pb, k)];
    final mh = diffTokens(aTok[pa], bTok[pb]);
    _collectTextChanges(mh, oldDoc, newDoc, ar, br, rowOfA, rowOfB, drafts);
    if (formatting) {
      _collectFormatting(mh, oldDoc, newDoc, ar, br, rowOfA, drafts);
    }
    _collectImages(rowOfA[pa]!, oldDoc.pages[pa], newDoc.pages[pb], drafts);
    _collectAnnots(rowOfA[pa]!, oldDoc.pages[pa], newDoc.pages[pb], drafts);
  }
  report(0.9);

  const full = [NormRect(0, 0, 1, 1)];
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    if (row.a == null) {
      if (moved.containsValue(row.b)) continue;
      final p = newDoc.pages[row.b!];
      drafts.add(_Draft(
        CompareCategory.pages,
        CompareChangeKind.inserted,
        r,
        0,
        newText: 'New page ${row.b! + 1} (${_summary(p)})',
        bRects: {row.b!: full},
        bPage: row.b,
      ));
    } else if (row.b == null) {
      final to = moved[row.a];
      final p = oldDoc.pages[row.a!];
      if (to != null) {
        drafts.add(_Draft(
          CompareCategory.pages,
          CompareChangeKind.moved,
          r,
          0,
          detail: 'Old page ${row.a! + 1} is now page ${to + 1}',
          aRects: {row.a!: full},
          bRects: {to: full},
          aPage: row.a,
          bPage: to,
        ));
        continue;
      }
      drafts.add(_Draft(
        CompareCategory.pages,
        CompareChangeKind.deleted,
        r,
        0,
        oldText: 'Old page ${row.a! + 1} (${_summary(p)})',
        aRects: {row.a!: full},
        aPage: row.a,
      ));
    } else {
      final pa = oldDoc.pages[row.a!];
      final pb = newDoc.pages[row.b!];
      if ((pa.widthPt - pb.widthPt).abs() > 1.5 ||
          (pa.heightPt - pb.heightPt).abs() > 1.5) {
        drafts.add(_Draft(
          CompareCategory.formatting,
          CompareChangeKind.changed,
          r,
          0,
          detail: 'Page size ${_pt(pa.widthPt)}×${_pt(pa.heightPt)} → '
              '${_pt(pb.widthPt)}×${_pt(pb.heightPt)} pt',
          aRects: {row.a!: full},
          bRects: {row.b!: full},
          aPage: row.a,
          bPage: row.b,
        ));
      }
      _collectImages(r, pa, pb, drafts);
      _collectAnnots(r, pa, pb, drafts);
    }
  }

  drafts.sort((x, y) {
    final c = x.row.compareTo(y.row);
    return c != 0 ? c : x.y.compareTo(y.y);
  });
  final changes = [
    for (var i = 0; i < drafts.length; i++) drafts[i].build(i),
  ];
  sw.stop();
  onProgress?.call(1);
  return CompareResult(
    oldDoc: oldDoc,
    newDoc: newDoc,
    rows: rows,
    changes: changes,
    elapsed: sw.elapsed,
    movedAtoB: moved,
  );
}

/// Canonical form used for equality: typographic variants are folded so that
/// re-exported documents don't produce spurious differences.
String normalizeCompareWord(String w) {
  if (w.codeUnits.every((c) => c < 0x80)) return w;
  final sb = StringBuffer();
  for (final r in w.runes) {
    switch (r) {
      case 0x2018 || 0x2019 || 0x201A || 0x2032:
        sb.write("'");
      case 0x201C || 0x201D || 0x201E || 0x2033:
        sb.write('"');
      case 0x2010 || 0x2011 || 0x2012 || 0x2013 || 0x2212:
        sb.write('-');
      case 0x2014 || 0x2015:
        sb.write('--');
      case 0xFB00:
        sb.write('ff');
      case 0xFB01:
        sb.write('fi');
      case 0xFB02:
        sb.write('fl');
      case 0xFB03:
        sb.write('ffi');
      case 0xFB04:
        sb.write('ffl');
      case 0x00AD || 0x200C || 0x200D:
        break;
      case 0x2026:
        sb.write('...');
      default:
        sb.writeCharCode(r);
    }
  }
  return sb.toString();
}

/// Text that moved across a page break (deleted at the end of one page pair
/// and inserted at the start of the next, or vice versa) is reflow, not a
/// change: the two hunks become one cross-page equal hunk.
void _cancelReflow(
  List<DiffHunk> hunks,
  int tailIndex,
  int headIndex,
  List<int> a,
  List<int> b,
) {
  if (tailIndex < 0 || headIndex >= hunks.length) return;
  final tail = hunks[tailIndex];
  final head = hunks[headIndex];
  bool same(int as, int ae, int bs, int be) {
    if (ae - as != be - bs || ae == as) return false;
    for (var k = 0; k < ae - as; k++) {
      if (a[as + k] != b[bs + k]) return false;
    }
    return true;
  }

  const empty = DiffHunk(DiffOp.equal, 0, 0, 0, 0);
  if (tail.op == DiffOp.delete &&
      head.op == DiffOp.insert &&
      same(tail.aStart, tail.aEnd, head.bStart, head.bEnd)) {
    hunks[tailIndex] =
        DiffHunk(DiffOp.equal, tail.aStart, tail.aEnd, head.bStart, head.bEnd);
    hunks[headIndex] = empty;
  } else if (tail.op == DiffOp.insert &&
      head.op == DiffOp.delete &&
      same(head.aStart, head.aEnd, tail.bStart, tail.bEnd)) {
    hunks[tailIndex] =
        DiffHunk(DiffOp.equal, head.aStart, head.aEnd, tail.bStart, tail.bEnd);
    hunks[headIndex] = empty;
  }
}

class _WordRef {
  const _WordRef(this.page, this.word);
  final int page;
  final int word;
}

class _Draft {
  _Draft(
    this.category,
    this.kind,
    this.row,
    this.y, {
    this.oldText = '',
    this.newText = '',
    this.detail,
    this.aRects = const {},
    this.bRects = const {},
    this.aPage,
    this.bPage,
  });

  final CompareCategory category;
  final CompareChangeKind kind;
  final int row;
  final double y;
  final String oldText;
  final String newText;
  final String? detail;
  final Map<int, List<NormRect>> aRects;
  final Map<int, List<NormRect>> bRects;
  final int? aPage;
  final int? bPage;

  CompareChange build(int id) => CompareChange(
        id: id,
        category: category,
        kind: kind,
        row: row,
        oldText: oldText,
        newText: newText,
        detail: detail,
        aRects: aRects,
        bRects: bRects,
        aPage: aPage,
        bPage: bPage,
      );
}

String _pt(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

String _summary(ComparePageData p) {
  final n = p.words.length;
  if (n == 0) return p.images.isEmpty ? 'blank' : '${p.images.length} image(s)';
  return '$n word${n == 1 ? '' : 's'}';
}

String _orNone(String s) => s.isEmpty ? '(none)' : s;

String _clip(String s, [int max = 400]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Merges word boxes into per-line boxes, grouped by page.
Map<int, List<NormRect>> _lineRects(
  Iterable<_WordRef> refs,
  CompareDocData doc,
) {
  final out = <int, List<NormRect>>{};
  NormRect? cur;
  var curPage = -1;
  void push() {
    if (cur != null) (out[curPage] ??= []).add(cur!.inflate(0.0015));
    cur = null;
  }

  for (final ref in refs) {
    final r = doc.pages[ref.page].words[ref.word].rect;
    if (r.area <= 0) continue;
    final c = cur;
    if (c != null && ref.page == curPage) {
      final overlap = math.min(c.b, r.b) - math.max(c.t, r.t);
      final h = math.min(c.height, r.height);
      final sameLine = h > 0 && overlap >= h * 0.5;
      if (sameLine && r.l >= c.l - 0.01 && r.l - c.r < 0.06) {
        cur = c.union(r);
        continue;
      }
    }
    push();
    cur = r;
    curPage = ref.page;
  }
  push();
  return out;
}

/// Thin caret marking where text was inserted / removed on the other side.
Map<int, List<NormRect>> _caret(
  List<_WordRef> refs,
  int at,
  CompareDocData doc,
) {
  if (refs.isEmpty) return const {};
  final after = at > 0;
  final ref = refs[math.min(after ? at - 1 : at, refs.length - 1)];
  final r = doc.pages[ref.page].words[ref.word].rect;
  if (r.area <= 0) return const {};
  final x = after ? r.r + 0.001 : r.l - 0.001;
  return {
    ref.page: [NormRect(x - 0.0015, r.t - 0.002, x + 0.0015, r.b + 0.002)],
  };
}

void _collectTextChanges(
  List<DiffHunk> hunks,
  CompareDocData a,
  CompareDocData b,
  List<_WordRef> aRef,
  List<_WordRef> bRef,
  Map<int, int> rowOfA,
  Map<int, int> rowOfB,
  List<_Draft> out,
) {
  // Group change hunks, bridging single-word equal islands so a rewritten
  // phrase reads as one replacement rather than fragments.
  final groups = <(int, int, int, int)>[];
  int? a0, a1, b0, b1;
  for (var h = 0; h < hunks.length; h++) {
    final hk = hunks[h];
    if (hk.op == DiffOp.equal) {
      final bridge = a0 != null &&
          hk.aLen == 1 &&
          h + 1 < hunks.length &&
          hunks[h + 1].op != DiffOp.equal;
      if (bridge) continue;
      if (a0 != null) groups.add((a0, a1!, b0!, b1!));
      a0 = a1 = b0 = b1 = null;
      continue;
    }
    a0 ??= hk.aStart;
    b0 ??= hk.bStart;
    a1 = hk.aEnd;
    b1 = hk.bEnd;
  }
  if (a0 != null) groups.add((a0, a1!, b0!, b1!));

  for (final (ga0, ga1, gb0, gb1) in groups) {
    final aLen = ga1 - ga0;
    final bLen = gb1 - gb0;
    final kind = aLen == 0
        ? CompareChangeKind.inserted
        : bLen == 0
            ? CompareChangeKind.deleted
            : CompareChangeKind.replaced;
    String join(List<_WordRef> refs, CompareDocData d, int s, int e) =>
        _clip(refs
            .sublist(s, e)
            .map((r) => d.pages[r.page].words[r.word].text)
            .join(' '));
    final aRects = aLen > 0
        ? _lineRects(aRef.sublist(ga0, ga1), a)
        : _caret(aRef, ga0, a);
    final bRects = bLen > 0
        ? _lineRects(bRef.sublist(gb0, gb1), b)
        : _caret(bRef, gb0, b);
    final aPage = aLen > 0
        ? aRef[ga0].page
        : (aRects.isEmpty ? null : aRects.keys.first);
    final bPage = bLen > 0
        ? bRef[gb0].page
        : (bRects.isEmpty ? null : bRects.keys.first);
    final row = aPage != null
        ? rowOfA[aPage]!
        : bPage != null
            ? rowOfB[bPage]!
            : 0;
    final firstRect = (aRects[aPage] ?? bRects[bPage])?.first;
    out.add(_Draft(
      CompareCategory.text,
      kind,
      row,
      firstRect?.t ?? 0,
      oldText: aLen > 0 ? join(aRef, a, ga0, ga1) : '',
      newText: bLen > 0 ? join(bRef, b, gb0, gb1) : '',
      aRects: aRects,
      bRects: bRects,
      aPage: aPage,
      bPage: bPage,
    ));
  }
}

String _fontKey(String f) {
  var s = f.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  for (final suffix in ['psmt', 'mt', 'ps']) {
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      break;
    }
  }
  return s;
}

bool _colorDiffers(int x, int y) {
  final dr = ((x >> 16) & 0xFF) - ((y >> 16) & 0xFF);
  final dg = ((x >> 8) & 0xFF) - ((y >> 8) & 0xFF);
  final db = (x & 0xFF) - (y & 0xFF);
  return dr.abs() + dg.abs() + db.abs() > 60;
}

String _hex(int c) =>
    '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _formatDetail(CompareWord x, CompareWord y) {
  final parts = <String>[];
  if (x.font.isNotEmpty &&
      y.font.isNotEmpty &&
      _fontKey(x.font) != _fontKey(y.font)) {
    parts.add('Font ${x.font} → ${y.font}');
  }
  if ((x.size - y.size).abs() > 0.6) {
    parts.add('Size ${_pt(x.size)} → ${_pt(y.size)} pt');
  }
  if (_colorDiffers(x.color, y.color)) {
    parts.add('Color ${_hex(x.color)} → ${_hex(y.color)}');
  }
  return parts.join(' · ');
}

void _collectFormatting(
  List<DiffHunk> hunks,
  CompareDocData a,
  CompareDocData b,
  List<_WordRef> aRef,
  List<_WordRef> bRef,
  Map<int, int> rowOfA,
  List<_Draft> out,
) {
  var start = -1;
  var startB = -1;
  var end = -1;
  var detail = '';
  void flush() {
    if (start < 0) return;
    final bEnd = startB + (end - start);
    final aRects = _lineRects(aRef.sublist(start, end), a);
    final bRects = _lineRects(bRef.sublist(startB, bEnd), b);
    final aPage = aRef[start].page;
    final text = _clip(aRef
        .sublist(start, end)
        .map((r) => a.pages[r.page].words[r.word].text)
        .join(' '));
    out.add(_Draft(
      CompareCategory.formatting,
      CompareChangeKind.changed,
      rowOfA[aPage]!,
      aRects[aPage]?.first.t ?? 0,
      oldText: text,
      newText: text,
      detail: detail,
      aRects: aRects,
      bRects: bRects,
      aPage: aPage,
      bPage: bRef[startB].page,
    ));
    start = -1;
  }

  for (final h in hunks) {
    if (h.op != DiffOp.equal) {
      flush();
      continue;
    }
    for (var k = 0; k < h.aLen; k++) {
      final ia = h.aStart + k;
      final ib = h.bStart + k;
      final wa = a.pages[aRef[ia].page].words[aRef[ia].word];
      final wb = b.pages[bRef[ib].page].words[bRef[ib].word];
      final d = _formatDetail(wa, wb);
      if (start >= 0 &&
          (d != detail ||
              ia != end ||
              aRef[ia].page != aRef[start].page ||
              bRef[ib].page != bRef[startB].page)) {
        flush();
      }
      if (d.isEmpty) continue;
      if (start < 0) {
        start = ia;
        startB = ib;
        detail = d;
      }
      end = ia + 1;
    }
  }
  flush();
}

void _collectImages(
  int row,
  ComparePageData pa,
  ComparePageData pb,
  List<_Draft> out,
) {
  final pairs = _greedyMatch(
    pa.images.map((e) => e.rect).toList(),
    pb.images.map((e) => e.rect).toList(),
    (i, j) => true,
  );
  final usedA = <int>{};
  final usedB = <int>{};
  for (final (i, j) in pairs) {
    usedA.add(i);
    usedB.add(j);
    final x = pa.images[i];
    final y = pb.images[j];
    final moved = x.rect.iou(y.rect) < 0.9;
    final resampled = (x.pixelWidth != y.pixelWidth ||
            x.pixelHeight != y.pixelHeight) &&
        x.pixelWidth > 0 &&
        y.pixelWidth > 0;
    final content = x.hash != 0 && y.hash != 0 && x.hash != y.hash;
    if (!moved && !resampled && !content) continue;
    out.add(_Draft(
      CompareCategory.images,
      content ? CompareChangeKind.replaced : CompareChangeKind.changed,
      row,
      x.rect.t,
      detail: [
        if (content) 'Image content differs',
        if (moved) 'Moved or resized',
        if (resampled)
          'Pixels ${x.pixelWidth}×${x.pixelHeight} → ${y.pixelWidth}×${y.pixelHeight}',
      ].join(' · '),
      aRects: {pa.index: [x.rect]},
      bRects: {pb.index: [y.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
  for (var i = 0; i < pa.images.length; i++) {
    if (usedA.contains(i)) continue;
    final x = pa.images[i];
    out.add(_Draft(
      CompareCategory.images,
      CompareChangeKind.deleted,
      row,
      x.rect.t,
      detail: x.pixelWidth > 0 ? '${x.pixelWidth}×${x.pixelHeight} px' : null,
      aRects: {pa.index: [x.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
  for (var j = 0; j < pb.images.length; j++) {
    if (usedB.contains(j)) continue;
    final y = pb.images[j];
    out.add(_Draft(
      CompareCategory.images,
      CompareChangeKind.inserted,
      row,
      y.rect.t,
      detail: y.pixelWidth > 0 ? '${y.pixelWidth}×${y.pixelHeight} px' : null,
      bRects: {pb.index: [y.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
}

void _collectAnnots(
  int row,
  ComparePageData pa,
  ComparePageData pb,
  List<_Draft> out,
) {
  final pairs = _greedyMatch(
    pa.annots.map((e) => e.rect).toList(),
    pb.annots.map((e) => e.rect).toList(),
    (i, j) => pa.annots[i].subtype == pb.annots[j].subtype,
  );
  final usedA = <int>{};
  final usedB = <int>{};
  for (final (i, j) in pairs) {
    usedA.add(i);
    usedB.add(j);
    final x = pa.annots[i];
    final y = pb.annots[j];
    final moved = x.rect.iou(y.rect) < 0.8;
    final edited = x.contents.trim() != y.contents.trim();
    final retarget = x.target != y.target;
    if (!moved && !edited && !retarget) continue;
    out.add(_Draft(
      CompareCategory.annotations,
      CompareChangeKind.changed,
      row,
      x.rect.t,
      oldText: _clip(edited ? x.contents : x.target, 200),
      newText: _clip(edited ? y.contents : y.target, 200),
      detail: [
        x.subtypeLabel,
        if (moved) 'moved',
        if (edited) 'contents edited',
        if (retarget) 'target ${_orNone(x.target)} → ${_orNone(y.target)}',
      ].join(' · '),
      aRects: {pa.index: [x.rect]},
      bRects: {pb.index: [y.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
  for (var i = 0; i < pa.annots.length; i++) {
    if (usedA.contains(i)) continue;
    final x = pa.annots[i];
    out.add(_Draft(
      CompareCategory.annotations,
      CompareChangeKind.deleted,
      row,
      x.rect.t,
      oldText: _clip(x.contents.isNotEmpty ? x.contents : x.target, 200),
      detail: x.subtypeLabel,
      aRects: {pa.index: [x.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
  for (var j = 0; j < pb.annots.length; j++) {
    if (usedB.contains(j)) continue;
    final y = pb.annots[j];
    out.add(_Draft(
      CompareCategory.annotations,
      CompareChangeKind.inserted,
      row,
      y.rect.t,
      newText: _clip(y.contents.isNotEmpty ? y.contents : y.target, 200),
      detail: y.subtypeLabel,
      bRects: {pb.index: [y.rect]},
      aPage: pa.index,
      bPage: pb.index,
    ));
  }
}

/// Greedy one-to-one matching by overlap, falling back to center distance for
/// objects that moved without overlapping.
List<(int, int)> _greedyMatch(
  List<NormRect> a,
  List<NormRect> b,
  bool Function(int i, int j) compatible,
) {
  if (a.isEmpty || b.isEmpty) return const [];
  final cand = <(double, int, int)>[];
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < b.length; j++) {
      if (!compatible(i, j)) continue;
      final iou = a[i].iou(b[j]);
      final dist = math.sqrt(math.pow(a[i].cx - b[j].cx, 2) +
          math.pow(a[i].cy - b[j].cy, 2));
      final sizeRatio = a[i].area <= 0 || b[j].area <= 0
          ? 0.0
          : math.min(a[i].area, b[j].area) / math.max(a[i].area, b[j].area);
      final score = iou >= 0.3
          ? 1 + iou
          : (dist < 0.08 && sizeRatio > 0.5 ? 1 - dist : 0.0);
      if (score > 0) cand.add((score, i, j));
    }
  }
  cand.sort((x, y) => y.$1.compareTo(x.$1));
  final ua = Uint8List(a.length);
  final ub = Uint8List(b.length);
  final out = <(int, int)>[];
  for (final (_, i, j) in cand) {
    if (ua[i] == 1 || ub[j] == 1) continue;
    ua[i] = 1;
    ub[j] = 1;
    out.add((i, j));
  }
  return out;
}
