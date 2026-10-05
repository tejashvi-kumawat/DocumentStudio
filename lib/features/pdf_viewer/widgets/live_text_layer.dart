import 'dart:math' as math;

import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pointer_claim_region.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_math.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Default width of a click-created text box, in points.
const double kLiveNewTextWidthPt = 200;

/// Paints committed text boxes that are still being written into the PDF.
class LivePendingTextPainter extends CustomPainter {
  LivePendingTextPainter({required this.items, required this.geom});

  final List<LivePendingText> items;
  final LivePageGeom geom;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in items) {
      final bg = Paint()..color = t.coverColor ?? Colors.white;
      if (t.coverRects.isNotEmpty) {
        for (final r in t.coverRects) {
          canvas.drawRect(geom.rectToPx(r), bg);
        }
      } else if (t.coverNorm != null) {
        canvas.drawRect(geom.rectToPx(t.coverNorm!), bg);
      }
      paintLiveTextBox(
        canvas,
        boxPx: geom.rectToPx(t.boxNorm),
        lines: t.lines,
        fontSizePt: t.fontSizePt,
        pxPerPt: geom.pxPerPt,
        color: t.color,
        bold: t.bold,
        align: t.align,
        italic: t.italic,
        family: t.family,
        lineHeightEm: t.lineHeightEm,
        customFamily: t.customFamily,
      );
    }
  }

  @override
  bool shouldRepaint(covariant LivePendingTextPainter old) =>
      old.geom != geom ||
      old.items.length != items.length ||
      !_sameIds(old.items);

  bool _sameIds(List<LivePendingText> other) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].id != other[i].id) return false;
    }
    return true;
  }
}

enum _TextDrag { none, create, move, resizeLeft, resizeRight }

/// Add / edit text directly on the page (Acrobat "Edit PDF"-style).
///
/// The editor renders with Helvetica metrics, 1.2 leading and no padding, so
/// the text lands in the PDF exactly where it is typed.
class LiveTextLayer extends StatefulWidget {
  const LiveTextLayer({super.key, required this.session, required this.geom});

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveTextLayer> createState() => _LiveTextLayerState();
}

class _LiveTextLayerState extends State<LiveTextLayer> {
  late final TextEditingController _ctrl;
  final FocusNode _textFocus = FocusNode(debugLabel: 'live-text');
  final FocusNode _selFocus = FocusNode(debugLabel: 'live-text-selection');
  _TextDrag _drag = _TextDrag.none;
  bool _armMove = false;
  bool _hideFieldGestures = false;
  Offset? _startLocal;
  PagePlacementNorm? _base;
  Offset? _hover;
  int _focusRequestedFor = -1;
  bool _selPending = false;
  Offset? _selStart;
  LiveTextEditTarget? _selRun;

