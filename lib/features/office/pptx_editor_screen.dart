import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/office/office_chrome.dart';
import 'package:document_studio/features/office/office_fonts.dart';
import 'package:document_studio/features/office/office_route.dart';
import 'package:document_studio/features/office/pptx_animation.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:document_studio/features/office/pptx_render.dart';
import 'package:document_studio/features/office/pptx_slideshow.dart';
import 'package:document_studio/features/office/pptx_text.dart';
import 'package:document_studio/features/print/print_gateway.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

const _accent = kSlidesAccent;
const _fontSizes = [
  '8',
  '9',
  '10',
  '11',
  '12',
  '14',
  '16',
  '18',
  '20',
  '24',
  '28',
  '32',
  '36',
  '40',
  '44',
  '54',
  '60',
  '72',
  '96',
];

/// Shapes offered by Insert → Shape (DrawingML preset names).
const _shapes = [
  ('rect', 'Rectangle', Icons.crop_square),
  ('roundRect', 'Rounded rectangle', Icons.rounded_corner),
  ('ellipse', 'Oval', Icons.circle_outlined),
  ('triangle', 'Triangle', Icons.change_history),
  ('rtTriangle', 'Right triangle', Icons.signal_cellular_null),
  ('diamond', 'Diamond', Icons.diamond_outlined),
  ('parallelogram', 'Parallelogram', Icons.view_array_outlined),
  ('trapezoid', 'Trapezoid', Icons.filter_list),
  ('pentagon', 'Pentagon', Icons.pentagon_outlined),
  ('hexagon', 'Hexagon', Icons.hexagon_outlined),
  ('octagon', 'Octagon', Icons.stop_outlined),
  ('star5', 'Star', Icons.star_border),
  ('star4', '4-point star', Icons.auto_awesome_outlined),
  ('heart', 'Heart', Icons.favorite_border),
  ('plus', 'Plus', Icons.add),
  ('rightArrow', 'Right arrow', Icons.arrow_right_alt),
  ('leftArrow', 'Left arrow', Icons.arrow_back),
  ('upArrow', 'Up arrow', Icons.arrow_upward),
  ('downArrow', 'Down arrow', Icons.arrow_downward),
  ('leftRightArrow', 'Double arrow', Icons.swap_horiz),
  ('chevron', 'Chevron', Icons.chevron_right),
  ('homePlate', 'Pentagon arrow', Icons.label_outline),
  ('wedgeRoundRectCallout', 'Callout', Icons.chat_bubble_outline),
  ('cloud', 'Cloud', Icons.cloud_outlined),
];

const _transitions = [
  ('none', 'None', Icons.block),
  ('fade', 'Fade', Icons.gradient),
  ('push', 'Push', Icons.input),
  ('wipe', 'Wipe', Icons.cleaning_services_outlined),
  ('split', 'Split', Icons.vertical_split_outlined),
  ('cover', 'Cover', Icons.layers_outlined),
  ('pull', 'Uncover', Icons.layers_clear_outlined),
  ('zoom', 'Zoom', Icons.zoom_out_map),
  ('circle', 'Circle', Icons.radio_button_unchecked),
  ('dissolve', 'Dissolve', Icons.blur_on),
  ('randomBar', 'Random bars', Icons.view_week_outlined),
  ('cut', 'Cut', Icons.content_cut),
];

enum _Panel { none, theme, transition, animation, format, background }

/// PowerPoint editor laid out like Google Slides: menus, one toolbar,
/// filmstrip on the left with deck details, slide canvas with speaker
/// notes, and side panels for theme, transition, background and format.
class PptxEditorScreen extends ConsumerStatefulWidget {
  const PptxEditorScreen({
    super.key,
    required this.doc,
    this.path,
    this.session,
  });

  final PptxDocument doc;
  final String? path;

  /// Keeps the slide, history and view across tab switches.
  final OfficeSession? session;

  @override
  ConsumerState<PptxEditorScreen> createState() => _PptxEditorScreenState();
}

class _PptxEditorScreenState extends ConsumerState<PptxEditorScreen> {
  PptxDocument get doc => widget.doc;
  late String? _path = widget.path;
  int _current = 0;
  PptxShape? _selected;
  PptxShape? _editing;
  QuillController? _quill;
  final _quillFocus = FocusNode(debugLabel: 'pptx-text');
  final _quillKey = GlobalKey<QuillEditorState>();
  final _canvasFocus = FocusNode(debugLabel: 'pptx-canvas');
  final _notes = TextEditingController();
  bool _dirtyFlag = false;

  /// Unsaved changes; mirrored into the tab's session so closing the tab
  /// can ask first.
  bool get _dirty => _dirtyFlag;
  set _dirty(bool v) {
    _dirtyFlag = v;
    widget.session?.dirty = v;
  }

  _Panel _panel = _Panel.none;
  bool _showStrip = true;
  bool _showNotes = true;
  bool _grid = false;
  bool _sorter = false;
  double _zoom = 1; // 1 = fit
  final _undo = <PptxSnapshot>[];
  final _redo = <PptxSnapshot>[];
  (XmlElement, String?)? _clip;

  /// Canvas-only repaint while dragging (the strip waits for the drop).
  final _live = ValueNotifier<int>(0);
  List<double> _guidesX = [], _guidesY = [];
  Rect? _dragBase;
  Offset _dragAcc = Offset.zero;
  double _rotBase = 0;
  int _transitionPreview = 0;

  PptxSlide get _slide => doc.slides[_current.clamp(0, doc.slides.length - 1)];

  @override
  void initState() {
    super.initState();
    widget.session?.saveNow = () => _save();
    final session = widget.session;
    final st = session?.state;
    if (session != null && st != null && st.isNotEmpty) {
      _path = session.path;
      _dirty = session.dirty;
      _current = ((st['slide'] as int?) ?? 0).clamp(0, doc.slides.length - 1);
      _zoom = (st['zoom'] as double?) ?? 1;
      _showStrip = (st['strip'] as bool?) ?? true;
      _showNotes = (st['notes'] as bool?) ?? true;
      _undo.addAll((st['undo'] as List<PptxSnapshot>?) ?? const []);
      _redo.addAll((st['redo'] as List<PptxSnapshot>?) ?? const []);
    }
    _notes.text = _slide.notes;
    OfficeFonts.instance.preload(pptxFonts(doc));
    unawaited(PptxImages.preload(doc));
  }

