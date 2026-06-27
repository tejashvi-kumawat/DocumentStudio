import 'dart:math' as math;

import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_overlay_common.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool liveFormValueChecked(String? v) => v == 'Yes' || v == 'true' || v == '1';

/// Small light note. It does not cover the page.
class _EmptyBlankNotice extends StatelessWidget {
  const _EmptyBlankNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1F1A1C1E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF3C4048),
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Type into detected form fields right on the page; the typed value renders
/// with the same font size / baseline the flatten writer uses.
class LiveFormLayer extends StatefulWidget {
  const LiveFormLayer({super.key, required this.session, required this.geom});

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  @override
  State<LiveFormLayer> createState() => _LiveFormLayerState();
}

class _LiveFormLayerState extends State<LiveFormLayer> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _nodes = {};
  int _seenFocusGeneration = -1;
  int? _scanAskedFor;

  ViewerLiveToolSession get _live => widget.session;
  LivePageGeom get _g => widget.geom;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(PdfFormSpot spot) => _controllers.putIfAbsent(
        spot.id,
        () => TextEditingController(text: _live.formValues[spot.id] ?? ''),
      );

  FocusNode _nodeFor(PdfFormSpot spot) => _nodes.putIfAbsent(spot.id, () {
        final node = FocusNode(debugLabel: 'form_spot_${spot.id}');
        node.onKeyEvent = _onKey;
        node.addListener(() {
          if (node.hasFocus && _live.activeFormSpotId != spot.id) {
            if (_live.pageIndex1Based != _g.pageNumber) {
              _live.focusPage(_g.pageNumber);
            }
            _live.focusFormSpot(spot.id);
          }
        });
        return node;
      });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _live.focusNextFormSpot(reverse: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      node.unfocus();
      _live.clearActiveFormSpot();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _syncFocus() {
    final gen = _live.formFocusGeneration;
    if (gen == _seenFocusGeneration) return;
    _seenFocusGeneration = gen;
    final id = _live.activeFormSpotId;
    final node = id == null ? null : _nodes[id];
    if (node == null || node.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _g.pageNumber;
    if (_scanAskedFor != page && !_live.formPageScanned(page)) {
      _scanAskedFor = page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _live.requestFormPageScan(page);
      });
    }
    final spots = [
      for (final s in _live.formSpots)
        if (s.kind != PdfFormSpotKind.signature &&
            (s.pageIndex1Based == 0 || s.pageIndex1Based == page))
          s,
    ];
    for (final s in spots) {
      _nodeFor(s);
    }
    _syncFocus();
    final onThisPage = _live.pageIndex1Based == page;
    if (spots.isEmpty) {
      final message = _live.formPageEmptyMessage(page);
      if (message == null) return const SizedBox.expand();
      return IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DsMotion.fadeRiseIn(
              child: _EmptyBlankNotice(text: message),
            ),
          ),
        ),
      );
    }
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < spots.length; i++)
            Positioned.fromRect(
              rect: _g.rectToPx(spots[i].normRect),
              child: FocusTraversalOrder(
                order: NumericFocusOrder(i.toDouble()),
                child: spots[i].kind == PdfFormSpotKind.checkbox
                    ? _CheckboxSpot(
                        focusNode: _nodeFor(spots[i]),
                        checked: liveFormValueChecked(_live.formValues[spots[i].id]),
                        active: _live.activeFormSpotId == spots[i].id,
                        strokePx: formCheckStrokePt(
                              spots[i].normRect.width * _g.pageWidthPt,
                              spots[i].normRect.height * _g.pageHeightPt,
                            ) *
                            _g.pxPerPt,
                        onTap: () {
                          if (!onThisPage) _live.focusPage(_g.pageNumber);
                          _live.focusFormSpot(spots[i].id);
                          _live.toggleCheckbox(spots[i].id);
                        },
                      )
                    : _TextSpot(
                        controller: _ctrlFor(spots[i]),
                        focusNode: _nodeFor(spots[i]),
                        active: _live.activeFormSpotId == spots[i].id,
                        value: _live.formValues[spots[i].id] ?? '',
                        widthPt: spots[i].normRect.width * _g.pageWidthPt,
                        heightPt: spots[i].normRect.height * _g.pageHeightPt,
                        pxPerPt: _g.pxPerPt,
                        onChanged: (v) => _live.setFormValue(spots[i].id, v),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckboxSpot extends StatelessWidget {
  const _CheckboxSpot({
    required this.focusNode,
    required this.checked,
    required this.active,
    required this.strokePx,
    required this.onTap,
  });

  final FocusNode focusNode;
  final bool checked;
  final bool active;
  final double strokePx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: DsMotion.hoverDuration,
            decoration: const BoxDecoration(color: Color(0x1A2B6FE6)),
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: active ? kLiveSelectionColor : const Color(0x88406BCF),
                width: active ? 1.6 : 1,
              ),
            ),
            child: AnimatedSwitcher(
              duration: DsMotion.hoverDuration,
              child: checked
                  ? CustomPaint(
                      key: const ValueKey('on'),
                      size: Size.infinite,
                      painter: _CheckPainter(strokePx: strokePx),
                    )
                  : const SizedBox.expand(key: ValueKey('off')),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.strokePx});

  final double strokePx;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < kFormCheckMarkNorm.length; i++) {
      final p = kFormCheckMarkNorm[i];
      final o = Offset(p.dx * size.width, p.dy * size.height);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF111111)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, strokePx)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.strokePx != strokePx;
}

/// In-rect text editor that matches the flattened output (font / baseline).
class _TextSpot extends StatelessWidget {
  const _TextSpot({
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.value,
    required this.widthPt,
    required this.heightPt,
    required this.pxPerPt,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
  final String value;
  final double widthPt;
  final double heightPt;
  final double pxPerPt;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    final fs = formFieldFontSizePt(value, widthPt, heightPt);
    final fontPx = fs * pxPerPt;
    final topPx = formFieldLineTopPt(heightPt, fs) * pxPerPt;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: focusNode.requestFocus,
        child: AnimatedContainer(
          duration: DsMotion.hoverDuration,
          // Border as foreground so it never insets (shifts) the text.
          decoration: BoxDecoration(
            color: active ? const Color(0x142B6FE6) : const Color(0x0A2B6FE6),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? kLiveSelectionColor : const Color(0xAA406BCF),
                width: active ? 1.5 : 1,
              ),
            ),
          ),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(
                left: kFormFieldPadPt * pxPerPt,
                right: kFormFieldPadPt * pxPerPt,
                top: topPx,
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 1,
                style: liveHelveticaStyle(fontPx: fontPx, color: const Color(0xFF111111)),
                strutStyle: StrutStyle(
                  fontFamily: kHelveticaCompatibleFontFamily,
                  fontFamilyFallback: kHelveticaCompatibleFontFallback,
                  fontSize: fontPx,
                  height: kTextLineHeightEm,
                  leadingDistribution: TextLeadingDistribution.even,
                  forceStrutHeight: true,
                ),
                cursorColor: kLiveSelectionColor,
                cursorHeight: fontPx * 1.1,
                scrollPadding: EdgeInsets.zero,
                decoration: const InputDecoration.collapsed(hintText: null),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
