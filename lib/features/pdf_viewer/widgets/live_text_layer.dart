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
      final cover = t.coverNorm;
      if (cover != null) {
        canvas.drawRect(geom.rectToPx(cover), Paint()..color = Colors.white);
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
  _TextDrag _drag = _TextDrag.none;
  bool _armMove = false;
  bool _hideFieldGestures = false;
  Offset? _startLocal;
  PagePlacementNorm? _base;
  Offset? _hover;
  int _focusRequestedFor = -1;

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
      _g.ptToNormY(_live.fontSizePt * kTextLineHeightEm);

  Rect get _boxPx => _g.rectToPx(_live.placement.rect);

  /// Grows / shrinks the box to the wrapped line count (same wrap as writer).
  void _fitHeight(String text) {
    final boxWPt = _live.placement.width * _g.pageWidthPt;
    final lines = wrapPlainTextToWidth(
      text: text.isEmpty ? ' ' : text,
      maxWidthPt: boxWPt,
      fontSizePt: _live.fontSizePt,
      bold: _live.textBold,
    );
    final h = liveTextBoxHeightNorm(
      fontSizePt: _live.fontSizePt,
      pageHeightPt: _g.pageHeightPt,
      lineCount: lines.length,
    );
    if ((_live.placement.height - h).abs() < 1e-5) return;
    _live.setPlacement(_live.placement.copyWith(height: h));
  }

  LiveTextEditTarget? _runAt(Offset local) {
    if (!_onThisPage) return null;
    final n = Offset(local.dx / _g.pagePx.width, local.dy / _g.pagePx.height);
    for (final hit in _live.textRunHits) {
      if (hit.hitRect.contains(n)) return hit;
    }
    return null;
  }

  _TextDrag _frameZone(Offset local) {
    if (!_editing) return _TextDrag.none;
    final box = _boxPx;
    final frame = box.inflate(7);
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
    if (run != null) {
      _live.setTextEditTarget(run);
      _fitHeight(run.originalText);
      return;
    }
    final n = _g.toNorm(local);
    final lineH = _lineHeightNorm;
    final origin = Offset(n.dx, (n.dy - lineH / 2).clamp(0.0, 1.0 - lineH));
    _drag = _TextDrag.create;
    _startLocal = local;
    _live.beginCreateTextBoxAtNorm(origin, heightNorm: lineH);
  }

  void _move(PointerMoveEvent e) {
    final local = e.localPosition;
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
    final was = _drag;
    _drag = _TextDrag.none;
    _armMove = false;
    _startLocal = null;
    _base = null;
    if (_hideFieldGestures && mounted) {
      setState(() => _hideFieldGestures = false);
    }
    if (was == _TextDrag.create) {
      _live.finishCreateTextBox(
        defaultWidthNorm: _g.ptToNormX(kLiveNewTextWidthPt).clamp(0.05, 1.0),
      );
      _fitHeight('');
      return;
    }
    if (was != _TextDrag.none) _live.commitDraft();
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
                  ),
                  strutStyle: StrutStyle(
                    fontFamily: kHelveticaCompatibleFontFamily,
                    fontFamilyFallback: kHelveticaCompatibleFontFallback,
                    fontSize: fontPx,
                    height: kTextLineHeightEm,
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
                    live.setLabelText(v);
                    _fitHeight(v);
                  },
                ),
              ),
            ),
          )
        : null;

    return MouseRegion(
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
                    if (_onThisPage && !editing)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _RunsPainter(
                            runs: [
                              for (final r in live.textRunHits)
                                _g.rectToPx(r.hitRect),
                            ],
                            hovered: hoverRun == null
                                ? null
                                : _g.rectToPx(hoverRun.hitRect),
                          ),
                        ),
                      ),
                    if (editing && target?.coverNorm != null)
                      Positioned.fromRect(
                        rect: _g.rectToPx(target!.coverNorm!),
                        child: const IgnorePointer(
                          child: ColoredBox(color: Colors.white),
                        ),
                      ),
                    if (editing || creating)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: LiveSelectionPainter(
                            boxPx: box.inflate(creating ? 0 : 3),
                            showHandles: !creating,
                            edgeHandlesOnly: true,
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
                      text: live.textRunHits.isEmpty
                          ? 'Click to add text · drag to set its width'
                          : 'Click text to edit it · click empty space to add text',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RunsPainter extends CustomPainter {
  _RunsPainter({required this.runs, this.hovered});

  final List<Rect> runs;
  final Rect? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..color = kLiveSelectionColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in runs) {
      canvas.drawRect(r.inflate(1), faint);
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
      old.hovered != hovered || old.runs.length != runs.length;
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
  static const double _barW = 372;

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