  @override
  void dispose() {
    widget.session?.saveNow = null;
    final s = _editing, q = _quill;
    if (s != null && q != null) {
      s
        ..paras = deltaToPptx(doc, s, q.document.toDelta())
        ..dirtyText = true;
      _dirty = true;
    }
    final session = widget.session;
    if (session != null) {
      session
        ..path = _path
        ..dirty = _dirty;
      session.state
        ..['slide'] = _current
        ..['zoom'] = _zoom
        ..['strip'] = _showStrip
        ..['notes'] = _showNotes
        ..['undo'] = List<PptxSnapshot>.of(_undo)
        ..['redo'] = List<PptxSnapshot>.of(_redo);
    }
    _quill?.dispose();
    _quillFocus.dispose();
    _canvasFocus.dispose();
    _notes.dispose();
    _live.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ history

  /// Built thumbnails per slide; a slide's entry is dropped when it changes,
  /// so editing one slide never rebuilds the whole filmstrip.
  final _thumbs = <PptxSlide, Widget>{};

  void _checkpoint({bool deck = false}) {
    deck ? _thumbs.clear() : _thumbs.remove(_slide);
    _undo.add(deck ? doc.snapshot() : doc.snapshot(only: _slide));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
    _dirty = true;
  }

  PptxSnapshot _mirror(PptxSnapshot s) {
    if (s.parts != null) return doc.snapshot();
    final slide = doc.slides
        .where((x) => s.slides.containsKey(x.path))
        .firstOrNull;
    return slide == null ? doc.snapshot() : doc.snapshot(only: slide);
  }

  void _undoOp() => _history(_undo, _redo);
  void _redoOp() => _history(_redo, _undo);

  void _history(List<PptxSnapshot> from, List<PptxSnapshot> to) {
    if (_editing != null) _endEdit();
    if (from.isEmpty) return;
    final s = from.removeLast();
    to.add(_mirror(s));
    final path = _slide.path;
    doc.restore(s);
    _thumbs.clear();
    setState(() {
      _selected = null;
      final i = doc.slides.indexWhere((x) => x.path == path);
      _current = i < 0 ? _current.clamp(0, doc.slides.length - 1) : i;
      _notes.text = _slide.notes;
      _dirty = true;
    });
  }

  void _changed() {
    _thumbs.remove(_slide);
    setState(() => _dirty = true);
  }

  // ---------------------------------------------------------- selection

  void _goto(int i) {
    if (_editing != null) _endEdit();
    setState(() {
      _current = i.clamp(0, doc.slides.length - 1);
      _selected = null;
      _notes.text = _slide.notes;
    });
  }

  void _select(PptxShape? s) {
    if (_editing != null && !identical(_editing, s)) _endEdit();
    setState(() => _selected = s);
    _canvasFocus.requestFocus();
  }

  bool get _textTarget =>
      _selected != null &&
      _selected!.kind == PptxShapeKind.text &&
      _selected!.geom != 'line';

  // --------------------------------------------------------- text edit

  void _beginEdit(PptxShape s) {
    if (s.kind != PptxShapeKind.text || s.geom == 'line' || s.locked) return;
    if (_editing != null) _endEdit();
    _checkpoint();
    final q = QuillController(
      document: Document.fromDelta(pptxToDelta(doc, s)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    q.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: q.document.length - 1),
      ChangeSource.local,
    );
    q.addListener(_onQuill);
    setState(() {
      _selected = s;
      _editing = s;
      _quill = q;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _quillFocus.requestFocus(),
    );
  }

  void _onQuill() {
    // Ribbon state follows the caret; text boxes grow with their text.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _growToText());
  }

  void _growToText() {
    final s = _editing;
    final r =
        _quillKey.currentState?.editableTextKey.currentState?.renderEditor;
    if (s == null ||
        r == null ||
        !r.hasSize ||
        s.geom != null ||
        s.placeholder != null)
      return;
    final scale = _scale;
    if (scale <= 0) return;
    final needed = (r.size.height + 7.2 * 2 * _ptToPx) / scale;
    if (needed > s.h + 1) {
      s.h = needed;
      s.dirtyGeometry = true;
      _live.value++;
    }
  }

  void _endEdit() {
    final s = _editing;
    final q = _quill;
    if (s == null || q == null) return;
    final paras = deltaToPptx(doc, s, q.document.toDelta());
    s
      ..paras = paras
      ..dirtyText = true;
    q.removeListener(_onQuill);
    _editing = null;
    _quill = null;
    _thumbs.remove(_slide);
    WidgetsBinding.instance.addPostFrameCallback((_) => q.dispose());
    _dirty = true;
    if (mounted) setState(() {});
    _canvasFocus.requestFocus();
  }

  // ---------------------------------------------------------- formatting

  /// Applies a character format to the selected text (when editing) or to
  /// every run of the selected shape.
  void _fmt(String key, Object? value) {
    final q = _quill;
    if (q != null) {
      q.formatSelection(Attribute.fromKeyValue(key, value));
      _quillFocus.requestFocus();
      return;
    }
    final s = _selected;
    if (s == null || !_textTarget) return;
    _checkpoint();
    for (final para in s.paras) {
      for (final r in para.runs) {
        switch (key) {
          case 'bold':
            r.bold = value == true;
          case 'italic':
            r.italic = value == true;
          case 'underline':
            r.underline = value == true;
          case 'strike':
            r.strike = value == true;
          case 'size':
            r.sizePt = double.tryParse('$value');
          case 'color':
            r.color = value == null
                ? null
                : (value as String).replaceFirst('#', '').toUpperCase();
          case 'font':
            r.font = value as String?;
        }
      }
    }
    s.dirtyText = true;
    _changed();
  }

  /// Paragraph formats (align, list, indent, spacing).
  void _paraFmt(String key, Object? value) {
    final q = _quill;
    if (q != null) {
      if (key == 'indent') {
        q.indentSelection(value == true);
      } else {
        q.formatSelection(Attribute.fromKeyValue(key, value));
      }
      _quillFocus.requestFocus();
      return;
    }
    final s = _selected;
    if (s == null || !_textTarget) return;
    _checkpoint();
    for (final para in s.paras) {
      switch (key) {
        case 'align':
          para.align = switch (value) {
            'center' => 'ctr',
            'right' => 'r',
            'justify' => 'just',
            _ => 'l',
          };
        case 'list':
          final was = value == 'ordered' ? para.numbered : para.bullet;
          para.bullet = value == 'bullet' && !was;
          para.numbered = value == 'ordered' && !was;
        case 'indent':
          para.level = (para.level + (value == true ? 1 : -1)).clamp(0, 4);
        case 'line-height':
          para.lineSpacing = (value as num?)?.toDouble();
      }
    }
    s.dirtyText = true;
    _changed();
  }

  Map<String, Attribute> get _qsel =>
      _quill?.getSelectionStyle().attributes ?? const {};

  bool _isOn(String key) {
    if (_quill != null) return _qsel[key]?.value == true;
    final runs =
        _selected?.paras
            .expand((e) => e.runs)
            .where((r) => r.text.isNotEmpty)
            .toList() ??
        const [];
    if (runs.isEmpty) return false;
    return runs.every(
      (r) => switch (key) {
        'bold' => r.bold,
        'italic' => r.italic,
        'underline' => r.underline,
        'strike' => r.strike,
        _ => false,
      },
    );
  }

  PptxRun? get _firstRun => _selected?.paras
      .expand((e) => e.runs)
      .where((r) => r.text.isNotEmpty)
      .firstOrNull;

  String get _fontName {
    final q = _qsel['font']?.value;
    if (q is String) return q;
    final s = _selected;
    return doc.fontName(_firstRun?.font, title: s?.titleFont ?? false);
  }

  double get _fontPt {
    final q = double.tryParse('${_qsel['size']?.value ?? ''}');
    if (q != null) return q;
    final s = _selected;
    if (s == null) return 18;
    return _firstRun?.sizePt ?? s.sizeForLevel(0);
  }

  String? get _paraAlign {
    if (_quill != null) return _qsel['align']?.value as String?;
    final a = _selected?.paras.firstOrNull?.align ?? _selected?.defaultAlign;
    return switch (a) {
      'ctr' => 'center',
      'r' => 'right',
      'just' => 'justify',
      _ => null,
    };
  }

  String _fmtPt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  void _grow(bool up) {
    final sizes = _fontSizes.map(double.parse).toList();
    final cur = _fontPt;
    final next = up
        ? sizes.firstWhere((s) => s > cur + 0.01, orElse: () => cur + 8)
        : sizes.lastWhere(
            (s) => s < cur - 0.01,
            orElse: () => math.max(1, cur - 1).toDouble(),
          );
    _fmt('size', _fmtPt(next));
  }

  String _hex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _shapeStyle({
    String? fill,
    String? line,
    double? width,
    bool clearFill = false,
    bool clearLine = false,
  }) {
    final s = _selected;
    if (s == null || s.locked) return;
    _checkpoint();
    if (fill != null || clearFill) s.fill = clearFill ? 'none' : fill;
    if (line != null || clearLine) s.line = clearLine ? 'none' : line;
    if (width != null) s.lineWidth = width;
    s.dirtyStyle = true;
    _changed();
  }

  // ------------------------------------------------------------- objects

  void _addTextBox() {
    _checkpoint();
    final s = doc.addTextBox(_slide, sizePt: 18, color: null);
    _changed();
    _beginEdit(s);
  }

  void _addWordArt() {
    _checkpoint();
    final s = doc.addTextBox(
      _slide,
      text: 'Your text',
      sizePt: 54,
      color: '@accent1',
      bold: true,
    );
    s.paras.first.align = 'ctr';
    _changed();
    setState(() => _selected = s);
  }

  void _addAnimation(PptxShape shape) {
    _checkpoint();
    _slide.animations.add(
      PptxAnim(shape: shape, cls: PptxAnimClass.entr, effect: 'fade'),
    );
    _slide.dirtyAnimations = true;
    _animPreview++;
    _changed();
  }

  void _editAnimation(PptxAnim a, void Function() f) {
    _checkpoint();
    f();
    _slide.dirtyAnimations = true;
    _changed();
  }

  int _animPreview = 0;

  void _addShape(String geom) {
    _checkpoint();
    final s = doc.addShape(_slide, geom);
    setState(() => _selected = s);
    _changed();
  }

  void _addTable(int rows, int cols) {
    _checkpoint();
    final s = doc.addTable(_slide, rows, cols);
    setState(() => _selected = s);
    _changed();
  }

  Future<void> _addPicture() async {
    final f = await ref
        .read(fileStorageProvider)
        .pickOpenFile(
          allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'bmp'],
        );
    if (f == null) return;
    final bytes = await File(f.path).readAsBytes();
    double aspect;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
    } catch (_) {
      _snack('That picture could not be read');
      return;
    }
    var ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
    if (ext == 'jpg') ext = 'jpeg';
    _checkpoint();
    final s = doc.addPicture(_slide, bytes, ext, aspect);
    unawaited(PptxImages.unawaitedLoad(doc, s.media!));
    setState(() => _selected = s);
    _changed();
  }

  void _delete() {
    final s = _selected;
    if (s == null || s.locked) return;
    _checkpoint();
    doc.removeShape(_slide, s);
    setState(() => _selected = null);
    _changed();
  }

  void _copy({bool cut = false}) {
    final s = _selected;
    if (s == null) return;
    _clip = doc.copyShape(_slide, s);
    if (cut) _delete();
  }

  void _paste() {
    final c = _clip;
    if (c == null) return;
    _checkpoint();
    final s = doc.pasteShape(_slide, c);
    setState(() => _selected = s);
    _changed();
  }

  void _duplicate() {
    final s = _selected;
    if (s == null) return;
    final c = doc.copyShape(_slide, s);
    if (c == null) return;
    _checkpoint();
    final n = doc.pasteShape(_slide, c);
    setState(() => _selected = n);
    _changed();
  }

  void _order(String how) {
    final s = _selected;
    if (s == null || s.locked) return;
    _checkpoint();
    doc.reorder(_slide, s, how);
    _changed();
  }

  void _alignOnSlide(String how) {
    final s = _selected;
    if (s == null || s.locked) return;
    _checkpoint();
    switch (how) {
      case 'left':
        s.x = 0;
      case 'center':
        s.x = (doc.width - s.w) / 2;
      case 'right':
        s.x = doc.width - s.w;
      case 'top':
        s.y = 0;
      case 'middle':
        s.y = (doc.height - s.h) / 2;
      case 'bottom':
        s.y = doc.height - s.h;
    }
    s.dirtyGeometry = true;
    _changed();
  }

  void _rotate(double deg) {
    final s = _selected;
    if (s == null || s.locked) return;
    _checkpoint();
    s
      ..rotation = (s.rotation + deg) % 360
      ..dirtyGeometry = true;
    _changed();
  }

  Future<void> _editTable() async {
    final s = _selected;
    if (s == null || s.kind != PptxShapeKind.table || s.locked) return;
    final result = await showDialog<List<List<String>>?>(
      context: context,
      builder: (_) => _TableCellsDialog(
        rows:
            s.cells ??
            const [
              [''],
            ],
      ),
    );
    if (result == null) return;
    _checkpoint();
    if (result.isEmpty) {
      doc.removeShape(_slide, s);
      setState(() => _selected = null);
    } else {
      s
        ..cells = result
        ..dirtyText = true;
    }
    _changed();
  }

  // -------------------------------------------------------------- slides

  void _newSlide([PptxLayout? layout]) {
    if (_editing != null) _endEdit();
    _checkpoint(deck: true);
    final s = layout == null
        ? doc.duplicateSlide(_slide, empty: true)
        : doc.addSlide(layout, after: _slide);
    _goto(doc.slides.indexOf(s));
    _changed();
  }

  void _duplicateSlide() {
    if (_editing != null) _endEdit();
    _checkpoint(deck: true);
    _goto(doc.slides.indexOf(doc.duplicateSlide(_slide)));
    _changed();
  }

  void _deleteSlide() {
    if (doc.slides.length < 2) return;
    _checkpoint(deck: true);
    doc.deleteSlide(_slide);
    _goto(_current.clamp(0, doc.slides.length - 1));
    _changed();
  }

  void _toggleHidden() {
    _checkpoint();
    _slide
      ..hidden = !_slide.hidden
      ..dirtyHidden = true;
    _changed();
  }

  void _moveSlide(int from, int to) {
    _checkpoint(deck: true);
    final cur = _slide;
    doc.moveSlide(from, to);
    setState(() => _current = doc.slides.indexOf(cur));
    _changed();
  }

  void _changeLayout(PptxLayout l) {
    if (_editing != null) _endEdit();
    _checkpoint(deck: true);
    doc.changeLayout(_slide, l);
    setState(() => _selected = null);
    _changed();
  }

  void _applyTheme(PptxTheme t) {
    _checkpoint(deck: true);
    doc.applyTheme(t);
    OfficeFonts.instance.preload([t.major, t.minor]);
    _changed();
  }

  void _setBackground(Color? c, {bool all = false}) {
    _checkpoint(deck: all);
    for (final s in all ? doc.slides : [_slide]) {
      s
        ..ownBackground = c != null
        ..background = c == null ? '@bg1' : _hex(c)
        ..dirtyBackground = true;
    }
    if (c == null) {
      // Back to the theme background: re-read so the layout's shows again.
      final snap = doc.snapshot(only: all ? null : _slide);
      doc.restore(snap);
    }
    _changed();
  }

  void _setTransition({
    String? type,
    String? dir,
    String? speed,
    int? advance,
    bool clearAdvance = false,
    bool all = false,
  }) {
    _checkpoint(deck: all);
    for (final s in all ? doc.slides : [_slide]) {
      if (all) {
        s
          ..transition = _slide.transition
          ..transitionDir = _slide.transitionDir
          ..transitionSpeed = _slide.transitionSpeed
          ..advanceAfterMs = _slide.advanceAfterMs;
      } else {
        if (type != null) s.transition = type == 'none' ? null : type;
        if (dir != null) s.transitionDir = dir;
        if (speed != null) s.transitionSpeed = speed;
        if (advance != null) s.advanceAfterMs = advance;
        if (clearAdvance) s.advanceAfterMs = null;
      }
      s.dirtyTransition = true;
    }
    _transitionPreview++;
    _changed();
  }