  static const _palette = <Color>[
    Color(0xFF1A1A1A),
    Color(0xFFE4002B),
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFF6B4F2A),
    Color(0xFFFFFFFF),
  ];

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;
  bool get _onThisPage => _live.pageIndex1Based == _g.pageNumber;
  bool get _editing =>
      _onThisPage &&
      !_live.creatingTextBox &&
      (_live.inlineEditing || _live.textEditTarget != null);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _live.labelText ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _textFocus.dispose();
    _selFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveTextLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromSession();
  }

  void _syncFromSession() {
    final label = _live.labelText ?? '';
    if (_ctrl.text != label && !_textFocus.hasFocus) {
      _ctrl.value = TextEditingValue(
        text: label,
        selection: TextSelection.collapsed(offset: label.length),
      );
    }
    if (_editing) {
      final gen =
          _live.textCommitRequestId * 7919 +
          _live.textCancelRequestId * 31 +
          (_live.textEditTarget?.hashCode ?? 0) +
          (_live.placement.left * 1e6).round();
      if (_focusRequestedFor != gen && !_textFocus.hasFocus) {
        _focusRequestedFor = gen;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _editing) _textFocus.requestFocus();
        });
      }
    }
  }

  double get _lineHeightNorm =>
      _g.ptToNormY(_live.fontSizePt * _live.textLineHeightEm);

  Rect get _boxPx => _g.rectToPx(_live.placement.rect);

  /// Grows / shrinks the box to the wrapped line count (same wrap as writer).
  void _fitHeight(String text, {bool draft = false}) {
    final boxWPt = _live.placement.width * _g.pageWidthPt;
    final lines = wrapPlainTextToWidth(
      text: text.isEmpty ? ' ' : text,
      maxWidthPt: boxWPt,
      fontSizePt: _live.fontSizePt,
      bold: _live.textBold,
      measure: _live.textMeasure(_live.fontSizePt),
    );
    final h = liveTextBoxHeightNorm(
      fontSizePt: _live.fontSizePt,
      pageHeightPt: _g.pageHeightPt,
      lineCount: lines.length,
      lineHeightEm: _live.textLineHeightEm,
    );
    if ((_live.placement.height - h).abs() < 1e-5) return;
    _live.setPlacement(_live.placement.copyWith(height: h), draft: draft);
  }

  Rect? _selectedOnThisPage(ViewerLiveToolSession live) {
    final sel = live.selectedRun;
    if (sel == null) return null;
    for (final r in live.textRunsForPage(_g.pageNumber)) {
      if (r.originalText == sel.originalText &&
          (r.hitRect.center - sel.hitRect.center).distance < 1e-4) {
        return _g.rectToPx(r.hitRect);
      }
    }
    return null;
  }

  LiveTextEditTarget? _runAt(Offset local) {
    final n = Offset(local.dx / _g.pagePx.width, local.dy / _g.pagePx.height);
    for (final hit in _live.textRunsForPage(_g.pageNumber)) {
      if (hit.hitRect.contains(n)) return hit;
    }
    return null;
  }

  _TextDrag _frameZone(Offset local) {
    if (!_editing) return _TextDrag.none;
    final box = _boxPx;
    final frame = box.inflate(7);
    // Corner handles resize the box width from that side (height follows
    // the text), like the side handles.
    final f3 = box.inflate(3);
    for (final (c, zone) in [
      (f3.topLeft, _TextDrag.resizeLeft),
      (f3.bottomLeft, _TextDrag.resizeLeft),
      (f3.topRight, _TextDrag.resizeRight),
      (f3.bottomRight, _TextDrag.resizeRight),
    ]) {
      if ((local - c).distance <= kLiveHandleHitPad) return zone;
    }
    if ((local - box.centerLeft.translate(-7, 0)).distance <=
        kLiveHandleHitPad) {
      return _TextDrag.resizeLeft;
    }
    if ((local - box.centerRight.translate(7, 0)).distance <=
        kLiveHandleHitPad) {
      return _TextDrag.resizeRight;
    }
    if (frame.contains(local) && !box.contains(local)) return _TextDrag.move;
    return _TextDrag.none;
  }

  bool _claims(Offset local) {
    if (_drag != _TextDrag.none || _armMove) return true;
    if (!_editing && _runAt(local) != null) return true;
    if (!_onThisPage) return false;
    if (_live.creatingTextBox || _live.awaitingClickPlacement || _editing) {
      return true;
    }
    if (_runAt(local) != null) return true;
    return _boxPx.inflate(kLiveHandleHitPad + 18).contains(local);
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final local = e.localPosition;
    if (!_claims(local)) return;
    if (_editing) {
      final zone = _frameZone(local);
      if (zone != _TextDrag.none) {
        _armMove = false;
        _drag = zone;
        _startLocal = local;
        _base = _live.placement;
        return;
      }
      if (_boxPx.inflate(8).contains(local)) {
        // A tap edits; a drag past slop moves the box. The claim region keeps
        // the viewer scroller from taking that drag.
        _armMove = true;
        _drag = _TextDrag.none;
        _startLocal = local;
        _base = _live.placement;
        return;
      }
    }
    // Clicking away from an open box commits it (or discards an empty one).
    final hadText = (_live.labelText ?? '').trim().isNotEmpty;
    if (_live.inlineEditing || _live.textEditTarget != null) {
      if (hadText) {
        _live.requestTextCommit();
        if (!_onThisPage) _live.focusPage(_g.pageNumber);
        return;
      }
      _live.requestTextCancel();
    }
    if (!_onThisPage) _live.focusPage(_g.pageNumber);
    final run = _runAt(local);
    // Canvas-style: a click on empty space first just clears the selection.
    if (run == null &&
        (_live.selectedImage != null || _live.selectedRun != null)) {
      _live.selectImage(null);
      _live.selectTextRun(null);
      return;
    }
    if (run != null) {
      if (_live.selectedImage != null) _live.selectImage(null);
      final sel = _live.selectedRun;
      final alreadySelected =
          sel != null &&
          sel.originalText == run.originalText &&
          (sel.hitRect.center - run.hitRect.center).distance < 1e-4;
      if (alreadySelected) {
        // Second click on the selected block: type into it.
        _live.setTextEditTarget(run);
        _fitHeight(run.originalText);
        return;
      }
      // First click selects (Acrobat); a drag from here moves the block.
      _live.selectTextRun(run);
      _selFocus.requestFocus();
      _selPending = true;
      _selStart = local;
      _selRun = run;
      return;
    }
    _live.selectTextRun(null);
    final n = _g.toNorm(local);
    final lineH = _lineHeightNorm;
    final origin = Offset(n.dx, (n.dy - lineH / 2).clamp(0.0, 1.0 - lineH));
    _drag = _TextDrag.create;
    _startLocal = local;
    _live.beginCreateTextBoxAtNorm(origin, heightNorm: lineH);
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
    if (_selPending && _selRun != null && _selStart != null) {
      if ((local - _selStart!).distance < 8) return;
      final run = _selRun!;
      _selPending = false;
      _live.setTextEditTarget(run);
      _fitHeight(run.originalText);
      _drag = _TextDrag.move;
      _startLocal = _selStart;
      _base = _live.placement;
      if (!_hideFieldGestures && mounted) {
        setState(() => _hideFieldGestures = true);
      }
    }
    if (_armMove && _drag == _TextDrag.none) {
      final start = _startLocal;
      if (start == null || (local - start).distance < 8) return;
      _armMove = false;
      _drag = _TextDrag.move;
      if (!_hideFieldGestures && mounted) {
        setState(() => _hideFieldGestures = true);
      }
    }
    switch (_drag) {
      case _TextDrag.none:
        return;
      case _TextDrag.create:
        final n = _g.toNorm(local);
        _live.updateCreateTextBoxAtNorm(
          Offset(n.dx, _live.textBoxCreateOriginNorm?.dy ?? n.dy),
          heightNorm: _lineHeightNorm,
        );
      case _TextDrag.move:
        final d = _g.deltaToNorm(local - _startLocal!);
        _live.setPlacement(
          movePagePlacement(_base!, dx: d.dx, dy: d.dy, minFraction: 0.004),
          draft: true,
        );
      case _TextDrag.resizeLeft:
      case _TextDrag.resizeRight:
        final base = _base!;
        final dx = _g.deltaToNorm(local - _startLocal!).dx;
        final minW = _g.ptToNormX(_live.fontSizePt * 1.2);
        var left = base.left;
        var right = base.left + base.width;
        if (_drag == _TextDrag.resizeLeft) {
          left = (left + dx).clamp(0.0, right - minW);
        } else {
          right = (right + dx).clamp(left + minW, 1.0);
        }
        _live.setPlacement(
          base.copyWith(left: left, width: right - left),
          draft: true,
        );
        _fitHeight(_ctrl.text);
    }
  }

  void _up(PointerEvent e) {
    _selPending = false;
    final start = _startLocal;
    final was = _drag;
    _drag = _TextDrag.none;
    _armMove = false;
    _startLocal = null;
    _base = null;
    if (_hideFieldGestures && mounted) {
      setState(() => _hideFieldGestures = false);
    }
    if (was == _TextDrag.create) {
      // Edit mode: a plain click on empty space only clears; dragging out a
      // width adds a new text box there.
      final dragged = start != null && (e.localPosition - start).distance >= 8;
      if (!dragged) {
        _live.finishCreateTextBox(commit: false);
        return;
      }
      _live.finishCreateTextBox(
        defaultWidthNorm: _g.ptToNormX(kLiveNewTextWidthPt).clamp(0.05, 1.0),
      );
      _fitHeight('');
      return;
    }
    if (was != _TextDrag.none) _live.commitDraft();
  }

  /// Keys for a selected (not yet opened) block: Delete removes it, Enter
  /// opens it for typing, Esc deselects.
  KeyEventResult _onSelectionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final sel = _live.selectedRun;
    if (sel == null || _editing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _live.setTextEditTarget(sel);
      _live.setLabelText('');
      _live.requestTextCommit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _live.setTextEditTarget(sel);
      _fitHeight(sel.originalText);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _live.selectTextRun(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _live.requestTextCancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final kb = HardwareKeyboard.instance;
      if (kb.isShiftPressed) return KeyEventResult.ignored;
      _live.requestTextCommit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextAlign _align(LiveMarginAlign a) => switch (a) {
    LiveMarginAlign.left => TextAlign.left,
    LiveMarginAlign.center => TextAlign.center,
    LiveMarginAlign.right => TextAlign.right,
  };

  MouseCursor _cursorAt(Offset? local) {
    if (local == null) return SystemMouseCursors.text;
    switch (_frameZone(local)) {
      case _TextDrag.move:
        return SystemMouseCursors.move;
      case _TextDrag.resizeLeft:
      case _TextDrag.resizeRight:
        return SystemMouseCursors.resizeLeftRight;
      default:
        return SystemMouseCursors.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncFromSession();
    final live = _live;
    final pending = [
      for (final t in live.pendingTexts)
        if (t.pageIndex1Based == _g.pageNumber) t,
    ];
    final editing = _editing;
    final creating = _onThisPage && live.creatingTextBox;
    final box = _boxPx;
    final target = _onThisPage ? live.textEditTarget : null;
    final fontPx = live.fontSizePt * _g.pxPerPt;
    final hoverRun = _hover == null || editing ? null : _runAt(_hover!);
    final showHint = _onThisPage && live.awaitingClickPlacement && !creating;

    final field = editing
        ? Positioned(
            left: box.left,
            top: box.top,
            width: math.max(box.width, 2),
            child: IgnorePointer(
              ignoring: _hideFieldGestures,
              child: Focus(
                onKeyEvent: _onFieldKey,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _textFocus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlign: _align(live.textAlign),
                  style: liveHelveticaStyle(
                    fontPx: fontPx,
                    color: live.markupColor,
                    bold: live.textBold,
                    italic: live.textItalic,
                    family: live.textFamily,
                    lineHeightEm: live.textLineHeightEm,
                    customFamily: live.textUserFont?.flutterFamily,
                  ),
                  strutStyle: StrutStyle(
                    fontFamily: kHelveticaCompatibleFontFamily,
                    fontFamilyFallback: kHelveticaCompatibleFontFallback,
                    fontSize: fontPx,
                    height: live.textLineHeightEm,
                    leadingDistribution: TextLeadingDistribution.even,
                    forceStrutHeight: true,
                  ),
                  cursorColor: kLiveSelectionColor,
                  cursorWidth: math.max(1.2, fontPx * 0.07),
                  cursorHeight: fontPx * 1.12,
                  scrollPadding: EdgeInsets.zero,
                  decoration: InputDecoration.collapsed(
                    hintText: target == null ? 'Type here' : null,
                    hintStyle: liveHelveticaStyle(
                      fontPx: fontPx,
                      color: const Color(0x66000000),
                      bold: live.textBold,
                    ),
                  ),
                  onChanged: (v) {
                      live.setLabelText(v, draft: true);
                      _fitHeight(v, draft: true);
                    },
                ),
              ),
            ),
          )
        : null;

    return Focus(
      focusNode: _selFocus,
      onKeyEvent: _onSelectionKey,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.deferToChild,
        cursor: _cursorAt(_hover),
        onHover: (e) => setState(() => _hover = e.localPosition),
        onExit: (_) => setState(() => _hover = null),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: PointerClaimRegion(
                claims: _claims,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      if (pending.isNotEmpty)
                        CustomPaint(
                          painter: LivePendingTextPainter(
                            items: pending,
                            geom: _g,
                          ),
                        ),
                      if (!editing)
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _RunsPainter(
                              runs: [
                                for (final r in live.textRunsForPage(
                                  _g.pageNumber,
                                ))
                                  _g.rectToPx(r.hitRect),
                              ],
                              hovered: hoverRun == null
                                  ? null
                                  : _g.rectToPx(hoverRun.hitRect),
                              selected: _selectedOnThisPage(live),
                            ),
                          ),
                        ),
                      if (editing && target?.coverNorm != null)
                        for (final r
                            in target!.coverRects.isNotEmpty
                                ? target.coverRects
                                : [target.coverNorm!])
                          Positioned.fromRect(
                            rect: _g.rectToPx(r),
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: target.coverColor ?? Colors.white,
                              ),
                            ),
                          ),
                      if (editing || creating)
                        IgnorePointer(
                          child: CustomPaint(
                            painter: LiveSelectionPainter(
                              boxPx: box.inflate(creating ? 0 : 3),
                              showHandles: !creating,
                              edgeHandlesOnly: false,
                              dashed: creating,
                            ),
                          ),
                        ),
                      ?field,
                    ],
                  ),
                ),
              ),
            ),
            if (!editing && _selectedOnThisPage(live) != null)
              _SelectionBar(
                anchor: _selectedOnThisPage(live)!,
                pageSize: _g.pagePx,
                onEdit: () {
                  final sel = live.selectedRun;
                  if (sel == null) return;
                  live.setTextEditTarget(sel);
                  _fitHeight(sel.originalText);
                },
                onDelete: () {
                  final sel = live.selectedRun;
                  if (sel == null) return;
                  live.setTextEditTarget(sel);
                  live.setLabelText('');
                  live.requestTextCommit();
                },
                onDeselect: () => live.selectTextRun(null),
              ),
            if (editing)
              _TextFormatBar(
                anchor: box,
                pageSize: _g.pagePx,
                session: live,
                palette: _palette,
                onChanged: () {
                  _fitHeight(_ctrl.text);
                  _textFocus.requestFocus();
                },
              ),
            if (showHint)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: DsMotion.fadeRiseIn(
                      child: LiveHintChip(
                        icon: Icons.text_fields,
                        text: live.textRunsForPage(_g.pageNumber).isEmpty
                            ? 'Drag on the page to add a text box'
                            : 'Click to select · click again to type · drag on empty space to add text',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunsPainter extends CustomPainter {
  _RunsPainter({required this.runs, this.hovered, this.selected});

  final List<Rect> runs;
  final Rect? hovered;
  final Rect? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..color = kLiveSelectionColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in runs) {
      canvas.drawRect(r.inflate(1), faint);
    }
    final sel = selected;
    if (sel != null) {
      canvas.drawRect(
        sel.inflate(2),
        Paint()..color = kLiveSelectionColor.withValues(alpha: 0.08),
      );
      canvas.drawRect(
        sel.inflate(2),
        Paint()
          ..color = kLiveSelectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      for (final c in [
        sel.inflate(2).topLeft,
        sel.inflate(2).topRight,
        sel.inflate(2).bottomLeft,
        sel.inflate(2).bottomRight,
      ]) {
        final r = Rect.fromCenter(center: c, width: 8, height: 8);
        canvas.drawRect(r, Paint()..color = Colors.white);
        canvas.drawRect(
          r,
          Paint()
            ..color = kLiveSelectionColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }
    }
    final h = hovered;
    if (h != null) {
      canvas.drawRect(
        h.inflate(1),
        Paint()..color = kLiveSelectionColor.withValues(alpha: 0.10),
      );
      canvas.drawRect(
        h.inflate(1),
        Paint()
          ..color = kLiveSelectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RunsPainter old) =>
      old.hovered != hovered ||
      old.selected != selected ||
      old.runs.length != runs.length;
}

class _TextFormatBar extends StatelessWidget {
  const _TextFormatBar({
    required this.anchor,
    required this.pageSize,
    required this.session,
    required this.palette,
    required this.onChanged,
  });

  final Rect anchor;
  final Size pageSize;
  final ViewerLiveToolSession session;
  final List<Color> palette;
  final VoidCallback onChanged;

  static const double _barH = 36;
  static const double _barW = 404;

  Widget _icon({
    required Key key,
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Tooltip(
      message: tip,
      child: InkResponse(
        key: key,
        onTap: onTap,
        radius: 16,
        canRequestFocus: false,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected
                ? kLiveSelectionColor.withValues(alpha: 0.12)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected ? kLiveSelectionColor : const Color(0xFF3C3C43),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var top = anchor.top - _barH - 12;
    if (top < 2) top = anchor.bottom + 10;
    final left = anchor.left
        .clamp(2.0, math.max(2.0, pageSize.width - _barW - 2))
        .toDouble();
    final s = session;
    return Positioned(
      left: left,
      top: top,
      height: _barH,
      child: DsMotion.fadeRiseIn(
        duration: DsMotion.switchDuration,
        risePx: 4,
        child: Material(
          elevation: 4,
          shadowColor: const Color(0x55000000),
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(
                  key: const Key('live_text_font_smaller'),
                  icon: Icons.text_decrease,
                  tip: 'Smaller',
                  onTap: () {
                    s.setFontSizePt(s.fontSizePt - 1);
                    onChanged();
                  },
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    key: const Key('live_text_font_size'),
                    '${s.fontSizePt.round()} pt',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _icon(
                  key: const Key('live_text_font_larger'),
                  icon: Icons.text_increase,
                  tip: 'Larger',
                  onTap: () {
                    s.setFontSizePt(s.fontSizePt + 1);
                    onChanged();
                  },
                ),
                const _Divider(),
                for (final c in palette)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () {
                        s.setMarkupColor(c);
                        onChanged();
                      },
                      child: AnimatedContainer(
                        duration: DsMotion.hoverDuration,
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.markupColor == c
                                ? kLiveSelectionColor
                                : Colors.black26,
                            width: s.markupColor == c ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                const _Divider(),
                _icon(
                  key: const Key('live_text_bold'),
                  icon: Icons.format_bold,
                  tip: 'Bold',
                  selected: s.textBold,
                  onTap: () {
                    s.setTextBold(!s.textBold);
                    onChanged();
                  },
                ),
                for (final (a, icon, key) in const [
                  (
                    LiveMarginAlign.left,
                    Icons.format_align_left,
                    'live_text_align_left',
                  ),
                  (
                    LiveMarginAlign.center,
                    Icons.format_align_center,
                    'live_text_align_center',
                  ),
                  (
                    LiveMarginAlign.right,
                    Icons.format_align_right,
                    'live_text_align_right',
                  ),
                ])
                  _icon(
                    key: Key(key),
                    icon: icon,
                    tip: 'Align ${a.name}',
                    selected: s.textAlign == a,
                    onTap: () {
                      s.setTextAlign(a);
                      onChanged();
                    },
                  ),
                const _Divider(),
                _icon(
                  key: const Key('live_text_delete'),
                  icon: Icons.delete_outline,
                  tip: 'Delete this text (removes it from the page)',
                  onTap: () {
                    if (s.textEditTarget == null) {
                      s.requestTextCancel();
                      return;
                    }
                    s.setLabelText('');
                    s.requestTextCommit();
                  },
                ),
                _icon(
                  key: const Key('live_text_cancel'),
                  icon: Icons.close,
                  tip: 'Discard (Esc)',
                  onTap: s.requestTextCancel,
                ),
                _icon(
                  key: const Key('live_text_commit'),
                  icon: Icons.check,
                  tip: 'Done (Enter)',
                  onTap: s.requestTextCommit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating bar over a selected (not yet opened) text block.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.anchor,
    required this.pageSize,
    required this.onEdit,
    required this.onDelete,
    required this.onDeselect,
  });

  final Rect anchor;
  final Size pageSize;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;

  static const double _w = 236;
  static const double _h = 34;

  static Rect rectFor(Rect anchor, Size pageSize) {
    var top = anchor.top - _h - 10;
    if (top < 2) top = anchor.bottom + 8;
    final left = anchor.left
        .clamp(2.0, math.max(2.0, pageSize.width - _w - 2))
        .toDouble();
    return Rect.fromLTWH(left, top, _w, _h);
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(Key key, IconData icon, String label, VoidCallback onTap) =>
        InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: const Color(0xFF333333)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
          ),
        );
    final r = rectFor(anchor, pageSize);
    return Positioned(
      left: r.left,
      top: r.top,
      height: _h,
      child: Material(
        elevation: 4,
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(
              const Key('live_text_sel_edit'),
              Icons.edit_outlined,
              'Edit',
              onEdit,
            ),
            btn(
              const Key('live_text_sel_delete'),
              Icons.delete_outline,
              'Delete',
              onDelete,
            ),
            btn(
              const Key('live_text_sel_close'),
              Icons.close,
              'Done',
              onDeselect,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: const Color(0x1F000000),
  );
}