  Future<void> _slideSize() async {
    final choice = await showDialog<(double, double)>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Page setup'),
        children: [
          for (final (label, w, h) in [
            ('Widescreen 16:9', 12192000.0, 6858000.0),
            ('Standard 4:3', 9144000.0, 6858000.0),
            ('Widescreen 16:10', 10972800.0, 6858000.0),
            ('A4 paper', 10692000.0, 7560000.0),
            ('Letter paper', 9144000.0, 7058025.0),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, (w, h)),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child:
                        (doc.width - w).abs() < 2000 &&
                            (doc.height - h).abs() < 2000
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    if (_editing != null) _endEdit();
    _checkpoint(deck: true);
    doc.setSlideSize(choice.$1, choice.$2);
    setState(() => _selected = null);
    _changed();
  }

  Future<void> _findReplace() async {
    final f = TextEditingController(), r = TextEditingController();
    var matchCase = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Find and replace'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: f,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Find'),
                ),
                TextField(
                  controller: r,
                  decoration: const InputDecoration(labelText: 'Replace with'),
                ),
                CheckboxListTile(
                  value: matchCase,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Match case'),
                  onChanged: (v) => set(() => matchCase = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace all'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || f.text.isEmpty) return;
    if (_editing != null) _endEdit();
    _checkpoint(deck: true);
    final n = doc.replaceAll(f.text, r.text, matchCase: matchCase);
    _changed();
    _snack(
      n == 0
          ? 'No matches found'
          : 'Replaced $n occurrence${n == 1 ? '' : 's'}',
    );
  }

  // ---------------------------------------------------------------- file

  Future<bool> _save({bool saveAs = false}) async {
    if (_editing != null) _endEdit();
    final bytes = doc.save();
    var path = _path;
    if (path == null || saveAs) {
      path = await ref
          .read(fileStorageProvider)
          .pickSavePath(
            suggestedName: _path == null
                ? 'Presentation.pptx'
                : p.basename(_path!),
            bytes: bytes,
            allowedExtensions: const ['pptx'],
          );
      if (path == null) return false;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) return true;
    setState(() {
      _path = path;
      _dirty = false;
    });
    _snack('Saved ${p.basename(path)}');
    return true;
  }

  Future<void> _exportPdf() async {
    if (_editing != null) _endEdit();
    final bytes = await pptxToPdf(doc);
    final stem = _path == null
        ? 'Presentation'
        : p.basenameWithoutExtension(_path!);
    final path = await ref
        .read(fileStorageProvider)
        .pickSavePath(
          suggestedName: '$stem.pdf',
          bytes: bytes,
          allowedExtensions: const ['pdf'],
          mimeType: 'application/pdf',
        );
    if (path == null) return;
    await File(path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    showDocumentSaveResultActions(
      context,
      file: LocalFileRef(
        path: path,
        displayName: p.basename(path),
        sizeBytes: bytes.length,
      ),
      message: 'Exported ${p.basename(path)}',
    );
  }

  Future<void> _print() async {
    if (_editing != null) _endEdit();
    final bytes = await pptxToPdf(doc);
    await const PrintingGateway().layoutPdf(
      onLayout: (_) async => bytes,
      name: _path == null ? 'Presentation' : p.basename(_path!),
    );
  }

  Future<void> _close() async {
    if (_editing != null) _endEdit();
    if (_dirty) {
      final r = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Save changes?'),
          content: const Text(
            'This presentation has changes that are not saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text("Don't save"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (r == null || r == 'cancel') return;
      if (r == 'save' && !await _save()) return;
    }
    if (!mounted) return;
    widget.session?.release();
    context.canPop() ? context.pop() : context.go('/');
  }

  Future<void> _present({
    bool fromStart = false,
    bool presenter = false,
  }) async {
    if (_editing != null) _endEdit();
    await showPptxSlideshow(
      context,
      doc,
      start: fromStart ? 0 : _current,
      presenter: presenter,
    );
    if (mounted) _canvasFocus.requestFocus();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );

  // ------------------------------------------------------------------ UI

  double _scale = 1;
  double get _ptToPx => _scale * emuPerPt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_save()),
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () =>
            unawaited(_save(saveAs: true)),
        const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
          shift: true,
        ): () =>
            unawaited(_exportPdf()),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            unawaited(_print()),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true):
            _newSlide,
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            unawaited(_present(fromStart: true)),
        const SingleActivator(LogicalKeyboardKey.f5, shift: true): () =>
            unawaited(_present()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_present()),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            unawaited(_findReplace()),
      },
      child: Scaffold(
        backgroundColor: officeCanvas(theme.brightness),
        body: Column(
          children: [
            _topBar(),
            _toolbar(),
            Divider(height: 1, color: DsColors.border(theme.brightness)),
            Expanded(
              child: _sorter
                  ? _sorterView(theme)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showStrip && wide) _strip(theme),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _canvas(theme)),
                              if (_showNotes) _notesPane(theme),
                            ],
                          ),
                        ),
                        if (_panel != _Panel.none) _sidePanel(theme),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- menus

  Widget _topBar() {
    final sc = SingleActivator.new;
    Widget check(bool on, String label, VoidCallback f) =>
        officeItem(label, f, checked: on);
    final sel = _selected;
    return OfficeTopBar(
      onBack: () => unawaited(_close()),
      menus: [
        officeMenu('File', [
          officeItem(
            'New presentation',
            () => context.push(officeLocation(kind: 'pptx')),
            icon: Icons.note_add_outlined,
          ),
          officeItem('Open…', () async {
            final f = await ref
                .read(fileStorageProvider)
                .pickOpenFile(allowedExtensions: officeExtensions);
            if (f != null && mounted)
              unawaited(context.push(officeLocation(path: f.path)));
          }, icon: Icons.folder_open_outlined),
          officeMenuDivider,
          officeItem(
            'Save',
            () => unawaited(_save()),
            icon: Icons.save_outlined,
            shortcut: sc(LogicalKeyboardKey.keyS, control: true),
          ),
          officeItem(
            'Save as…',
            () => unawaited(_save(saveAs: true)),
            shortcut: sc(LogicalKeyboardKey.keyS, control: true, shift: true),
          ),
          officeItem(
            'Download as PDF',
            () => unawaited(_exportPdf()),
            icon: Icons.picture_as_pdf_outlined,
            shortcut: sc(LogicalKeyboardKey.keyE, control: true, shift: true),
          ),
          officeMenuDivider,
          officeItem('Page setup…', _slideSize, icon: Icons.aspect_ratio),
          officeItem(
            'Print',
            () => unawaited(_print()),
            icon: Icons.print_outlined,
            shortcut: sc(LogicalKeyboardKey.keyP, control: true),
          ),
          officeMenuDivider,
          officeItem('Close', () => unawaited(_close()), icon: Icons.close),
        ]),
        officeMenu('Edit', [
          officeItem(
            'Undo',
            _undo.isEmpty ? null : _undoOp,
            icon: Icons.undo,
            shortcut: sc(LogicalKeyboardKey.keyZ, control: true),
          ),
          officeItem(
            'Redo',
            _redo.isEmpty ? null : _redoOp,
            icon: Icons.redo,
            shortcut: sc(LogicalKeyboardKey.keyY, control: true),
          ),
          officeMenuDivider,
          officeItem(
            'Cut',
            sel == null ? null : () => _copy(cut: true),
            icon: Icons.content_cut,
            shortcut: sc(LogicalKeyboardKey.keyX, control: true),
          ),
          officeItem(
            'Copy',
            sel == null ? null : _copy,
            icon: Icons.content_copy,
            shortcut: sc(LogicalKeyboardKey.keyC, control: true),
          ),
          officeItem(
            'Paste',
            _clip == null ? null : _paste,
            icon: Icons.content_paste,
            shortcut: sc(LogicalKeyboardKey.keyV, control: true),
          ),
          officeItem(
            'Duplicate',
            sel == null ? null : _duplicate,
            icon: Icons.copy_all_outlined,
            shortcut: sc(LogicalKeyboardKey.keyD, control: true),
          ),
          officeItem(
            'Delete',
            sel == null ? null : _delete,
            icon: Icons.delete_outline,
            shortcut: sc(LogicalKeyboardKey.delete),
          ),
          officeMenuDivider,
          officeItem(
            'Find and replace',
            () => unawaited(_findReplace()),
            icon: Icons.find_replace,
            shortcut: sc(LogicalKeyboardKey.keyH, control: true),
          ),
        ]),
        officeMenu('View', [
          officeItem(
            'Slideshow',
            () => unawaited(_present(fromStart: true)),
            icon: Icons.slideshow,
            shortcut: sc(LogicalKeyboardKey.f5),
          ),
          officeItem(
            'Presenter view',
            () => unawaited(_present(presenter: true)),
            icon: Icons.co_present_outlined,
          ),
          officeMenuDivider,
          check(!_sorter, 'Normal', () => setState(() => _sorter = false)),
          check(
            _sorter,
            'Grid view (slide sorter)',
            () => setState(() => _sorter = true),
          ),
          officeMenuDivider,
          check(
            _showStrip,
            'Show filmstrip',
            () => setState(() => _showStrip = !_showStrip),
          ),
          check(
            _showNotes,
            'Show speaker notes',
            () => setState(() => _showNotes = !_showNotes),
          ),
          check(_grid, 'Gridlines', () => setState(() => _grid = !_grid)),
          officeMenuDivider,
          officeSub('Zoom', [
            for (final z in [0.5, 0.75, 1.0, 1.5, 2.0])
              check(
                (_zoom - z).abs() < 0.01,
                z == 1 ? 'Fit' : '${(z * 100).round()}%',
                () => setState(() => _zoom = z),
              ),
          ], icon: Icons.zoom_in),
        ]),
        officeMenu('Insert', [
          officeItem('Image…', _addPicture, icon: Icons.image_outlined),
          officeItem('Text box', _addTextBox, icon: Icons.text_fields),
          officeItem('Word art', _addWordArt, icon: Icons.format_shapes),
          officeItem(
            'Animation',
            _selected == null
                ? null
                : () {
                    setState(() => _panel = _Panel.animation);
                    _addAnimation(_selected!);
                  },
            icon: Icons.auto_awesome_motion_outlined,
          ),
          officeSub('Shape', [_shapeGrid()], icon: Icons.category_outlined),
          officeSub('Line', [
            officeItem(
              'Line',
              () => _addShape('line'),
              icon: Icons.horizontal_rule,
            ),
            officeItem(
              'Arrow',
              () => _addShape('arrow'),
              icon: Icons.arrow_right_alt,
            ),
          ], icon: Icons.horizontal_rule),
          officeSub('Table', [
            _GridPicker(onPick: _addTable),
          ], icon: Icons.table_chart_outlined),
          officeMenuDivider,
          officeItem(
            'New slide',
            _newSlide,
            icon: Icons.add_box_outlined,
            shortcut: sc(LogicalKeyboardKey.keyM, control: true),
          ),
        ]),
        officeMenu('Format', [
          officeSub('Text', [
            officeItem(
              'Bold',
              () => _fmt('bold', !_isOn('bold')),
              icon: Icons.format_bold,
              shortcut: sc(LogicalKeyboardKey.keyB, control: true),
            ),
            officeItem(
              'Italic',
              () => _fmt('italic', !_isOn('italic')),
              icon: Icons.format_italic,
              shortcut: sc(LogicalKeyboardKey.keyI, control: true),
            ),
            officeItem(
              'Underline',
              () => _fmt('underline', !_isOn('underline')),
              icon: Icons.format_underline,
              shortcut: sc(LogicalKeyboardKey.keyU, control: true),
            ),
            officeItem(
              'Strikethrough',
              () => _fmt('strike', !_isOn('strike')),
              icon: Icons.strikethrough_s,
            ),
            officeMenuDivider,
            officeItem('Increase font size', () => _grow(true)),
            officeItem('Decrease font size', () => _grow(false)),
          ], icon: Icons.text_format),
          officeSub('Align & indent', [
            officeItem(
              'Left',
              () => _paraFmt('align', null),
              icon: Icons.format_align_left,
            ),
            officeItem(
              'Center',
              () => _paraFmt('align', 'center'),
              icon: Icons.format_align_center,
            ),
            officeItem(
              'Right',
              () => _paraFmt('align', 'right'),
              icon: Icons.format_align_right,
            ),
            officeItem(
              'Justified',
              () => _paraFmt('align', 'justify'),
              icon: Icons.format_align_justify,
            ),
            officeMenuDivider,
            officeItem(
              'Increase indent',
              () => _paraFmt('indent', true),
              icon: Icons.format_indent_increase,
            ),
            officeItem(
              'Decrease indent',
              () => _paraFmt('indent', false),
              icon: Icons.format_indent_decrease,
            ),
          ], icon: Icons.format_align_left),
          officeSub(
            'Line spacing',
            _spacingItems(),
            icon: Icons.format_line_spacing,
          ),
          officeSub('Bullets & numbering', [
            officeItem(
              'Bulleted list',
              () => _paraFmt('list', 'bullet'),
              icon: Icons.format_list_bulleted,
            ),
            officeItem(
              'Numbered list',
              () => _paraFmt('list', 'ordered'),
              icon: Icons.format_list_numbered,
            ),
          ], icon: Icons.format_list_bulleted),
          officeMenuDivider,
          officeItem(
            'Format options',
            () => setState(() => _panel = _Panel.format),
            icon: Icons.tune,
          ),
        ]),
        officeMenu('Slide', [
          officeItem(
            'New slide',
            _newSlide,
            icon: Icons.add_box_outlined,
            shortcut: sc(LogicalKeyboardKey.keyM, control: true),
          ),
          officeItem(
            'Duplicate slide',
            _duplicateSlide,
            icon: Icons.copy_all_outlined,
          ),
          officeItem(
            'Delete slide',
            doc.slides.length < 2 ? null : _deleteSlide,
            icon: Icons.delete_sweep_outlined,
          ),
          officeItem(
            _slide.hidden ? 'Unskip slide' : 'Skip slide',
            _toggleHidden,
            icon: Icons.visibility_off_outlined,
          ),
          officeMenuDivider,
          officeSub('Apply layout', [
            for (final l in doc.layouts)
              officeItem(l.name, () => _changeLayout(l)),
          ], icon: Icons.dashboard_outlined),
          officeItem(
            'Change background',
            () => setState(() => _panel = _Panel.background),
            icon: Icons.format_color_fill,
          ),
          officeItem(
            'Change theme',
            () => setState(() => _panel = _Panel.theme),
            icon: Icons.palette_outlined,
          ),
          officeItem(
            'Transition',
            () => setState(() => _panel = _Panel.transition),
            icon: Icons.animation,
          ),
          officeItem(
            'Animations',
            () => setState(() => _panel = _Panel.animation),
            icon: Icons.auto_awesome_motion_outlined,
          ),
        ]),
        officeMenu('Arrange', [
          officeSub('Order', [
            officeItem(
              'Bring to front',
              () => _order('front'),
              icon: Icons.flip_to_front,
              shortcut: sc(
                LogicalKeyboardKey.arrowUp,
                control: true,
                shift: true,
              ),
            ),
            officeItem(
              'Bring forward',
              () => _order('forward'),
              shortcut: sc(LogicalKeyboardKey.arrowUp, control: true),
            ),
            officeItem(
              'Send backward',
              () => _order('backward'),
              shortcut: sc(LogicalKeyboardKey.arrowDown, control: true),
            ),
            officeItem(
              'Send to back',
              () => _order('back'),
              icon: Icons.flip_to_back,
              shortcut: sc(
                LogicalKeyboardKey.arrowDown,
                control: true,
                shift: true,
              ),
            ),
          ], icon: Icons.layers_outlined),
          officeSub('Align', [
            officeItem(
              'Left',
              () => _alignOnSlide('left'),
              icon: Icons.align_horizontal_left,
            ),
            officeItem(
              'Center',
              () => _alignOnSlide('center'),
              icon: Icons.align_horizontal_center,
            ),
            officeItem(
              'Right',
              () => _alignOnSlide('right'),
              icon: Icons.align_horizontal_right,
            ),
            officeMenuDivider,
            officeItem(
              'Top',
              () => _alignOnSlide('top'),
              icon: Icons.align_vertical_top,
            ),
            officeItem(
              'Middle',
              () => _alignOnSlide('middle'),
              icon: Icons.align_vertical_center,
            ),
            officeItem(
              'Bottom',
              () => _alignOnSlide('bottom'),
              icon: Icons.align_vertical_bottom,
            ),
          ], icon: Icons.align_horizontal_left),
          officeSub('Rotate', [
            officeItem(
              'Rotate clockwise 90°',
              () => _rotate(90),
              icon: Icons.rotate_right,
            ),
            officeItem(
              'Rotate counter-clockwise 90°',
              () => _rotate(-90),
              icon: Icons.rotate_left,
            ),
          ], icon: Icons.rotate_right),
        ]),
        officeMenu('Tools', [
          officeItem(
            'Find and replace',
            () => unawaited(_findReplace()),
            icon: Icons.find_replace,
          ),
          officeItem(
            'Presenter view',
            () => unawaited(_present(presenter: true)),
            icon: Icons.co_present_outlined,
          ),
        ]),
      ],
    );
  }

  List<Widget> _spacingItems() => [
    for (final (v, l) in [
      (null, 'Single'),
      (1.15, '1.15'),
      (1.5, '1.5'),
      (2.0, 'Double'),
    ])
      officeItem(l, () => _paraFmt('line-height', v)),
  ];

  Widget _shapeGrid() => Padding(
    padding: const EdgeInsets.all(8),
    child: SizedBox(
      width: 6 * 40,
      child: Wrap(
        children: [
          for (final (g, label, icon) in _shapes)
            Tooltip(
              message: label,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  MenuController.maybeOf(context)?.close();
                  _addShape(g);
                },
                child: SizedBox(
                  width: 40,
                  height: 36,
                  child: Icon(icon, size: 20),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ------------------------------------------------------------ toolbar

  Widget _toolbar() {
    final sel = _selected;
    final text = _textTarget || _editing != null;
    final shape =
        sel != null &&
        sel.kind == PptxShapeKind.text &&
        (sel.geom != null || sel.fill != null);
    final align = _paraAlign;
    return OfficeToolbar(
      accent: _accent,
      trailing: [
        TbButton(
          icon: Icons.picture_as_pdf_outlined,
          tooltip: 'Download as PDF (Ctrl+Shift+E)',
          onTap: () => unawaited(_exportPdf()),
          accent: _accent,
        ),
        TbPrimary(
          icon: _dirty ? Icons.save_outlined : Icons.check_rounded,
          label: _dirty ? 'Save' : 'Saved',
          accent: _dirty ? _accent : const Color(0xFF64748B),
          tooltip: 'Save (Ctrl+S)',
          onTap: () => unawaited(_save()),
        ),
        const SizedBox(width: 4),
        MenuAnchor(
          menuChildren: [
            officeItem(
              'Present from beginning',
              () => unawaited(_present(fromStart: true)),
              icon: Icons.first_page,
              shortcut: const SingleActivator(LogicalKeyboardKey.f5),
            ),
            officeItem(
              'Present from current slide',
              () => unawaited(_present()),
              icon: Icons.play_arrow,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.f5,
                shift: true,
              ),
            ),
            officeItem(
              'Presenter view',
              () => unawaited(_present(presenter: true)),
              icon: Icons.co_present_outlined,
            ),
          ],
          builder: (context, c, _) => TbPrimary(
            icon: Icons.slideshow_rounded,
            label: 'Slideshow',
            accent: _accent,
            tooltip: 'Present (F5)  ·  right-click for options',
            onTap: () => unawaited(_present(fromStart: true)),
          ).withMenu(c),
        ),
      ],
      children: [
        TbButton(
          icon: Icons.add_box_outlined,
          tooltip: 'New slide (Ctrl+M)',
          accent: _accent,
          onTap: _newSlide,
        ),
        TbButton(
          icon: Icons.arrow_drop_down,
          tooltip: 'New slide with layout',
          accent: _accent,
          menu: [
            for (final l in doc.layouts)
              MenuItemButton(
                onPressed: () => _newSlide(l),
                child: Text(l.name),
              ),
          ],
          size: 22,
        ),
        TbButton(
          icon: Icons.undo,
          tooltip: 'Undo (Ctrl+Z)',
          accent: _accent,
          onTap: _undo.isEmpty ? null : _undoOp,
        ),
        TbButton(
          icon: Icons.redo,
          tooltip: 'Redo (Ctrl+Y)',
          accent: _accent,
          onTap: _redo.isEmpty ? null : _redoOp,
        ),
        TbButton(
          icon: Icons.print_outlined,
          tooltip: 'Print (Ctrl+P)',
          accent: _accent,
          onTap: () => unawaited(_print()),
        ),
        TbCombo(
          value: _zoom == 1 ? 'Fit' : '${(_zoom * 100).round()}%',
          items: const ['Fit', '50%', '75%', '150%', '200%'],
          width: 70,
          tooltip: 'Zoom',
          onSelected: (v) => setState(
            () => _zoom = v == 'Fit'
                ? 1
                : ((double.tryParse(v.replaceAll('%', '')) ?? 100) / 100).clamp(
                    0.25,
                    4.0,
                  ),
          ),
        ),
        const TbDivider(),
        TbButton(
          icon: Icons.text_fields,
          tooltip: 'Text box',
          accent: _accent,
          onTap: _addTextBox,
        ),
        TbButton(
          icon: Icons.add_photo_alternate_outlined,
          tooltip: 'Image',
          accent: _accent,
          onTap: _addPicture,
        ),
        TbButton(
          icon: Icons.category_outlined,
          tooltip: 'Shape',
          accent: _accent,
          menu: [_shapeGrid()],
        ),
        TbButton(
          icon: Icons.horizontal_rule,
          tooltip: 'Line',
          accent: _accent,
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.horizontal_rule, size: 18),
              onPressed: () => _addShape('line'),
              child: const Text('Line'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.arrow_right_alt, size: 18),
              onPressed: () => _addShape('arrow'),
              child: const Text('Arrow'),
            ),
          ],
        ),
        TbButton(
          icon: Icons.table_chart_outlined,
          tooltip: 'Table',
          accent: _accent,
          menu: [_GridPicker(onPick: _addTable)],
        ),
        if (sel == null && _editing == null) ...[
          const TbDivider(),
          TbButton(
            icon: Icons.format_color_fill,
            label: 'Background',
            tooltip: 'Slide background',
            accent: _accent,
            active: _panel == _Panel.background,
            onTap: () => _togglePanel(_Panel.background),
          ),
          TbButton(
            icon: Icons.dashboard_outlined,
            label: 'Layout',
            tooltip: 'Apply layout',
            accent: _accent,
            menu: [
              for (final l in doc.layouts)
                MenuItemButton(
                  onPressed: () => _changeLayout(l),
                  child: Text(l.name),
                ),
            ],
          ),
          TbButton(
            icon: Icons.palette_outlined,
            label: 'Theme',
            tooltip: 'Themes',
            accent: _accent,
            active: _panel == _Panel.theme,
            onTap: () => _togglePanel(_Panel.theme),
          ),
          TbButton(
            icon: Icons.animation,
            label: 'Transition',
            tooltip: 'Slide transition',
            accent: _accent,
            active: _panel == _Panel.transition,
            onTap: () => _togglePanel(_Panel.transition),
          ),
          TbButton(
            icon: Icons.auto_awesome_motion_outlined,
            label: 'Animations',
            tooltip: 'Object animations on this slide',
            accent: _accent,
            active: _panel == _Panel.animation,
            onTap: () => _togglePanel(_Panel.animation),
          ),
        ],
        if (shape || (sel != null && sel.geom == 'line')) ...[
          const TbDivider(),
          if (sel.geom != 'line')
            TbColorButton(
              icon: Icons.format_color_fill,
              tooltip: 'Fill color',
              noneLabel: 'Transparent',
              color: doc.resolve(sel.fill) ?? Colors.transparent,
              onPicked: (c) => c == null
                  ? _shapeStyle(clearFill: true)
                  : _shapeStyle(fill: _hex(c)),
            ),
          TbColorButton(
            icon: Icons.border_color_outlined,
            tooltip: 'Border color',
            noneLabel: 'Transparent',
            color: doc.resolve(sel.line) ?? Colors.transparent,
            onPicked: (c) => c == null
                ? _shapeStyle(clearLine: true)
                : _shapeStyle(line: _hex(c)),
          ),
          TbButton(
            icon: Icons.line_weight,
            tooltip: 'Border weight',
            accent: _accent,
            menu: [
              for (final pt in [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0])
                MenuItemButton(
                  onPressed: () => _shapeStyle(width: pt * emuPerPt),
                  child: Row(
                    children: [
                      Container(width: 60, height: pt, color: Colors.black87),
                      const SizedBox(width: 10),
                      Text('${_fmtPt(pt)} pt'),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (sel != null && sel.kind == PptxShapeKind.picture) ...[
          const TbDivider(),
          TbColorButton(
            icon: Icons.border_color_outlined,
            tooltip: 'Border color',
            noneLabel: 'None',
            color: doc.resolve(sel.line) ?? Colors.transparent,
            onPicked: (c) => c == null
                ? _shapeStyle(clearLine: true)
                : _shapeStyle(line: _hex(c), width: sel.lineWidth ?? 19050),
          ),
          TbButton(
            icon: Icons.tune,
            label: 'Format options',
            tooltip: 'Size, position and rotation',
            accent: _accent,
            onTap: () => _togglePanel(_Panel.format),
          ),
        ],
        if (sel != null && sel.kind == PptxShapeKind.table) ...[
          const TbDivider(),
          TbButton(
            icon: Icons.edit_note,
            label: 'Edit table',
            tooltip: 'Edit cells, add or remove rows and columns',
            accent: _accent,
            active: true,
            onTap: _editTable,
          ),
        ],
        if (text) ...[
          const TbDivider(),
          TbCombo(
            value: _fontName,
            items: OfficeFonts.instance.allNames,
            width: 124,
            tooltip: 'Font',
            itemStyle: (f) {
              final fam = OfficeFonts.instance.familyFor(f);
              return fam == null ? null : TextStyle(fontFamily: fam);
            },
            onSelected: (f) => _fmt('font', f),
          ),
          TbButton(
            icon: Icons.remove,
            tooltip: 'Decrease font size',
            accent: _accent,
            onTap: () => _grow(false),
          ),
          TbCombo(
            value: _fmtPt(_fontPt),
            items: _fontSizes,
            width: 52,
            tooltip: 'Font size',
            onSelected: (v) {
              final d = double.tryParse(v);
              if (d != null && d > 0 && d < 4000) _fmt('size', _fmtPt(d));
            },
          ),
          TbButton(
            icon: Icons.add,
            tooltip: 'Increase font size',
            accent: _accent,
            onTap: () => _grow(true),
          ),
          const TbDivider(),
          TbButton(
            icon: Icons.format_bold,
            tooltip: 'Bold (Ctrl+B)',
            accent: _accent,
            active: _isOn('bold'),
            onTap: () => _fmt('bold', _isOn('bold') ? null : true),
          ),
          TbButton(
            icon: Icons.format_italic,
            tooltip: 'Italic (Ctrl+I)',
            accent: _accent,
            active: _isOn('italic'),
            onTap: () => _fmt('italic', _isOn('italic') ? null : true),
          ),
          TbButton(
            icon: Icons.format_underline,
            tooltip: 'Underline (Ctrl+U)',
            accent: _accent,
            active: _isOn('underline'),
            onTap: () => _fmt('underline', _isOn('underline') ? null : true),
          ),
          TbButton(
            icon: Icons.strikethrough_s,
            tooltip: 'Strikethrough',
            accent: _accent,
            active: _isOn('strike'),
            onTap: () => _fmt('strike', _isOn('strike') ? null : true),
          ),
          TbColorButton(
            icon: Icons.format_color_text,
            tooltip: 'Text color',
            color: _textColor,
            onPicked: (c) => _fmt('color', c == null ? null : '#${_hex(c)}'),
          ),
          const TbDivider(),
          TbButton(
            icon: switch (align) {
              'center' => Icons.format_align_center,
              'right' => Icons.format_align_right,
              'justify' => Icons.format_align_justify,
              _ => Icons.format_align_left,
            },
            tooltip: 'Align',
            accent: _accent,
            menu: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TbButton(
                    icon: Icons.format_align_left,
                    tooltip: 'Left',
                    accent: _accent,
                    active: align == null,
                    onTap: () => _paraFmt('align', null),
                  ),
                  TbButton(
                    icon: Icons.format_align_center,
                    tooltip: 'Center',
                    accent: _accent,
                    active: align == 'center',
                    onTap: () => _paraFmt('align', 'center'),
                  ),
                  TbButton(
                    icon: Icons.format_align_right,
                    tooltip: 'Right',
                    accent: _accent,
                    active: align == 'right',
                    onTap: () => _paraFmt('align', 'right'),
                  ),
                  TbButton(
                    icon: Icons.format_align_justify,
                    tooltip: 'Justify',
                    accent: _accent,
                    active: align == 'justify',
                    onTap: () => _paraFmt('align', 'justify'),
                  ),
                ],
              ),
            ],
          ),
          TbButton(
            icon: Icons.vertical_align_center,
            tooltip: 'Vertical align',
            accent: _accent,
            menu: [
              for (final (v, l, i) in [
                ('t', 'Top', Icons.vertical_align_top),
                ('ctr', 'Middle', Icons.vertical_align_center),
                ('b', 'Bottom', Icons.vertical_align_bottom),
              ])
                MenuItemButton(
                  leadingIcon: Icon(i, size: 18),
                  onPressed: () {
                    final s = _editing ?? _selected;
                    if (s == null) return;
                    _checkpoint();
                    s
                      ..anchor = v
                      ..dirtyText = true;
                    _changed();
                  },
                  child: Text(l),
                ),
            ],
          ),
          TbButton(
            icon: Icons.format_line_spacing,
            tooltip: 'Line spacing',
            accent: _accent,
            menu: _spacingItems(),
          ),
          TbButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bulleted list',
            accent: _accent,
            onTap: () => _paraFmt('list', 'bullet'),
          ),
          TbButton(
            icon: Icons.format_list_numbered,
            tooltip: 'Numbered list',
            accent: _accent,
            onTap: () => _paraFmt('list', 'ordered'),
          ),
          TbButton(
            icon: Icons.format_indent_decrease,
            tooltip: 'Decrease indent',
            accent: _accent,
            onTap: () => _paraFmt('indent', false),
          ),
          TbButton(
            icon: Icons.format_indent_increase,
            tooltip: 'Increase indent',
            accent: _accent,
            onTap: () => _paraFmt('indent', true),
          ),
        ],
        if (sel != null) ...[
          const TbDivider(),
          TbButton(
            icon: Icons.auto_awesome_motion_outlined,
            label: 'Animate',
            tooltip: 'Add an animation to this object',
            accent: _accent,
            active: _panel == _Panel.animation,
            onTap: () {
              setState(() => _panel = _Panel.animation);
              if (!_slide.animations.any((a) => identical(a.shape, sel)))
                _addAnimation(sel);
            },
          ),
          TbButton(
            icon: Icons.layers_outlined,
            tooltip: 'Order',
            accent: _accent,
            menu: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.flip_to_front, size: 18),
                onPressed: () => _order('front'),
                child: const Text('Bring to front'),
              ),
              MenuItemButton(
                onPressed: () => _order('forward'),
                child: const Text('Bring forward'),
              ),
              MenuItemButton(
                onPressed: () => _order('backward'),
                child: const Text('Send backward'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.flip_to_back, size: 18),
                onPressed: () => _order('back'),
                child: const Text('Send to back'),
              ),
            ],
          ),
          TbButton(
            icon: Icons.tune,
            tooltip: 'Format options',
            accent: _accent,
            active: _panel == _Panel.format,
            onTap: () => _togglePanel(_Panel.format),
          ),
          TbButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete (Del)',
            accent: _accent,
            onTap: sel.locked ? null : _delete,
          ),
        ],
      ],
    );
  }

  Color get _textColor {
    final q = _qsel['color']?.value;
    if (q is String && q.length == 7)
      return Color(int.parse('FF${q.substring(1)}', radix: 16));
    final s = _selected;
    return doc.resolve(_firstRun?.color ?? s?.fontColor ?? '@tx1') ??
        Colors.black;
  }

  void _togglePanel(_Panel p) =>
      setState(() => _panel = _panel == p ? _Panel.none : p);

  // -------------------------------------------------------- filmstrip

  Widget _strip(ThemeData theme) {
    if (_thumbs.length > doc.slides.length) {
      final live = doc.slides.toSet();
      _thumbs.removeWhere((k, _) => !live.contains(k));
    }
    final muted = DsColors.textSecondary(theme.brightness);
    return OfficeSidePanel(
      width: 212,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              buildDefaultDragHandles: false,
              itemCount: doc.slides.length,
              onReorderItem: (a, b) => _moveSlide(a, b),
              itemBuilder: (context, i) {
                final s = doc.slides[i];
                final on = i == _current;
                return ReorderableDragStartListener(
                  key: ValueKey(s.path),
                  index: i,
                  child: GestureDetector(
                    onTap: () => _goto(i),
                    onSecondaryTapUp: (d) => _slideMenu(d.globalPosition, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Column(
                              children: [
                                Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: on ? _accent : muted,
                                    fontWeight: on ? FontWeight.w700 : null,
                                  ),
                                ),
                                if (s.hidden)
                                  Icon(
                                    Icons.visibility_off_outlined,
                                    size: 13,
                                    color: muted,
                                  ),
                                if (s.transition != null)
                                  Icon(Icons.animation, size: 13, color: muted),
                                if (s.animations.isNotEmpty)
                                  Icon(
                                    Icons.auto_awesome_motion_outlined,
                                    size: 13,
                                    color: muted,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: on
                                      ? _accent
                                      : DsColors.border(theme.brightness),
                                  width: on ? 2.5 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Opacity(
                                  opacity: s.hidden ? 0.45 : 1,
                                  child: _thumbs[s] ??= LayoutBuilder(
                                    builder: (context, c) => RepaintBoundary(
                                      child: IgnorePointer(
                                        child: PptxSlideView(
                                          doc: doc,
                                          slide: s,
                                          width: c.maxWidth,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: DsColors.border(theme.brightness)),
          const OfficePanelHeader('Details'),
          OfficeStat(
            'Slide',
            '${_current + 1} of ${doc.slides.length}',
            icon: Icons.slideshow_outlined,
          ),
          OfficeStat(
            'Layout',
            doc.layouts
                    .where((l) => l.path == _slide.layoutPath)
                    .firstOrNull
                    ?.name ??
                '—',
            icon: Icons.dashboard_outlined,
          ),
          OfficeStat('Theme', doc.theme.name, icon: Icons.palette_outlined),
          OfficeStat('Size', _sizeName(), icon: Icons.aspect_ratio),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  String _sizeName() {
    final r = doc.width / doc.height;
    if ((r - 16 / 9).abs() < 0.02) return '16:9';
    if ((r - 4 / 3).abs() < 0.02) return '4:3';
    if ((r - 16 / 10).abs() < 0.02) return '16:10';
    return '${(doc.width / 360000).toStringAsFixed(1)} × ${(doc.height / 360000).toStringAsFixed(1)} cm';
  }

  Future<void> _slideMenu(Offset at, int i) async {
    _goto(i);
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(value: 'new', child: Text('New slide')),
        const PopupMenuItem(value: 'dup', child: Text('Duplicate slide')),
        PopupMenuItem(
          value: 'del',
          enabled: doc.slides.length > 1,
          child: const Text('Delete slide'),
        ),
        PopupMenuItem(
          value: 'skip',
          child: Text(_slide.hidden ? 'Unskip slide' : 'Skip slide'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'bg', child: Text('Change background')),
        const PopupMenuItem(value: 'tr', child: Text('Transition')),
      ],
    );
    switch (r) {
      case 'new':
        _newSlide();
      case 'dup':
        _duplicateSlide();
      case 'del':
        _deleteSlide();
      case 'skip':
        _toggleHidden();
      case 'bg':
        setState(() => _panel = _Panel.background);
      case 'tr':
        setState(() => _panel = _Panel.transition);
    }
  }

  Widget _sorterView(ThemeData theme) => GridView.builder(
    padding: const EdgeInsets.all(24),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 260,
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      childAspectRatio: doc.aspect * 0.86,
    ),
    itemCount: doc.slides.length,
    itemBuilder: (context, i) {
      final s = doc.slides[i];
      return GestureDetector(
        onTap: () => setState(() => _current = i),
        onDoubleTap: () => setState(() {
          _current = i;
          _sorter = false;
        }),
        onSecondaryTapUp: (d) => _slideMenu(d.globalPosition, i),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: i == _current
                        ? _accent
                        : DsColors.border(theme.brightness),
                    width: i == _current ? 3 : 1,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, c) => IgnorePointer(
                    child: Opacity(
                      opacity: s.hidden ? 0.45 : 1,
                      child: PptxSlideView(
                        doc: doc,
                        slide: s,
                        width: c.maxWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${i + 1}${s.hidden ? '  (skipped)' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    },
  );

  // ------------------------------------------------------------ canvas

  Widget _canvas(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = (c.maxWidth - 64).clamp(200.0, 4000.0);
        final maxH = (c.maxHeight - 48).clamp(120.0, 4000.0);
        final fit = (maxW / maxH > doc.aspect) ? maxH * doc.aspect : maxW;
        final width = fit * _zoom;
        _scale = width / doc.width;
        final slideView = ValueListenableBuilder<int>(
          valueListenable: _live,
          builder: (context, _, _) => Stack(
            key: _slideKey,
            clipBehavior: Clip.none,
            children: [
              PptxSlideView(
                doc: doc,
                slide: _slide,
                width: width,
                showPrompts: true,
                hideShape: _editing,
                overlayBuilder: (s, rect) => _hitBox(s, rect),
              ),
              if (_editing != null) _textEditor(_editing!),
              if (_grid)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GridPainter(width / 16)),
                  ),
                ),
              if (_guidesX.isNotEmpty || _guidesY.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GuidePainter(
                        _guidesX.map((x) => x * _scale).toList(),
                        _guidesY.map((y) => y * _scale).toList(),
                      ),
                    ),
                  ),
                ),
              if (_selected != null && _editing == null && !_selected!.locked)
                ..._handles(_selected!),
            ],
          ),
        );
        return Focus(
          focusNode: _canvasFocus,
          autofocus: true,
          onKeyEvent: _onCanvasKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_editing != null) _endEdit();
              setState(() => _selected = null);
              _canvasFocus.requestFocus();
            },
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: c.maxWidth,
                    minHeight: c.maxHeight,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 14,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: slideView,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  KeyEventResult _onCanvasKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_editing != null) {
      // Esc leaves the text (the object stays selected); other keys type.
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        _endEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl) {
      switch (k) {
        case LogicalKeyboardKey.keyZ:
          shift ? _redoOp() : _undoOp();
        case LogicalKeyboardKey.keyY:
          _redoOp();
        case LogicalKeyboardKey.keyC:
          _copy();
        case LogicalKeyboardKey.keyX:
          _copy(cut: true);
        case LogicalKeyboardKey.keyV:
          _paste();
        case LogicalKeyboardKey.keyD:
          _selected == null ? _duplicateSlide() : _duplicate();
        case LogicalKeyboardKey.keyB:
          _fmt('bold', _isOn('bold') ? null : true);
        case LogicalKeyboardKey.keyI:
          _fmt('italic', _isOn('italic') ? null : true);
        case LogicalKeyboardKey.keyU:
          _fmt('underline', _isOn('underline') ? null : true);
        case LogicalKeyboardKey.arrowUp:
          _order(shift ? 'front' : 'forward');
        case LogicalKeyboardKey.arrowDown:
          _order(shift ? 'back' : 'backward');
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (_selected != null) {
        _delete();
      } else {
        _deleteSlide();
      }
      return KeyEventResult.handled;
    }
    final step = shift ? doc.width / 50 : doc.width / 400;
    final d = switch (k) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    final s = _selected;
    if (d != null && s != null && !s.locked) {
      _checkpoint();
      s
        ..x += d.dx
        ..y += d.dy
        ..dirtyGeometry = true;
      _changed();
      return KeyEventResult.handled;
    }
    if (d != null ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.pageUp) {
      final next =
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.pageDown;
      _goto(_current + (next ? 1 : -1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter && s != null) {
      s.kind == PptxShapeKind.table ? _editTable() : _beginEdit(s);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() => _selected = null);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab && _slide.shapes.isNotEmpty) {
      final i = _selected == null ? -1 : _slide.shapes.indexOf(_selected!);
      setState(() => _selected = _slide.shapes[(i + 1) % _slide.shapes.length]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Transparent hit area per object: click selects, double-click edits,
  /// dragging moves (with smart guides).
  Widget? _hitBox(PptxShape s, Rect rect) {
    if (identical(s, _editing)) return null;
    final selected = identical(s, _selected);
    final r = s.geom == 'line' ? rect.inflate(6) : rect;
    return Positioned.fromRect(
      rect: Rect.fromLTWH(
        r.left,
        r.top,
        math.max(r.width, 8),
        math.max(r.height, 8),
      ),
      child: Transform.rotate(
        angle: s.rotation * math.pi / 180,
        child: MouseRegion(
          cursor: s.locked
              ? SystemMouseCursors.basic
              : (selected ? SystemMouseCursors.move : SystemMouseCursors.click),
          // Selection happens on press, without waiting to see whether a
          // double-click (edit) follows.
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kPrimaryButton && !identical(_selected, s))
                _select(s);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Claims the click so the slide background does not deselect.
              onTap: () {},
              onDoubleTap: () =>
                  s.kind == PptxShapeKind.table ? _editTable() : _beginEdit(s),
              onPanStart: s.locked
                  ? null
                  : (_) {
                      _select(s);
                      _checkpoint();
                      _dragBase = Rect.fromLTWH(s.x, s.y, s.w, s.h);
                      _dragAcc = Offset.zero;
                    },
              onPanUpdate: s.locked ? null : (d) => _moveBy(s, d.delta),
              onPanEnd: s.locked ? null : (_) => _dragDone(s),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? _accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _moveBy(PptxShape s, Offset deltaPx) {
    final base = _dragBase;
    if (base == null) return;
    _dragAcc += deltaPx / _scale;
    var x = base.left + _dragAcc.dx, y = base.top + _dragAcc.dy;
    // Smart guides: snap edges and centres to the slide and other objects.
    final tol = 6 / _scale;
    final xs = <double>[0, doc.width / 2, doc.width];
    final ys = <double>[0, doc.height / 2, doc.height];
    for (final o in _slide.shapes) {
      if (identical(o, s)) continue;
      xs.addAll([o.x, o.x + o.w / 2, o.x + o.w]);
      ys.addAll([o.y, o.y + o.h / 2, o.y + o.h]);
    }
    final gx = <double>[], gy = <double>[];
    if (!HardwareKeyboard.instance.isAltPressed) {
      double? snap(
        double pos,
        double size,
        List<double> lines,
        List<double> out,
      ) {
        for (final edge in [0.0, size / 2, size]) {
          for (final l in lines) {
            if ((pos + edge - l).abs() < tol) {
              out.add(l);
              return l - edge;
            }
          }
        }
        return null;
      }

      x = snap(x, s.w, xs, gx) ?? x;
      y = snap(y, s.h, ys, gy) ?? y;
    }
    s
      ..x = x
      ..y = y;
    _guidesX = gx;
    _guidesY = gy;
    _live.value++;
  }

  void _dragDone(PptxShape s) {
    s.dirtyGeometry = true;
    _guidesX = [];
    _guidesY = [];
    _dragBase = null;
    _changed();
  }

  /// Eight resize handles and a rotation knob for the selected object.
  List<Widget> _handles(PptxShape s) {
    final rect = Rect.fromLTWH(
      s.x * _scale,
      s.y * _scale,
      s.w * _scale,
      s.h * _scale,
    );
    final line = s.geom == 'line';
    final points = line
        ? [Alignment.topLeft, Alignment.bottomRight]
        : [
            Alignment.topLeft,
            Alignment.topCenter,
            Alignment.topRight,
            Alignment.centerLeft,
            Alignment.centerRight,
            Alignment.bottomLeft,
            Alignment.bottomCenter,
            Alignment.bottomRight,
          ];
    Offset rotated(Offset local) {
      final c = rect.center;
      final a = s.rotation * math.pi / 180;
      final v = local - c;
      return c +
          Offset(
            v.dx * math.cos(a) - v.dy * math.sin(a),
            v.dx * math.sin(a) + v.dy * math.cos(a),
          );
    }

    final out = <Widget>[];
    for (final al in points) {
      final pos = rotated(al.withinRect(rect));
      final corner = al.x != 0 && al.y != 0;
      out.add(
        Positioned(
          left: pos.dx - 7,
          top: pos.dy - 7,
          child: MouseRegion(
            cursor: al.x == 0
                ? SystemMouseCursors.resizeUpDown
                : al.y == 0
                ? SystemMouseCursors.resizeLeftRight
                : (al.x == al.y
                      ? SystemMouseCursors.resizeUpLeftDownRight
                      : SystemMouseCursors.resizeUpRightDownLeft),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _checkpoint();
                _dragBase = Rect.fromLTWH(s.x, s.y, s.w, s.h);
                _dragAcc = Offset.zero;
              },
              onPanUpdate: (d) => _resize(s, al, d.delta),
              onPanEnd: (_) => _dragDone(s),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _accent, width: 1.6),
                  shape: corner ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: corner ? null : BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!line) {
      final knob = rotated(Offset(rect.center.dx, rect.top - 26));
      out.add(
        Positioned(
          left: knob.dx - 8,
          top: knob.dy - 8,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _checkpoint();
                _rotBase = s.rotation;
              },
              onPanUpdate: (d) {
                // Angle of the pointer around the object's centre.
                final center = rect.center;
                final local = _slideLocal(d.globalPosition);
                if (local == null) return;
                var deg =
                    math.atan2(local.dy - center.dy, local.dx - center.dx) *
                        180 /
                        math.pi +
                    90;
                if (HardwareKeyboard.instance.isShiftPressed)
                  deg = (deg / 15).round() * 15.0;
                s.rotation = (deg + 360) % 360;
                _live.value++;
              },
              onPanEnd: (_) {
                if (s.rotation != _rotBase) _dragDone(s);
              },
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.rotate_right,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  final _slideKey = GlobalKey();

  Offset? _slideLocal(Offset global) {
    final box = _slideKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _resize(PptxShape s, Alignment al, Offset deltaPx) {
    final base = _dragBase;
    if (base == null) return;
    // Work in the object's own (unrotated) axes.
    final a = -s.rotation * math.pi / 180;
    final d = Offset(
      deltaPx.dx * math.cos(a) - deltaPx.dy * math.sin(a),
      deltaPx.dx * math.sin(a) + deltaPx.dy * math.cos(a),
    );
    _dragAcc += d / _scale;
    var left = base.left,
        top = base.top,
        right = base.right,
        bottom = base.bottom;
    if (s.geom == 'line') {
      if (al == Alignment.topLeft) {
        left += _dragAcc.dx;
        top += _dragAcc.dy;
      } else {
        right += _dragAcc.dx;
        bottom += _dragAcc.dy;
      }
      s
        ..x = math.min(left, right)
        ..y = math.min(top, bottom)
        ..w = (right - left).abs()
        ..h = (bottom - top).abs()
        ..flipH = right < left
        ..flipV = bottom < top;
      _live.value++;
      return;
    }
    if (al.x < 0) left += _dragAcc.dx;
    if (al.x > 0) right += _dragAcc.dx;
    if (al.y < 0) top += _dragAcc.dy;
    if (al.y > 0) bottom += _dragAcc.dy;
    final minSize = doc.width * 0.01;
    var w = math.max(minSize, right - left),
        h = math.max(minSize, bottom - top);
    final keep =
        (s.kind == PptxShapeKind.picture) !=
        HardwareKeyboard.instance.isShiftPressed;
    if (keep && al.x != 0 && al.y != 0) {
      final k = base.width / base.height;
      if (w / h > k) {
        h = w / k;
      } else {
        w = h * k;
      }
    }
    s
      ..x = al.x < 0 ? base.right - w : left
      ..y = al.y < 0 ? base.bottom - h : top
      ..w = w
      ..h = h;
    _live.value++;
  }

  Widget _textEditor(PptxShape s) {
    final rect = Rect.fromLTWH(
      s.x * _scale,
      s.y * _scale,
      s.w * _scale,
      s.h * _scale,
    );
    final q = _quill!;
    final ptToPx = _ptToPx;
    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: s.rotation * math.pi / 180,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: PptxShapeView(
                  doc: doc,
                  shape: PptxShape(
                    kind: PptxShapeKind.text,
                    x: 0,
                    y: 0,
                    w: s.w,
                    h: s.h,
                    geom: s.geom,
                    fill: s.fill,
                    line: s.line,
                    lineWidth: s.lineWidth,
                  ),
                  ptToPx: ptToPx,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _accent, width: 1.5),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 7.2 * ptToPx,
                    vertical: 3.6 * ptToPx,
                  ),
                  child: Align(
                    alignment: switch (s.anchor) {
                      'ctr' => Alignment.center,
                      'b' => Alignment.bottomCenter,
                      _ => Alignment.topCenter,
                    },
                    child: Theme(
                      data: ThemeData.light(useMaterial3: true),
                      child: QuillEditor(
                        key: _quillKey,
                        controller: q,
                        focusNode: _quillFocus,
                        scrollController: ScrollController(),
                        config: QuillEditorConfig(
                          scrollable: false,
                          expands: false,
                          placeholder: 'Type here',
                          // Esc leaves the text box (Quill would only hide its toolbar).
                          // ignore: experimental_member_use
                          onKeyPressed: (event, _) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape) {
                              _endEdit();
                              return KeyEventResult.handled;
                            }
                            return null;
                          },
                          customStyles: DefaultStyles.getInstance(context)
                              .merge(
                                DefaultStyles(
                                  paragraph: DefaultTextBlockStyle(
                                    TextStyle(
                                      fontSize: s.sizeForLevel(0) * ptToPx,
                                      color:
                                          doc.resolve(s.fontColor ?? '@tx1') ??
                                          Colors.black,
                                      height: 1.18,
                                    ),
                                    HorizontalSpacing.zero,
                                    VerticalSpacing.zero,
                                    VerticalSpacing.zero,
                                    null,
                                  ),
                                ),
                              ),
                          customStyleBuilder: (a) {
                            if (a.key == 'size') {
                              final v = double.tryParse('${a.value}');
                              if (v != null)
                                return TextStyle(
                                  fontSize: v * s.fontScale * ptToPx,
                                );
                            }
                            if (a.key == 'font' && a.value is String) {
                              final f = OfficeFonts.instance.familyFor(
                                a.value as String,
                              );
                              if (f != null) return TextStyle(fontFamily: f);
                            }
                            return const TextStyle();
                          },
                        ),
                      ),
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

  Widget _notesPane(ThemeData theme) => Container(
    height: 110,
    decoration: BoxDecoration(
      color: officeBar(theme.brightness),
      border: Border(top: BorderSide(color: DsColors.border(theme.brightness))),
    ),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: TextField(
      controller: _notes,
      maxLines: null,
      expands: true,
      style: const TextStyle(fontSize: 13.5, height: 1.4),
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Click to add speaker notes',
      ),
      onChanged: (v) {
        _slide
          ..notes = v
          ..notesDirty = true;
        if (!_dirty) setState(() => _dirty = true);
      },
    ),
  );

  // -------------------------------------------------------- side panels

  Widget _sidePanel(ThemeData theme) {
    final title = switch (_panel) {
      _Panel.theme => 'Themes',
      _Panel.transition => 'Transition',
      _Panel.animation => 'Animations',
      _Panel.background => 'Background',
      _Panel.format => 'Format options',
      _Panel.none => '',
    };
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: officeBar(theme.brightness),
        border: Border(
          left: BorderSide(color: DsColors.border(theme.brightness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TbButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  accent: _accent,
                  onTap: () => setState(() => _panel = _Panel.none),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_panel) {
              _Panel.theme => _themePanel(),
              _Panel.transition => _transitionPanel(theme),
              _Panel.animation => _animationPanel(theme),
              _Panel.background => _backgroundPanel(),
              _Panel.format => _formatPanel(),
              _Panel.none => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Widget _themePanel() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    children: [
      for (final t in kPptxDesigns)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _applyTheme(t),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 140,
                  decoration: BoxDecoration(
                    color: Color(
                      0xFF000000 | int.parse(t.colors['lt1']!, radix: 16),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: doc.theme.name == t.name
                          ? _accent
                          : const Color(0x22000000),
                      width: doc.theme.name == t.name ? 3 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(
                          fontSize: 34,
                          fontFamily: OfficeFonts.instance.familyFor(t.major),
                          color: Color(
                            0xFF000000 | int.parse(t.colors['dk1']!, radix: 16),
                          ),
                        ),
                      ),
                      Text(
                        'Title and body text',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: OfficeFonts.instance.familyFor(t.minor),
                          color: Color(
                            0xFF000000 | int.parse(t.colors['dk2']!, radix: 16),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          for (var k = 1; k <= 6; k++)
                            Expanded(
                              child: Container(
                                height: 10,
                                margin: const EdgeInsets.only(right: 3),
                                color: Color(
                                  0xFF000000 |
                                      int.parse(
                                        t.colors['accent$k']!,
                                        radix: 16,
                                      ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _transitionPanel(ThemeData theme) {
    final s = _slide;
    final cur = s.transition ?? 'none';
    final dirs = const {'push', 'wipe', 'cover', 'pull'}.contains(cur);
    final prev = _current > 0 ? _current - 1 : _current;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: w,
                height: w / doc.aspect,
                child: Stack(
                  children: [
                    PptxSlideView(doc: doc, slide: doc.slides[prev], width: w),
                    _TransitionPreview(
                      key: ValueKey(_transitionPreview),
                      doc: doc,
                      slide: s,
                      width: w,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _transitionPreview++),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (id, label, icon) in _transitions)
              ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: cur == id,
                onSelected: (_) => _setTransition(type: id),
              ),
          ],
        ),
        if (dirs) ...[
          const SizedBox(height: 14),
          const Text(
            'Direction',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'l',
                icon: Icon(Icons.arrow_back),
                tooltip: 'From right',
              ),
              ButtonSegment(
                value: 'r',
                icon: Icon(Icons.arrow_forward),
                tooltip: 'From left',
              ),
              ButtonSegment(
                value: 'u',
                icon: Icon(Icons.arrow_upward),
                tooltip: 'From bottom',
              ),
              ButtonSegment(
                value: 'd',
                icon: Icon(Icons.arrow_downward),
                tooltip: 'From top',
              ),
            ],
            selected: {s.transitionDir ?? 'l'},
            onSelectionChanged: (v) => _setTransition(dir: v.first),
          ),
        ],
        const SizedBox(height: 14),
        const Text('Speed', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'slow', label: Text('Slow')),
            ButtonSegment(value: 'med', label: Text('Medium')),
            ButtonSegment(value: 'fast', label: Text('Fast')),
          ],
          selected: {s.transitionSpeed},
          onSelectionChanged: (v) => _setTransition(speed: v.first),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Advance automatically'),
          subtitle: Text(
            s.advanceAfterMs == null
                ? 'On click'
                : 'After ${(s.advanceAfterMs! / 1000).toStringAsFixed(s.advanceAfterMs! % 1000 == 0 ? 0 : 1)} s',
          ),
          value: s.advanceAfterMs != null,
          onChanged: (on) => on
              ? _setTransition(advance: 5000)
              : _setTransition(clearAdvance: true),
        ),
        if (s.advanceAfterMs != null)
          Slider(
            value: (s.advanceAfterMs! / 1000).clamp(1, 60).toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '${s.advanceAfterMs! ~/ 1000} s',
            onChanged: (v) {
              s
                ..advanceAfterMs = (v * 1000).round()
                ..dirtyTransition = true;
              _changed();
            },
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _setTransition(all: true),
          icon: const Icon(Icons.done_all),
          label: const Text('Apply to all slides'),
        ),
      ],
    );
  }

  Widget _animationPanel(ThemeData theme) {
    final anims = _slide.animations;
    final sel = _selected;
    final muted = DsColors.textSecondary(theme.brightness);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        LayoutBuilder(
          builder: (context, c) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _AnimPreview(
              key: ValueKey('anim$_animPreview'),
              doc: doc,
              slide: _slide,
              width: c.maxWidth,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: anims.isEmpty
                  ? null
                  : () => setState(() => _animPreview++),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: sel == null || sel.locked
                    ? null
                    : () => _addAnimation(sel),
                icon: const Icon(Icons.add),
                label: const Text('Add animation'),
              ),
            ),
          ],
        ),
        if (sel == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Select an object on the slide to animate it.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        const SizedBox(height: 10),
        for (var i = 0; i < anims.length; i++) _animCard(anims, i, theme),
      ],
    );
  }

  Widget _animCard(List<PptxAnim> anims, int i, ThemeData theme) {
    final a = anims[i];
    final on = identical(a.shape, _selected);
    final dirs = a.effect == 'fly' || a.effect == 'wipe';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: on ? _accent : DsColors.border(theme.brightness),
          width: on ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: _accent.withValues(alpha: 0.15),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontSize: 11, color: _accent),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selected = a.shape),
                    child: Text(
                      '${a.label} · ${a.shape.label}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                TbButton(
                  icon: Icons.arrow_upward,
                  tooltip: 'Earlier',
                  accent: _accent,
                  size: 26,
                  onTap: i == 0
                      ? null
                      : () => _editAnimation(
                          a,
                          () => anims.insert(i - 1, anims.removeAt(i)),
                        ),
                ),
                TbButton(
                  icon: Icons.arrow_downward,
                  tooltip: 'Later',
                  accent: _accent,
                  size: 26,
                  onTap: i == anims.length - 1
                      ? null
                      : () => _editAnimation(
                          a,
                          () => anims.insert(i + 1, anims.removeAt(i)),
                        ),
                ),
                TbButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove',
                  accent: _accent,
                  size: 26,
                  onTap: () => _editAnimation(a, () => anims.removeAt(i)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: kPptxEffects
                  .indexWhere((e) => e.$1 == a.cls && e.$2 == a.effect)
                  .clamp(0, kPptxEffects.length - 1),
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Effect',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (var k = 0; k < kPptxEffects.length; k++)
                  DropdownMenuItem(value: k, child: Text(kPptxEffects[k].$3)),
              ],
              onChanged: (k) => k == null
                  ? null
                  : _editAnimation(a, () {
                      a
                        ..cls = kPptxEffects[k].$1
                        ..effect = kPptxEffects[k].$2;
                    }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PptxAnimTrigger>(
              isExpanded: true,
              initialValue: a.trigger,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Start',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: PptxAnimTrigger.onClick,
                  child: Text('On click'),
                ),
                DropdownMenuItem(
                  value: PptxAnimTrigger.withPrevious,
                  child: Text('With previous'),
                ),
                DropdownMenuItem(
                  value: PptxAnimTrigger.afterPrevious,
                  child: Text('After previous'),
                ),
              ],
              onChanged: (t) =>
                  t == null ? null : _editAnimation(a, () => a.trigger = t),
            ),
            if (dirs) ...[
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'b',
                    icon: Icon(Icons.arrow_upward, size: 16),
                    tooltip: 'From bottom',
                  ),
                  ButtonSegment(
                    value: 't',
                    icon: Icon(Icons.arrow_downward, size: 16),
                    tooltip: 'From top',
                  ),
                  ButtonSegment(
                    value: 'l',
                    icon: Icon(Icons.arrow_forward, size: 16),
                    tooltip: 'From left',
                  ),
                  ButtonSegment(
                    value: 'r',
                    icon: Icon(Icons.arrow_back, size: 16),
                    tooltip: 'From right',
                  ),
                ],
                selected: {a.dir},
                onSelectionChanged: (v) =>
                    _editAnimation(a, () => a.dir = v.first),
              ),
            ],
            Row(
              children: [
                const SizedBox(
                  width: 62,
                  child: Text('Duration', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: (a.durMs / 1000).clamp(0.1, 5.0),
                    min: 0.1,
                    max: 5,
                    divisions: 49,
                    label: '${(a.durMs / 1000).toStringAsFixed(1)} s',
                    onChanged: (v) =>
                        setState(() => a.durMs = (v * 1000).round()),
                    onChangeEnd: (_) => _editAnimation(a, () {}),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(
                  width: 62,
                  child: Text('Delay', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: (a.delayMs / 1000).clamp(0.0, 5.0),
                    max: 5,
                    divisions: 50,
                    label: '${(a.delayMs / 1000).toStringAsFixed(1)} s',
                    onChanged: (v) =>
                        setState(() => a.delayMs = (v * 1000).round()),
                    onChangeEnd: (_) => _editAnimation(a, () {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _backgroundPanel() {
    Widget swatch(int c) => InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _setBackground(Color(c)),
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Color(c),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33000000)),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      children: [
        const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          children: [
            for (final c in [
              ...kOfficeThemeColors.take(30),
              ...kOfficeStandardColors,
            ])
              swatch(c),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _setBackground(null),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset to theme'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () =>
              _setBackground(doc.resolve(_slide.background), all: true),
          icon: const Icon(Icons.done_all),
          label: const Text('Apply to all slides'),
        ),
      ],
    );
  }

  Widget _formatPanel() {
    final s = _selected;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Select an object on the slide to change its size, position and rotation.',
        ),
      );
    }
    String cm(double emu) => (emu / 360000).toStringAsFixed(2);
    Widget field(String label, double value, void Function(double) set) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            key: ValueKey(
              '$label-${identityHashCode(s)}-${value.toStringAsFixed(2)}',
            ),
            initialValue: label == 'Rotation'
                ? value.toStringAsFixed(0)
                : cm(value),
            enabled: !s.locked,
            decoration: InputDecoration(
              labelText: label,
              suffixText: label == 'Rotation' ? '°' : 'cm',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onFieldSubmitted: (v) {
              final d = double.tryParse(v);
              if (d == null) return;
              _checkpoint();
              set(label == 'Rotation' ? d : d * 360000);
              s.dirtyGeometry = true;
              _changed();
            },
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      children: [
        Text(s.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (s.locked)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Part of a group: shown as in the file, not editable here.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Size', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        field('Width', s.w, (v) => s.w = math.max(v, 36000)),
        field('Height', s.h, (v) => s.h = math.max(v, 36000)),
        const Text('Position', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        field('X', s.x, (v) => s.x = v),
        field('Y', s.y, (v) => s.y = v),
        field('Rotation', s.rotation, (v) => s.rotation = v % 360),
      ],
    );
  }
}

extension on TbPrimary {
  /// Right-click (or long-press) opens the slideshow options.
  Widget withMenu(MenuController c) => GestureDetector(
    onSecondaryTap: () => c.isOpen ? c.close() : c.open(),
    onLongPress: () => c.isOpen ? c.close() : c.open(),
    child: this,
  );
}

/// Plays every animation of a slide in order (Motion panel preview).
class _AnimPreview extends StatefulWidget {
  const _AnimPreview({
    super.key,
    required this.doc,
    required this.slide,
    required this.width,
  });
  final PptxDocument doc;
  final PptxSlide slide;
  final double width;

  @override
  State<_AnimPreview> createState() => _AnimPreviewState();
}

class _AnimPreviewState extends State<_AnimPreview>
    with SingleTickerProviderStateMixin {
  late final _steps = pptxAnimSteps(widget.slide.animations);
  late final _a = AnimationController(vsync: this);
  int _step = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    for (var k = 0; k < _steps.length; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => _step = k + 1);
      _a.duration = Duration(
        milliseconds: math.max(1, pptxStepLength(_steps[k])),
      );
      await _a.forward(from: 0).orCancel.catchError((_) {});
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.width / widget.doc.aspect);
    return PptxSlideView(
      doc: widget.doc,
      slide: widget.slide,
      width: widget.width,
      decorate: _steps.isEmpty
          ? null
          : (shape, rect, child) => AnimatedBuilder(
              animation: _a,
              builder: (context, _) => pptxAnimate(
                steps: _steps,
                shape: shape,
                child: child,
                step: _step,
                tMs: _a.value * (_a.duration?.inMilliseconds ?? 0),
                slide: size,
                rect: rect,
              ),
            ),
    );
  }
}

/// Incoming slide in the transition panel's preview.
class _TransitionPreview extends StatefulWidget {
  const _TransitionPreview({
    super.key,
    required this.doc,
    required this.slide,
    required this.width,
  });
  final PptxDocument doc;
  final PptxSlide slide;
  final double width;

  @override
  State<_TransitionPreview> createState() => _TransitionPreviewState();
}

class _TransitionPreviewState extends State<_TransitionPreview>
    with SingleTickerProviderStateMixin {
  late final _a = AnimationController(
    vsync: this,
    duration: transitionDuration(widget.slide),
  )..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => transitionFor(
    widget.slide.transition,
    widget.slide.transitionDir,
    _a,
    PptxSlideView(doc: widget.doc, slide: widget.slide, width: widget.width),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.step);
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 0.6;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.step != step;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.xs, this.ys);
  final List<double> xs, ys;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFE91E63)
      ..strokeWidth = 1;
    for (final x in xs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (final y in ys) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => true;
}

class _GridPicker extends StatefulWidget {
  const _GridPicker({required this.onPick});
  final void Function(int rows, int cols) onPick;

  @override
  State<_GridPicker> createState() => _GridPickerState();
}

class _GridPickerState extends State<_GridPicker> {
  int _r = 0, _c = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _r == 0 ? 'Table' : '$_c × $_r',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (var r = 1; r <= 8; r++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 1; c <= 10; c++)
                  MouseRegion(
                    onEnter: (_) => setState(() {
                      _r = r;
                      _c = c;
                    }),
                    child: GestureDetector(
                      onTap: () {
                        MenuController.maybeOf(context)?.close();
                        widget.onPick(r, c);
                      },
                      child: Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: r <= _r && c <= _c
                              ? _accent.withValues(alpha: 0.25)
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: r <= _r && c <= _c
                                ? _accent
                                : theme.dividerColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TableCellsDialog extends StatefulWidget {
  const _TableCellsDialog({required this.rows});
  final List<List<String>> rows;

  @override
  State<_TableCellsDialog> createState() => _TableCellsDialogState();
}

class _TableCellsDialogState extends State<_TableCellsDialog> {
  late final List<List<TextEditingController>> _cells;

  /// Controllers of deleted rows/columns: their text fields are still on
  /// screen for the frame that removes them, so they are disposed with the
  /// dialog, never at once.
  final _retired = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final cols = widget.rows.fold<int>(1, (m, r) => math.max(m, r.length));
    _cells = [
      for (final r in widget.rows)
        [
          for (var c = 0; c < cols; c++)
            TextEditingController(text: c < r.length ? r[c] : ''),
        ],
    ];
    if (_cells.isEmpty) _cells.add([TextEditingController()]);
  }

  @override
  void dispose() {
    for (final r in _cells) {
      for (final c in r) {
        c.dispose();
      }
    }
    for (final c in _retired) {
      c.dispose();
    }
    super.dispose();
  }

  int get _cols => _cells.first.length;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Text('Edit table'),
        const Spacer(),
        TbButton(
          icon: Icons.table_rows_outlined,
          label: 'Row',
          tooltip: 'Insert row',
          accent: _accent,
          onTap: () => setState(
            () => _cells.add([
              for (var c = 0; c < _cols; c++) TextEditingController(),
            ]),
          ),
        ),
        TbButton(
          icon: Icons.view_column_outlined,
          label: 'Column',
          tooltip: 'Insert column',
          accent: _accent,
          onTap: () => setState(() {
            for (final r in _cells) {
              r.add(TextEditingController());
            }
          }),
        ),
        TbButton(
          icon: Icons.remove,
          label: 'Row',
          tooltip: 'Delete last row',
          accent: _accent,
          onTap: _cells.length <= 1
              ? null
              : () => setState(() => _retired.addAll(_cells.removeLast())),
        ),
        TbButton(
          icon: Icons.remove,
          label: 'Column',
          tooltip: 'Delete last column',
          accent: _accent,
          onTap: _cols <= 1
              ? null
              : () => setState(() {
                  for (final r in _cells) {
                    _retired.add(r.removeLast());
                  }
                }),
        ),
      ],
    ),
    content: SizedBox(
      width: 720,
      height: 380,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(140),
            border: TableBorder.all(color: const Color(0xFFBFBFBF)),
            children: [
              for (final r in _cells)
                TableRow(
                  children: [
                    for (final c in r)
                      TextField(
                        controller: c,
                        maxLines: null,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(8),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, <List<String>>[]),
        style: TextButton.styleFrom(foregroundColor: Colors.red),
        child: const Text('Delete table'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, [
          for (final r in _cells) [for (final c in r) c.text],
        ]),
        child: const Text('OK'),
      ),
    ],
  );
}

/// Bytes of the bundled blank 16:9 presentation.
Future<Uint8List> blankPresentationBytes() async {
  final data = await rootBundle.load('assets/office/blank.pptx');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
