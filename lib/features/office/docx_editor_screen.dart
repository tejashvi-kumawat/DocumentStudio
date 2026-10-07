// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compose/compose_pdf.dart';
import 'package:document_studio/features/compose/math_raster.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/office/docx_io.dart';
import 'package:document_studio/features/office/docx_to_compose.dart';
import 'package:document_studio/features/office/office_fonts.dart';
import 'package:document_studio/features/office/office_chrome.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/office/office_route.dart';
import 'package:document_studio/features/print/print_gateway.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

const _fontSizes = [
  '8',
  '9',
  '10',
  '10.5',
  '11',
  '12',
  '14',
  '16',
  '18',
  '20',
  '22',
  '24',
  '26',
  '28',
  '36',
  '48',
  '72',
];

/// Point size of each heading level when the run has none (Word 365 styles).
const _headingPt = {1: 16.0, 2: 13.0, 3: 12.0, 4: 11.0, 5: 11.0, 6: 11.0};

const _symbols = [
  '©',
  '®',
  '™',
  '§',
  '¶',
  '•',
  '…',
  '—',
  '–',
  '°',
  '±',
  '×',
  '÷',
  '≈',
  '≠',
  '≤',
  '≥',
  '∞',
  '√',
  '∑', //
  '€',
  '£',
  '¥',
  '₹',
  '¢',
  '←',
  '→',
  '↑',
  '↓',
  '↔',
  '⇒',
  '✓',
  '✗',
  '★',
  '☆',
  '♥',
  'α',
  'β',
  'γ',
  'δ', //
  'π',
  'θ',
  'λ',
  'µ',
  'σ',
  'Ω',
  'Δ',
  '∂',
  '∫',
  '∈',
  '∀',
  '∃',
  '½',
  '¼',
  '¾',
  '²',
  '³',
  '‰',
  '«',
  '»',
];

/// Word-style editor for .docx: File backstage, Home / Insert / Layout /
/// Review / View ribbon, print-layout page with zoom, navigation pane,
/// find & replace, tables, pictures and page breaks. Saves .docx, exports
/// and prints PDF on-device.
class DocxEditorScreen extends ConsumerStatefulWidget {
  const DocxEditorScreen({
    super.key,
    required this.doc,
    this.path,
    this.session,
  });

  final DocxDocument doc;
  final String? path;

  /// Keeps the text, file and view across tab switches.
  final OfficeSession? session;

  @override
  ConsumerState<DocxEditorScreen> createState() => _DocxEditorScreenState();

  /// The editor's plain text (tests).
  @visibleForTesting
  static String debugPlain(State state) =>
      (state as _DocxEditorScreenState)._ctrl.document.toPlainText();

  /// Replaces text as typing / deleting does (tests).
  @visibleForTesting
  static void debugReplace(State state, int index, int len, String text) {
    final st = state as _DocxEditorScreenState;
    st._ctrl.replaceText(
      index,
      len,
      text,
      TextSelection.collapsed(offset: index + text.length),
    );
  }

  /// Turns suggesting mode on or off (tests).
  @visibleForTesting
  static void debugSuggest(State state, bool on) =>
      (state as _DocxEditorScreenState)._suggesting = on;

  /// Accepts (or rejects) every suggestion (tests).
  @visibleForTesting
  static void debugResolveAll(State state, bool accept) =>
      (state as _DocxEditorScreenState)._resolveAll(accept);

  /// Selects a range of the text (tests).
  @visibleForTesting
  static void debugSelect(State state, int start, int end) =>
      (state as _DocxEditorScreenState)._ctrl.updateSelection(
        TextSelection(baseOffset: start, extentOffset: end),
        ChangeSource.local,
      );
}

class _DocxEditorScreenState extends ConsumerState<DocxEditorScreen> {
  late final QuillController _ctrl = QuillController(
    document: Document.fromDelta(
      (widget.session?.state['delta'] as Delta?) ?? widget.doc.delta,
    ),
    selection:
        (widget.session?.state['selection'] as TextSelection?) ??
        const TextSelection.collapsed(offset: 0),
  );
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _editorKey = GlobalKey<QuillEditorState>();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();
  late String? _path = widget.path;
  bool _dirtyFlag = false;

  /// Unsaved changes; mirrored into the tab's session so closing the tab
  /// can ask first.
  bool get _dirty => _dirtyFlag;
  set _dirty(bool v) {
    _dirtyFlag = v;
    widget.session?.dirty = v;
  }

  int _words = 0;
  int _chars = 0;

  double _zoom = 1;
  bool _fitWidth = false;
  bool _webLayout = false;
  bool _showNav = true;
  bool _showRuler = true;
  bool _showComments = true;

  /// Suggesting mode (Google Docs): edits become `ins` / `del` marks that
  /// others accept or reject; saved as Word tracked changes.
  bool _suggesting = false;
  bool _applyingSuggestion = false;
  String? _activeComment;
  String? _editingComment;
  final _headerKey = GlobalKey<_RunningBandState>();
  final _footerKey = GlobalKey<_RunningBandState>();
  bool _showReplace = false;
  final _editorHeight = ValueNotifier<double>(0);

  /// Offset of the selected picture (handles shown), or null.
  final _imageSel = ValueNotifier<int?>(null);

  /// Ties the floating picture bar (outside the editor) to the picture.
  final _picLink = LayerLink();
  DefaultStyles? _stylesCache;

  /// Format Painter: the copied style, applied to the next selection.
  Style? _painter;
  int _seq = 0;

  DocxPageSetup get _page => widget.doc.page;

  @override
  void initState() {
    super.initState();
    widget.session?.saveNow = () => _save();
    _ctrl.onReplaceText = _onReplaceText;
    final st = widget.session?.state;
    if (st != null && st.isNotEmpty) {
      _path = widget.session!.path;
      _dirty = widget.session!.dirty;
      _zoom = (st['zoom'] as double?) ?? 1;
      _fitWidth = (st['fit'] as bool?) ?? false;
      _webLayout = (st['web'] as bool?) ?? false;
      _showNav = (st['nav'] as bool?) ?? true;
    }
    _ctrl.document.changes.listen((_) => _onEdit());
    _ctrl.addListener(_measureSoon);
    _ctrl.addListener(_syncImageSel);
    OfficeFonts.instance.addListener(_onFonts);
    OfficeFonts.instance.preload({'Calibri', ..._documentFonts()});
    _count(now: true);
    _measureSoon();
  }

  Set<String> _documentFonts() => {
    for (final op in widget.doc.delta.toList())
      if (op.attributes?['font'] is String) op.attributes!['font'] as String,
  };

  void _onFonts() {
    _stylesCache = null;
    if (mounted) setState(() {});
  }

  // Typing must not rebuild the page: the ribbon, title and status bars
  // listen to the controller themselves; only the first edit (dirty mark)
  // rebuilds here.
  void _onEdit() {
    if (!_dirty && mounted) setState(() => _dirty = true);
    _count();
    _measureSoon();
  }

  Timer? _countTimer;
  final _countTick = ValueNotifier<int>(0);

  void _count({bool now = false}) {
    void run() {
      final text = _ctrl.document.toPlainText();
      _words = RegExp(r'\S+').allMatches(text).length;
      _chars = text.replaceAll(RegExp(r'\s|\uFFFC'), '').length;
      _countTick.value++;
    }

    _countTimer?.cancel();
    if (now) {
      run();
    } else {
      _countTimer = Timer(const Duration(milliseconds: 250), run);
    }
  }

  void _syncImageSel() {
    final e = _embed;
    _imageSel.value = e?.type == 'docimage' && _ctrl.selection.isCollapsed
        ? e!.offset
        : null;
  }

  bool _measureQueued = false;
  double _caretY = 0;
  final _caretTick = ValueNotifier<int>(0);

  /// Page metrics come from the laid-out editor, so read them after the
  /// frame (never during build).
  void _measureSoon() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      final r = _render;
      if (!mounted || r == null || !r.hasSize) return;
      final h = r.size.height;
      if ((h - _editorHeight.value).abs() > 1) _editorHeight.value = h;
      if (_ctrl.selection.isValid) {
        try {
          final y = r.getLocalRectForCaret(TextPosition(offset: _caret)).top;
          if ((y - _caretY).abs() > 1) {
            _caretY = y;
            _caretTick.value++;
          }
        } catch (_) {}
      }
    });
  }

  RenderEditor? get _render =>
      _editorKey.currentState?.editableTextKey.currentState?.renderEditor;

  @override
  void dispose() {
    widget.session?.saveNow = null;
    final session = widget.session;
    if (session != null) {
      session
        ..path = _path
        ..dirty = _dirty;
      session.state
        ..['delta'] = _ctrl.document.toDelta()
        ..['selection'] = _ctrl.selection
        ..['zoom'] = _zoom
        ..['fit'] = _fitWidth
        ..['web'] = _webLayout
        ..['nav'] = _showNav;
    }
    OfficeFonts.instance.removeListener(_onFonts);
    _countTimer?.cancel();
    _ctrl.removeListener(_measureSoon);
    _ctrl.removeListener(_syncImageSel);
    _imageSel.dispose();
    _caretTick.dispose();
    _countTick.dispose();
    _editorHeight.dispose();
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DocxDocument get _current => DocxDocument(
    delta: _ctrl.document.toDelta(),
    images: widget.doc.images,
    tables: widget.doc.tables,
    original: widget.doc.original,
    page: _page,
    header: widget.doc.header,
    footer: widget.doc.footer,
    comments: widget.doc.comments,
    sections: widget.doc.sections,
  );

  String get _title =>
      _path == null ? 'Document1' : p.basenameWithoutExtension(_path!);

  // ------------------------------------------------------------ file

  Future<bool> _save({bool saveAs = false}) async {
    final bytes = writeDocx(_current);
    var path = _path;
    if (path == null || saveAs) {
      path = await ref
          .read(fileStorageProvider)
          .pickSavePath(
            suggestedName: '$_title.docx',
            bytes: bytes,
            allowedExtensions: const ['docx'],
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

  Future<Uint8List> _pdfBytes() async => renderComposePdf(
    docxToCompose(_current),
    fonts: await ComposeFonts.load(),
    math: MathRaster.instance.render,
  );

  Future<void> _exportPdf() async {
    final bytes = await _pdfBytes();
    final path = await ref
        .read(fileStorageProvider)
        .pickSavePath(
          suggestedName: '$_title.pdf',
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
    final bytes = await _pdfBytes();
    await const PrintingGateway().layoutPdf(
      onLayout: (_) async => bytes,
      name: _title,
    );
  }

  Future<void> _close() async {
    if (_dirty) {
      final r = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Microsoft Word document'),
          content: Text('Do you want to save changes to "$_title"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text("Don't Save"),
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

  Future<void> _openOther() async {
    final f = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: officeExtensions);
    if (f != null && mounted)
      unawaited(context.push(officeLocation(path: f.path)));
  }

  void _properties() {
    final kb = _path == null
        ? null
        : File(_path!).existsSync()
        ? File(_path!).lengthSync() / 1024
        : null;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(
              'Name',
              _path == null ? 'Document1 (not saved)' : p.basename(_path!),
            ),
            if (_path != null) _kv('Location', p.dirname(_path!)),
            if (kb != null) _kv('Size', '${kb.toStringAsFixed(1)} KB'),
            _kv('Pages', '${_pageCount()}'),
            _kv('Words', '$_words'),
            _kv('Pictures', '${widget.doc.images.length}'),
            _kv('Tables', '${widget.doc.tables.length}'),
            _kv('Page size', _sizeName()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: SelectableText(v)),
      ],
    ),
  );

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
    );

  // --------------------------------------------------------- formatting

  Map<String, Attribute> get _sel => _ctrl.getSelectionStyle().attributes;
  bool _has(Attribute a) => _sel[a.key]?.value == a.value;

  void _toggle(Attribute a) {
    _ctrl.formatSelection(_has(a) ? Attribute.clone(a, null) : a);
    _focus.requestFocus();
  }

  void _set(String key, Object? value) {
    _ctrl.formatSelection(Attribute.fromKeyValue(key, value));
    _focus.requestFocus();
  }

  String get _fontName => (_sel['font']?.value as String?) ?? 'Calibri';

  double get _fontPt {
    final s = double.tryParse('${_sel['size']?.value ?? ''}');
    if (s != null) return s;
    final h = _sel['header']?.value;
    return h is int ? _headingPt[h] ?? 11 : 11;
  }

  String _fmtPt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  void _grow(bool up) {
    final sizes = _fontSizes.map(double.parse).toList();
    final cur = _fontPt;
    final next = up
        ? sizes.firstWhere((s) => s > cur + 0.01, orElse: () => cur + 10)
        : sizes.lastWhere(
            (s) => s < cur - 0.01,
            orElse: () => (cur - 1).clamp(1, 1638).toDouble(),
          );
    _set('size', _fmtPt(next));
  }

  void _clearFormatting() {
    for (final k in [
      'bold',
      'italic',
      'underline',
      'strike',
      'color',
      'background',
      'font',
      'size',
      'script',
      'code',
    ]) {
      _ctrl.formatSelection(Attribute.fromKeyValue(k, null));
    }
    for (final k in [
      'header',
      'blockquote',
      'code-block',
      'list',
      'align',
      'indent',
      'line-height',
    ]) {
      _ctrl.formatSelection(Attribute.fromKeyValue(k, null));
    }
    _focus.requestFocus();
  }

  void _changeCase(String mode) {
    final sel = _ctrl.selection;
    if (sel.isCollapsed) return;
    final slice = _ctrl.document.toDelta().slice(sel.start, sel.end);
    var atWordStart =
        sel.start == 0 ||
        RegExp(r'\s').hasMatch(_ctrl.document.toPlainText()[sel.start - 1]);
    var sentenceStart = true;
    final out = Delta()..retain(sel.start);
    for (final op in slice.toList()) {
      if (op.data is! String) {
        out.retain(op.length!);
        continue;
      }
      final b = StringBuffer();
      for (final ch in (op.data as String).split('')) {
        final space = RegExp(r'\s').hasMatch(ch);
        b.write(switch (mode) {
          'upper' => ch.toUpperCase(),
          'lower' => ch.toLowerCase(),
          'title' => atWordStart ? ch.toUpperCase() : ch.toLowerCase(),
          'sentence' =>
            sentenceStart && !space ? ch.toUpperCase() : ch.toLowerCase(),
          _ => ch == ch.toUpperCase() ? ch.toLowerCase() : ch.toUpperCase(),
        });
        atWordStart = space;
        if (!space) sentenceStart = false;
        if ('.!?'.contains(ch)) sentenceStart = true;
      }
      out
        ..delete(op.length!)
        ..insert(b.toString(), op.attributes);
    }
    // Deletes and inserts interleave; compose does the right thing in order.
    _ctrl.compose(out, sel, ChangeSource.local);
    _focus.requestFocus();
  }

  void _copyFormat() {
    if (_painter != null) {
      setState(() => _painter = null);
      return;
    }
    final inline = {
      for (final e in _sel.entries)
        if (e.value.scope == AttributeScope.inline) e.key: e.value,
    };
    setState(() => _painter = Style.attr(inline));
    _snack('Format Painter: select the text to format');
  }

  void _applyPainter() {
    final painter = _painter;
    if (painter == null || _ctrl.selection.isCollapsed) return;
    for (final k in [
      'bold',
      'italic',
      'underline',
      'strike',
      'color',
      'background',
      'font',
      'size',
      'script',
    ]) {
      _ctrl.formatSelection(
        painter.attributes[k] ?? Attribute.fromKeyValue(k, null),
      );
    }
    setState(() => _painter = null);
  }

  void _list(Attribute a) {
    _ctrl.formatSelection(
      _sel['list']?.value == a.value
          ? Attribute.clone(Attribute.list, null)
          : a,
    );
    _focus.requestFocus();
  }

  void _align(Attribute? a) {
    _ctrl.formatSelection(a ?? Attribute.clone(Attribute.align, null));
    _focus.requestFocus();
  }

  void _style(String id) {
    for (final k in ['header', 'blockquote', 'code-block']) {
      _ctrl.formatSelection(Attribute.fromKeyValue(k, null));
    }
    switch (id) {
      case 'h1':
        _ctrl.formatSelection(Attribute.h1);
      case 'h2':
        _ctrl.formatSelection(Attribute.h2);
      case 'h3':
        _ctrl.formatSelection(Attribute.h3);
      case 'h4':
        _ctrl.formatSelection(Attribute.h4);
      case 'quote':
        _ctrl.formatSelection(Attribute.blockQuote);
      case 'code':
        _ctrl.formatSelection(Attribute.codeBlock);
    }
    _focus.requestFocus();
  }

  String get _currentStyle {
    final h = _sel['header']?.value;
    if (h is int) return 'h$h';
    if (_sel['blockquote'] != null) return 'quote';
    if (_sel['code-block'] != null) return 'code';
    return 'normal';
  }

  // ------------------------------------------------------------- insert

  int get _caret =>
      _ctrl.selection.baseOffset.clamp(0, _ctrl.document.length - 1);

  void _insertEmbed(String type, String data) {
    final sel = _ctrl.selection;
    _ctrl.replaceText(
      sel.start,
      sel.end - sel.start,
      BlockEmbed(type, data),
      null,
    );
    _ctrl.updateSelection(
      TextSelection.collapsed(offset: sel.start + 2),
      ChangeSource.local,
    );
    _focus.requestFocus();
  }

  void _insertText(String t) {
    final sel = _ctrl.selection;
    _ctrl.replaceText(
      sel.start,
      sel.end - sel.start,
      t,
      TextSelection.collapsed(offset: sel.start + t.length),
    );
    _focus.requestFocus();
  }

  void _pageBreak() => _insertEmbed('docbreak', 'page');

  void _insertTable(int rows, int cols) {
    final id = 'tbl_n${_seq++}';
    widget.doc.tables[id] = docxNewTable(
      List.generate(rows, (_) => List.filled(cols, '')),
      header: false,
    );
    _insertEmbed('doctable', id);
  }

  Future<void> _insertTableDialog() async {
    final r = TextEditingController(text: '3');
    final c = TextEditingController(text: '4');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insert Table'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: c,
                decoration: const InputDecoration(labelText: 'Columns'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 110,
              child: TextField(
                controller: r,
                decoration: const InputDecoration(labelText: 'Rows'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _insertTable(
        (int.tryParse(r.text) ?? 3).clamp(1, 200),
        (int.tryParse(c.text) ?? 4).clamp(1, 30),
      );
    }
  }

  Future<void> _insertPicture() async {
    final f = await ref
        .read(fileStorageProvider)
        .pickOpenFile(
          allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'bmp'],
        );
    if (f == null) return;
    final bytes = await File(f.path).readAsBytes();
    int w = 600, h = 400;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      w = frame.image.width;
      h = frame.image.height;
      frame.image.dispose();
    } catch (_) {
      if (mounted) _snack('That picture could not be read');
      return;
    }
    final maxEmu = (_page.width - _page.left - _page.right) * 635;
    var cx = w * 9525, cy = h * 9525;
    if (cx > maxEmu) {
      cy = (cy * maxEmu / cx).round();
      cx = maxEmu;
    }
    final ext = p
        .extension(f.path)
        .toLowerCase()
        .replaceFirst('.', '')
        .replaceFirst('jpg', 'jpeg');
    final id = 'img_n${_seq++}';
    widget.doc.images[id] = DocxImage(
      bytes,
      cx,
      cy,
      'word/media/ds_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    _insertEmbed('docimage', id);
  }

  Future<void> _insertLink() async {
    final sel = _ctrl.selection;
    final selected = sel.isCollapsed
        ? ''
        : _ctrl.document.getPlainText(sel.start, sel.end - sel.start);
    final text = TextEditingController(text: selected);
    final url = TextEditingController(
      text: (_sel['link']?.value as String?) ?? 'https://',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Insert Hyperlink'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                decoration: const InputDecoration(labelText: 'Text to display'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: url,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
        actions: [
          if (_sel['link'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(c, false);
                _set('link', null);
              },
              child: const Text('Remove Link'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    final t = text.text.isEmpty ? url.text.trim() : text.text;
    if (t != selected) {
      _ctrl.replaceText(sel.start, sel.end - sel.start, t, null);
    }
    _ctrl.formatText(
      sel.start,
      t.length,
      Attribute.fromKeyValue('link', url.text.trim()),
    );
    _ctrl.updateSelection(
      TextSelection.collapsed(offset: sel.start + t.length),
      ChangeSource.local,
    );
    _focus.requestFocus();
  }

  Future<void> _insertDate() async {
    final d = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final m = months[d.month - 1];
    final options = [
      '${d.day}/${d.month}/${d.year}',
      '${days[d.weekday - 1]}, ${d.day} $m ${d.year}',
      '${d.day} $m ${d.year}',
      '$m ${d.day}, ${d.year}',
      '${d.year}-${two(d.month)}-${two(d.day)}',
      '${d.day}-${m.substring(0, 3)}-${two(d.year % 100)}',
      '${d.day}/${d.month}/${d.year} $h12:${two(d.minute)} $ampm',
      '$h12:${two(d.minute)} $ampm',
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}',
    ];
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Date and Time'),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, o),
              child: Text(o),
            ),
        ],
      ),
    );
    if (pick != null) _insertText(pick);
  }

  // ------------------------------------------------------------- embeds

  /// The table or picture the caret is on (its line holds only the embed).
  ({String type, String id, int offset})? get _embed {
    final sel = _ctrl.selection;
    if (!sel.isValid) return null;
    for (final off in {sel.start, (sel.start - 1).clamp(0, 1 << 30)}) {
      final line = _ctrl.document.querySegmentLeafNode(off).line;
      final first = line?.children.firstOrNull;
      if (line != null && line.childCount == 1 && first is Embed) {
        return (
          type: first.value.type,
          id: '${first.value.data}',
          offset: first.documentOffset,
        );
      }
    }
    return null;
  }

  Future<void> _editTable(String id, int offset) async {
    final xml = widget.doc.tables[id];
    if (xml == null) return;
    final result = await showDialog<List<List<String>>?>(
      context: context,
      builder: (_) => _TableEditorDialog(rows: docxTableRows(xml)),
    );
    if (result == null) return;
    if (result.isEmpty) {
      _ctrl.replaceText(offset, 1, '', TextSelection.collapsed(offset: offset));
      return;
    }
    final nid = 'tbl_e${_seq++}';
    widget.doc.tables[nid] = docxTableWithCells(xml, result);
    _ctrl.replaceText(offset, 1, BlockEmbed('doctable', nid), null);
  }

  double get _textWidthEmu => (_page.width - _page.left - _page.right) * 635.0;

  void _resizePicture(String id, int offset, double fraction) =>
      _setPictureWidth(id, offset, _textWidthEmu * fraction);

  /// New width (EMU) for a picture, height following its proportions.
  void _setPictureWidth(
    String id,
    int offset,
    double widthEmu, {
    double? heightEmu,
  }) {
    final img = widget.doc.images[id];
    if (img == null) return;
    final cx = widthEmu.clamp(9525.0 * 16, _textWidthEmu).round();
    final cy = (heightEmu ?? img.heightEmu * cx / img.widthEmu).round().clamp(
      9525 * 16,
      9525 * 6000,
    );
    final nid = 'img_r${_seq++}';
    widget.doc.images[nid] = DocxImage(img.bytes, cx, cy, img.target);
    final align = _ctrl.document
        .querySegmentLeafNode(offset)
        .line
        ?.style
        .attributes['align'];
    _ctrl.replaceText(
      offset,
      1,
      BlockEmbed('docimage', nid),
      TextSelection.collapsed(offset: offset),
    );
    if (align != null) _ctrl.formatText(offset, 1, align);
  }

  void _alignEmbed(int offset, Attribute? a) {
    _ctrl.formatText(offset, 1, a ?? Attribute.clone(Attribute.align, null));
    _ctrl.updateSelection(
      TextSelection.collapsed(offset: offset),
      ChangeSource.local,
    );
  }

  /// Drag-and-drop of a picture to the text position under [global].
  void _moveEmbed(int offset, Offset global) {
    final r = _render;
    if (r == null) return;
    var to = r.getPositionForOffset(global).offset;
    if (to == offset || to == offset + 1) return;
    final leaf = _ctrl.document
        .querySegmentLeafNode(offset)
        .line
        ?.children
        .firstOrNull;
    if (leaf is! Embed) return;
    final embed = BlockEmbed(leaf.value.type, '${leaf.value.data}');
    _removeEmbedLine(offset);
    if (to > offset) to -= 2;
    _insertBlockAt(to.clamp(0, _ctrl.document.length - 1), embed);
  }

  /// Removes the embed at [offset] with its own line break (no empty line
  /// is left behind).
  void _removeEmbedLine(int offset) {
    final text = _ctrl.document.toPlainText();
    final ownLine = offset + 1 < text.length - 1 && text[offset + 1] == '\n';
    _ctrl.replaceText(offset, ownLine ? 2 : 1, '', null);
  }

  /// Inserts a block embed on a line of its own at [to] (the text line
  /// there is split when needed) and selects it.
  void _insertBlockAt(int to, BlockEmbed embed) {
    final text = _ctrl.document.toPlainText();
    if (to > 0 && text[to - 1] != '\n') {
      // Move to the end of this line, then break after it.
      final end = text.indexOf('\n', to);
      final at = end < 0 ? text.length - 1 : end;
      _ctrl.replaceText(at, 0, '\n', null); // a new empty line after it
      to = at + 1;
    }
    _ctrl.replaceText(to, 0, embed, null);
    final now = _ctrl.document.toPlainText();
    if (to + 1 < now.length && now[to + 1] != '\n')
      _ctrl.replaceText(to + 1, 0, '\n', null);
    _ctrl.updateSelection(
      TextSelection.collapsed(offset: _embedNear(to)),
      ChangeSource.local,
    );
  }

  /// Offset of the embed inserted at [pos] (block embeds may be moved to
  /// their own line).
  int _embedNear(int pos) {
    for (final o in [pos, pos + 1, pos - 1]) {
      if (o < 0) continue;
      final line = _ctrl.document.querySegmentLeafNode(o).line;
      final first = line?.children.firstOrNull;
      if (first is Embed) return first.documentOffset;
    }
    return pos;
  }

  void _selectEmbed(int offset) {
    _ctrl.updateSelection(
      TextSelection.collapsed(offset: offset),
      ChangeSource.local,
    );
    _focus.requestFocus();
  }

  void _deleteEmbed(int offset) {
    _removeEmbedLine(offset);
    _ctrl.updateSelection(
      TextSelection.collapsed(
        offset: offset.clamp(0, _ctrl.document.length - 1),
      ),
      ChangeSource.local,
    );
    _focus.requestFocus();
  }

  // --------------------------------------------------------------- page

  void _setPage(void Function(DocxPageSetup p) f) {
    setState(() {
      f(_page);
      _dirty = true;
    });
    _measureSoon();
  }

  static const _sizes = <String, (int, int)>{
    'Letter': (12240, 15840),
    'Legal': (12240, 20160),
    'Executive': (10440, 15120),
    'A3': (16838, 23811),
    'A4': (11906, 16838),
    'A5': (8391, 11906),
    'B5': (9979, 14175),
  };

  String _sizeName() {
    final short = _page.width < _page.height ? _page.width : _page.height;
    final long = _page.width < _page.height ? _page.height : _page.width;
    for (final e in _sizes.entries) {
      if ((e.value.$1 - short).abs() < 40 && (e.value.$2 - long).abs() < 40)
        return e.key;
    }
    return '${(short / 1440).toStringAsFixed(2)}" × ${(long / 1440).toStringAsFixed(2)}"';
  }

  void _setSize(String name) {
    final (w, h) = _sizes[name]!;
    _setPage((p) {
      final land = p.landscape;
      p
        ..width = land ? h : w
        ..height = land ? w : h;
    });
  }

  void _setOrientation(bool landscape) {
    if (landscape == _page.landscape) return;
    _setPage((p) {
      final w = p.width;
      p
        ..width = p.height
        ..height = w;
    });
  }

  void _setMargins(int t, int r, int b, int l) => _setPage(
    (p) => p
      ..top = t
      ..right = r
      ..bottom = b
      ..left = l,
  );

  Future<void> _customMargins() async {
    String inch(int tw) => (tw / 1440).toStringAsFixed(2);
    final c = [
      TextEditingController(text: inch(_page.top)),
      TextEditingController(text: inch(_page.bottom)),
      TextEditingController(text: inch(_page.left)),
      TextEditingController(text: inch(_page.right)),
    ];
    const labels = ['Top', 'Bottom', 'Left', 'Right'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Page Setup — Margins (inches)'),
        content: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: 120,
                child: TextField(
                  controller: c[i],
                  decoration: InputDecoration(labelText: labels[i]),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int tw(int i, int fallback) =>
        ((double.tryParse(c[i].text) ?? fallback / 1440) * 1440).round().clamp(
          0,
          10000,
        );
    _setMargins(
      tw(0, _page.top),
      tw(3, _page.right),
      tw(1, _page.bottom),
      tw(2, _page.left),
    );
  }

  // --------------------------------------------------------- find/goto

  void _selectAndReveal(int start, int len) {
    _ctrl.updateSelection(
      TextSelection(baseOffset: start, extentOffset: start + len),
      ChangeSource.local,
    );
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = _render;
      if (r == null) return;
      final rect = r.getLocalRectForCaret(TextPosition(offset: start));
      r.showOnScreen(
        rect: rect.inflate(120),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<({int level, String text, int offset})> _headings() {
    final out = <({int level, String text, int offset})>[];
    var offset = 0;
    var lineStart = 0;
    final buf = StringBuffer();
    for (final op in _ctrl.document.toDelta().toList()) {
      final data = op.data;
      if (data is! String) {
        offset += 1;
        continue;
      }
      for (var i = 0; i < data.length; i++) {
        if (data[i] == '\n') {
          final h = op.attributes?['header'];
          if (h is int && buf.toString().trim().isNotEmpty) {
            out.add((level: h, text: buf.toString().trim(), offset: lineStart));
          }
          buf.clear();
          lineStart = offset + 1;
        } else {
          buf.write(data[i]);
        }
        offset++;
      }
    }
    return out;
  }

  List<int> _matches(String q, {bool matchCase = false}) {
    if (q.isEmpty) return const [];
    final text = _ctrl.document.toPlainText();
    final hay = matchCase ? text : text.toLowerCase();
    final needle = matchCase ? q : q.toLowerCase();
    final out = <int>[];
    var i = hay.indexOf(needle);
    while (i >= 0 && out.length < 1000) {
      out.add(i);
      i = hay.indexOf(needle, i + needle.length);
    }
    return out;
  }

  void _openFind() {
    setState(() => _showNav = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  // ------------------------------------------------------------- build

  int _pageCount() {
    final contentPx =
        (_page.height - _page.top - _page.bottom) / 15 * _effectiveZoom;
    if (_editorHeight.value <= 0 || contentPx <= 0) return 1;
    return (_editorHeight.value / contentPx).ceil().clamp(1, 9999);
  }

  int _caretPage() {
    final contentPx =
        (_page.height - _page.top - _page.bottom) / 15 * _effectiveZoom;
    if (contentPx <= 0) return 1;
    return (_caretY / contentPx).floor() + 1;
  }

  double _effectiveZoom = 1;

  TextStyle _pt(double pt, {FontWeight? weight, Color? color, String? font}) =>
      TextStyle(
        fontSize: pt * 4 / 3,
        fontWeight: weight,
        color: color ?? const Color(0xFF000000),
        fontFamily: OfficeFonts.instance.familyFor(font ?? 'Calibri'),
        height: 1.16,
      );

  DefaultStyles _styles(BuildContext context) =>
      _stylesCache ??= _buildStyles(context);

  DefaultStyles _buildStyles(BuildContext context) {
    final base = DefaultStyles.getInstance(context);
    const after = VerticalSpacing(0, 10.7); // 8 pt after
    const none = VerticalSpacing(0, 0);
    DefaultTextBlockStyle block(TextStyle s, VerticalSpacing v) =>
        DefaultTextBlockStyle(s, HorizontalSpacing.zero, v, none, null);
    final blue = const Color(0xFF2F5496);
    return base.merge(
      DefaultStyles(
        paragraph: block(_pt(11), after),
        h1: block(
          _pt(16, color: blue, font: 'Calibri Light'),
          const VerticalSpacing(16, 0),
        ),
        h2: block(
          _pt(13, color: blue, font: 'Calibri Light'),
          const VerticalSpacing(2.7, 0),
        ),
        h3: block(
          _pt(12, color: const Color(0xFF1F3763), font: 'Calibri Light'),
          const VerticalSpacing(2.7, 0),
        ),
        h4: block(
          _pt(11, color: blue).copyWith(fontStyle: FontStyle.italic),
          const VerticalSpacing(2.7, 0),
        ),
        h5: block(_pt(11, color: blue), const VerticalSpacing(2.7, 0)),
        h6: block(
          _pt(11, color: const Color(0xFF1F3763)),
          const VerticalSpacing(2.7, 0),
        ),
        placeHolder: block(_pt(11, color: const Color(0xFF9E9E9E)), none),
        color: const Color(0xFF000000),
      ),
    );
  }

  TextStyle _custom(Attribute a) {
    if (a.key == 'ins' && a.value is String) {
      return const TextStyle(
        color: Color(0xFF188038),
        decoration: TextDecoration.underline,
        decorationColor: Color(0xFF188038),
      );
    }
    if (a.key == 'del' && a.value is String) {
      return const TextStyle(
        color: Color(0xFFC5221F),
        decoration: TextDecoration.lineThrough,
        decorationColor: Color(0xFFC5221F),
      );
    }
    if (a.key == 'comment' &&
        a.value is String &&
        widget.doc.comments.containsKey(a.value)) {
      final active = a.value == _activeComment;
      return TextStyle(
        backgroundColor: active
            ? const Color(0x88FFC107)
            : const Color(0x40FFC107),
      );
    }
    if (a.key == 'font' && a.value is String) {
      final f = OfficeFonts.instance.familyFor(a.value as String);
      return f == null ? const TextStyle() : TextStyle(fontFamily: f);
    }
    if (a.key == 'size') {
      final v = double.tryParse('${a.value}');
      if (v != null) return TextStyle(fontSize: v * 4 / 3);
    }
    return const TextStyle();
  }

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
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            setState(() => _showReplace = true),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            unawaited(_insertLink()),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            _align(Attribute.centerAlignment),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _align(null),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            _align(Attribute.rightAlignment),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            _align(Attribute.justifyAlignment),
        const SingleActivator(
          LogicalKeyboardKey.bracketRight,
          control: true,
        ): () =>
            _grow(true),
        const SingleActivator(
          LogicalKeyboardKey.bracketLeft,
          control: true,
        ): () =>
            _grow(false),
        const SingleActivator(
          LogicalKeyboardKey.period,
          control: true,
          shift: true,
        ): () =>
            _grow(true),
        const SingleActivator(
          LogicalKeyboardKey.comma,
          control: true,
          shift: true,
        ): () =>
            _grow(false),
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _pageBreak,
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            _toggle(Attribute.subscript),
        const SingleActivator(LogicalKeyboardKey.period, control: true): () =>
            _toggle(Attribute.superscript),
        const SingleActivator(LogicalKeyboardKey.backslash, control: true):
            _clearFormatting,
        const SingleActivator(LogicalKeyboardKey.space, control: true):
            _clearFormatting,
        const SingleActivator(
          LogicalKeyboardKey.digit0,
          control: true,
          alt: true,
        ): () =>
            _style('normal'),
        const SingleActivator(
          LogicalKeyboardKey.digit1,
          control: true,
          alt: true,
        ): () =>
            _style('h1'),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): () =>
            _style('h2'),
        const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ): () =>
            _style('h3'),
        const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
          alt: true,
        ): () =>
            _style('h4'),
        const SingleActivator(
          LogicalKeyboardKey.digit7,
          control: true,
          shift: true,
        ): () =>
            _list(Attribute.ol),
        const SingleActivator(
          LogicalKeyboardKey.digit8,
          control: true,
          shift: true,
        ): () =>
            _list(Attribute.ul),
        const SingleActivator(
          LogicalKeyboardKey.digit9,
          control: true,
          shift: true,
        ): () =>
            _list(Attribute.unchecked),
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): _wordCount,
        const SingleActivator(
          LogicalKeyboardKey.keyM,
          control: true,
          alt: true,
        ): _addComment,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_painter != null || _showReplace) {
            setState(() {
              _painter = null;
              _showReplace = false;
            });
          }
        },
      },
      child: Scaffold(
        backgroundColor: officeCanvas(theme.brightness),
        body: Column(
          children: [
            ListenableBuilder(
              listenable: _ctrl,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [_topBar(), _toolbar()],
              ),
            ),
            Divider(height: 1, color: DsColors.border(theme.brightness)),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      if (_showNav && wide) _panel(theme),
                      Expanded(child: _canvas()),
                      if (_showComments &&
                          (widget.doc.comments.isNotEmpty ||
                              _editingComment != null ||
                              _suggesting ||
                              _hasSuggestions) &&
                          wide)
                        ListenableBuilder(
                          listenable: _countTick,
                          builder: (context, _) => _commentsPanel(theme),
                        ),
                    ],
                  ),
                  if (_showNav && !wide)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Material(elevation: 8, child: _panel(theme)),
                    ),
                  if (!_showNav)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Material(
                        color: officeBar(theme.brightness),
                        elevation: 2,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Show outline and details',
                          icon: const Icon(Icons.segment_rounded),
                          onPressed: () => setState(() => _showNav = true),
                        ),
                      ),
                    ),
                  if (_showReplace) _replacePanel(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- menus

  Widget _topBar() {
    final shortcut = SingleActivator.new;
    Widget check(bool on, String label, VoidCallback f) =>
        officeItem(label, f, checked: on);
    bool margins(int t, int r, int b, int l) =>
        _page.top == t &&
        _page.right == r &&
        _page.bottom == b &&
        _page.left == l;
    return OfficeTopBar(
      onBack: () => unawaited(_close()),
      menus: [
        officeMenu('File', [
          officeItem(
            'New document',
            () => context.push(officeLocation(kind: 'docx')),
            icon: Icons.note_add_outlined,
          ),
          officeItem('Open…', _openOther, icon: Icons.folder_open_outlined),
          officeMenuDivider,
          officeItem(
            'Save',
            () => unawaited(_save()),
            icon: Icons.save_outlined,
            shortcut: shortcut(LogicalKeyboardKey.keyS, control: true),
          ),
          officeItem(
            'Save as…',
            () => unawaited(_save(saveAs: true)),
            shortcut: shortcut(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
            ),
          ),
          officeItem(
            'Download as PDF',
            () => unawaited(_exportPdf()),
            icon: Icons.picture_as_pdf_outlined,
            shortcut: shortcut(
              LogicalKeyboardKey.keyE,
              control: true,
              shift: true,
            ),
          ),
          officeMenuDivider,
          officeSub('Page setup', [
            officeSub('Orientation', [
              check(!_page.landscape, 'Portrait', () => _setOrientation(false)),
              check(_page.landscape, 'Landscape', () => _setOrientation(true)),
            ]),
            officeSub('Paper size', [
              for (final e in _sizes.entries)
                check(
                  _sizeName() == e.key,
                  '${e.key}  (${(e.value.$1 / 1440 * 25.4).round()} × ${(e.value.$2 / 1440 * 25.4).round()} mm)',
                  () => _setSize(e.key),
                ),
            ]),
            officeSub('Margins', [
              for (final (name, t, r, b, l) in [
                ('Normal (1")', 1440, 1440, 1440, 1440),
                ('Narrow (0.5")', 720, 720, 720, 720),
                ('Moderate (1" × 0.75")', 1440, 1080, 1440, 1080),
                ('Wide (1" × 2")', 1440, 2880, 1440, 2880),
              ])
                check(margins(t, r, b, l), name, () => _setMargins(t, r, b, l)),
              officeMenuDivider,
              officeItem('Custom margins…', _customMargins),
            ]),
          ], icon: Icons.article_outlined),
          officeItem('Details', _properties, icon: Icons.info_outline),
          officeItem(
            'Print',
            () => unawaited(_print()),
            icon: Icons.print_outlined,
            shortcut: shortcut(LogicalKeyboardKey.keyP, control: true),
          ),
          officeMenuDivider,
          officeItem('Close', () => unawaited(_close()), icon: Icons.close),
        ]),
        officeMenu('Edit', [
          officeItem(
            'Undo',
            _ctrl.hasUndo ? _ctrl.undo : null,
            icon: Icons.undo,
            shortcut: shortcut(LogicalKeyboardKey.keyZ, control: true),
          ),
          officeItem(
            'Redo',
            _ctrl.hasRedo ? _ctrl.redo : null,
            icon: Icons.redo,
            shortcut: shortcut(LogicalKeyboardKey.keyY, control: true),
          ),
          officeMenuDivider,
          officeItem(
            'Cut',
            () => _ctrl.clipboardSelection(false),
            icon: Icons.content_cut,
            shortcut: shortcut(LogicalKeyboardKey.keyX, control: true),
          ),
          officeItem(
            'Copy',
            () => _ctrl.clipboardSelection(true),
            icon: Icons.content_copy,
            shortcut: shortcut(LogicalKeyboardKey.keyC, control: true),
          ),
          officeItem(
            'Paste',
            () async {
              await _ctrl.clipboardPaste();
              _focus.requestFocus();
            },
            icon: Icons.content_paste,
            shortcut: shortcut(LogicalKeyboardKey.keyV, control: true),
          ),
          officeItem(
            'Select all',
            _selectAll,
            icon: Icons.select_all,
            shortcut: shortcut(LogicalKeyboardKey.keyA, control: true),
          ),
          officeMenuDivider,
          officeItem(
            'Find',
            _openFind,
            icon: Icons.search,
            shortcut: shortcut(LogicalKeyboardKey.keyF, control: true),
          ),
          officeItem(
            'Find and replace',
            () => setState(() => _showReplace = true),
            icon: Icons.find_replace,
            shortcut: shortcut(LogicalKeyboardKey.keyH, control: true),
          ),
        ]),
        officeMenu('View', [
          check(
            !_webLayout,
            'Print layout',
            () => setState(() => _webLayout = false),
          ),
          check(
            _webLayout,
            'Web layout',
            () => setState(() => _webLayout = true),
          ),
          officeMenuDivider,
          check(
            _showNav,
            'Show outline and details',
            () => setState(() => _showNav = !_showNav),
          ),
          check(
            _showRuler,
            'Show ruler',
            () => setState(() => _showRuler = !_showRuler),
          ),
          check(
            _showComments,
            'Show comments',
            () => setState(() => _showComments = !_showComments),
          ),
          officeMenuDivider,
          officeSub('Zoom', [
            for (final z in [0.5, 0.75, 0.9, 1.0, 1.25, 1.5, 2.0])
              check(
                !_fitWidth && (_zoom - z).abs() < 0.01,
                '${(z * 100).round()}%',
                () => setState(() {
                  _zoom = z;
                  _fitWidth = false;
                }),
              ),
            check(
              _fitWidth,
              'Fit page width',
              () => setState(() => _fitWidth = true),
            ),
          ], icon: Icons.zoom_in),
        ]),
        officeMenu('Insert', [
          officeItem('Image…', _insertPicture, icon: Icons.image_outlined),
          officeSub('Table', [
            _TableGridPicker(onPick: _insertTable),
            officeItem('Insert table…', _insertTableDialog),
          ], icon: Icons.table_chart_outlined),
          officeItem(
            'Link',
            _insertLink,
            icon: Icons.link,
            shortcut: shortcut(LogicalKeyboardKey.keyK, control: true),
          ),
          officeItem(
            'Comment',
            _addComment,
            icon: Icons.add_comment_outlined,
            shortcut: shortcut(
              LogicalKeyboardKey.keyM,
              control: true,
              alt: true,
            ),
          ),
          officeMenuDivider,
          officeItem(
            'Page break',
            _pageBreak,
            icon: Icons.insert_page_break_outlined,
            shortcut: shortcut(LogicalKeyboardKey.enter, control: true),
          ),
          officeItem('Blank page', () {
            _pageBreak();
            _pageBreak();
          }, icon: Icons.note_add_outlined),
          officeMenuDivider,
          officeItem(
            'Header',
            () => _headerKey.currentState?.edit(),
            icon: Icons.vertical_align_top,
          ),
          officeItem(
            'Footer',
            () => _footerKey.currentState?.edit(),
            icon: Icons.vertical_align_bottom,
          ),
          officeSub('Page numbers', [
            officeItem(
              'Bottom center: "Page 1 of 9"',
              () => _setRunning(
                widget.doc.footer,
                'Page {PAGE} of {PAGES}',
                align: 'center',
              ),
            ),
            officeItem(
              'Bottom center: "1"',
              () => _setRunning(widget.doc.footer, '{PAGE}', align: 'center'),
            ),
            officeItem(
              'Bottom right: "1"',
              () => _setRunning(widget.doc.footer, '{PAGE}', align: 'right'),
            ),
            officeItem(
              'Top right: "1"',
              () => _setRunning(widget.doc.header, '{PAGE}', align: 'right'),
            ),
          ], icon: Icons.tag),
          officeMenuDivider,
          officeItem(
            'Horizontal line',
            () => _insertEmbed('dochr', 'line'),
            icon: Icons.horizontal_rule,
          ),
          officeItem('Table of contents', _insertToc, icon: Icons.toc),
          officeMenuDivider,
          officeItem('Date and time…', _insertDate, icon: Icons.event_outlined),
          officeSub('Special characters', [
            _symbolGrid(),
          ], icon: Icons.emoji_symbols),
          officeItem(
            'Code block',
            () => _style(_currentStyle == 'code' ? 'normal' : 'code'),
            icon: Icons.code,
          ),
        ]),
        officeMenu('Format', [
          officeSub('Text', [
            officeItem(
              'Bold',
              () => _toggle(Attribute.bold),
              icon: Icons.format_bold,
              shortcut: shortcut(LogicalKeyboardKey.keyB, control: true),
            ),
            officeItem(
              'Italic',
              () => _toggle(Attribute.italic),
              icon: Icons.format_italic,
              shortcut: shortcut(LogicalKeyboardKey.keyI, control: true),
            ),
            officeItem(
              'Underline',
              () => _toggle(Attribute.underline),
              icon: Icons.format_underline,
              shortcut: shortcut(LogicalKeyboardKey.keyU, control: true),
            ),
            officeItem(
              'Strikethrough',
              () => _toggle(Attribute.strikeThrough),
              icon: Icons.strikethrough_s,
            ),
            officeItem(
              'Superscript',
              () => _toggle(Attribute.superscript),
              icon: Icons.superscript,
              shortcut: shortcut(LogicalKeyboardKey.period, control: true),
            ),
            officeItem(
              'Subscript',
              () => _toggle(Attribute.subscript),
              icon: Icons.subscript,
              shortcut: shortcut(LogicalKeyboardKey.comma, control: true),
            ),
            officeItem(
              'Code',
              () => _toggle(Attribute.inlineCode),
              icon: Icons.code,
            ),
            officeMenuDivider,
            officeItem(
              'Increase font size',
              () => _grow(true),
              shortcut: shortcut(
                LogicalKeyboardKey.period,
                control: true,
                shift: true,
              ),
            ),
            officeItem(
              'Decrease font size',
              () => _grow(false),
              shortcut: shortcut(
                LogicalKeyboardKey.comma,
                control: true,
                shift: true,
              ),
            ),
            officeSub('Capitalization', [
              officeItem('lowercase', () => _changeCase('lower')),
              officeItem('UPPERCASE', () => _changeCase('upper')),
              officeItem('Title Case', () => _changeCase('title')),
              officeItem('Sentence case', () => _changeCase('sentence')),
            ]),
          ], icon: Icons.text_format),
          officeSub('Paragraph styles', [
            for (final (id, label) in _styleNames)
              check(_currentStyle == id, label, () => _style(id)),
          ], icon: Icons.title),
          officeSub('Align & indent', [
            officeItem(
              'Left',
              () => _align(null),
              icon: Icons.format_align_left,
              shortcut: shortcut(LogicalKeyboardKey.keyL, control: true),
            ),
            officeItem(
              'Center',
              () => _align(Attribute.centerAlignment),
              icon: Icons.format_align_center,
              shortcut: shortcut(LogicalKeyboardKey.keyE, control: true),
            ),
            officeItem(
              'Right',
              () => _align(Attribute.rightAlignment),
              icon: Icons.format_align_right,
              shortcut: shortcut(LogicalKeyboardKey.keyR, control: true),
            ),
            officeItem(
              'Justified',
              () => _align(Attribute.justifyAlignment),
              icon: Icons.format_align_justify,
              shortcut: shortcut(LogicalKeyboardKey.keyJ, control: true),
            ),
            officeMenuDivider,
            officeItem(
              'Increase indent',
              () => _ctrl.indentSelection(true),
              icon: Icons.format_indent_increase,
            ),
            officeItem(
              'Decrease indent',
              () => _ctrl.indentSelection(false),
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
              () => _list(Attribute.ul),
              icon: Icons.format_list_bulleted,
              shortcut: shortcut(
                LogicalKeyboardKey.digit8,
                control: true,
                shift: true,
              ),
            ),
            officeItem(
              'Numbered list',
              () => _list(Attribute.ol),
              icon: Icons.format_list_numbered,
              shortcut: shortcut(
                LogicalKeyboardKey.digit7,
                control: true,
                shift: true,
              ),
            ),
            officeItem(
              'Checklist',
              () => _list(Attribute.unchecked),
              icon: Icons.checklist,
              shortcut: shortcut(
                LogicalKeyboardKey.digit9,
                control: true,
                shift: true,
              ),
            ),
          ], icon: Icons.format_list_bulleted),
          officeMenuDivider,
          officeItem(
            'Paint format',
            _copyFormat,
            icon: Icons.format_paint_outlined,
          ),
          officeItem(
            'Clear formatting',
            _clearFormatting,
            icon: Icons.format_clear,
            shortcut: shortcut(LogicalKeyboardKey.backslash, control: true),
          ),
        ]),
        officeMenu('Tools', [
          officeItem(
            _suggesting ? 'Stop suggesting' : 'Suggest edits',
            () => setState(() => _suggesting = !_suggesting),
            icon: Icons.rate_review_outlined,
          ),
          officeItem(
            'Accept all suggestions',
            _hasSuggestions ? () => _resolveAll(true) : null,
            icon: Icons.done_all,
          ),
          officeItem(
            'Reject all suggestions',
            _hasSuggestions ? () => _resolveAll(false) : null,
            icon: Icons.remove_done,
          ),
          officeMenuDivider,
          officeItem(
            'Word count',
            _wordCount,
            icon: Icons.numbers,
            shortcut: shortcut(
              LogicalKeyboardKey.keyC,
              control: true,
              shift: true,
            ),
          ),
          officeItem(
            'Find and replace',
            () => setState(() => _showReplace = true),
            icon: Icons.find_replace,
          ),
          officeItem(
            'Document outline',
            () => setState(() => _showNav = true),
            icon: Icons.segment_rounded,
          ),
        ]),
      ],
    );
  }

  static const _styleNames = [
    ('normal', 'Normal text'),
    ('h1', 'Heading 1'),
    ('h2', 'Heading 2'),
    ('h3', 'Heading 3'),
    ('h4', 'Heading 4'),
    ('quote', 'Quote'),
    ('code', 'Code'),
  ];

  List<Widget> _spacingItems() {
    final lh = _sel['line-height']?.value;
    return [
      for (final (v, l) in [
        (null, 'Single'),
        (1.15, '1.15'),
        (1.5, '1.5'),
        (2.0, 'Double'),
      ])
        officeItem(l, () => _set('line-height', v), checked: lh == v),
    ];
  }

  Widget _symbolGrid() => Padding(
    padding: const EdgeInsets.all(8),
    child: SizedBox(
      width: 20 * 30,
      child: Wrap(
        children: [
          for (final s in _symbols)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _insertText(s),
              child: SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: Text(s, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  void _selectAll() {
    _ctrl.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: _ctrl.document.length - 1),
      ChangeSource.local,
    );
    _focus.requestFocus();
  }

  // -------------------------------------------------------- toolbar

  Widget _toolbar() {
    final sel = _sel;
    final color = sel['color']?.value as String?;
    final bg = sel['background']?.value as String?;
    Color parse(String? hex, Color fallback) => hex != null && hex.length == 7
        ? Color(int.parse('FF${hex.substring(1)}', radix: 16))
        : fallback;
    final align = sel['align']?.value;
    final alignIcon = switch (align) {
      'center' => Icons.format_align_center,
      'right' => Icons.format_align_right,
      'justify' => Icons.format_align_justify,
      _ => Icons.format_align_left,
    };
    final embed = _embed;
    final styleLabel = _styleNames
        .firstWhere(
          (s) => s.$1 == _currentStyle,
          orElse: () => _styleNames.first,
        )
        .$2;
    return OfficeToolbar(
      accent: kDocsAccent,
      trailing: [
        TbButton(
          icon: _suggesting ? Icons.rate_review_outlined : Icons.edit_outlined,
          label: _suggesting ? 'Suggesting' : 'Editing',
          tooltip: 'Editing mode',
          active: _suggesting,
          menu: [
            officeItem(
              'Editing — change the document directly',
              () => setState(() => _suggesting = false),
              icon: Icons.edit_outlined,
              checked: !_suggesting,
            ),
            officeItem(
              'Suggesting — edits become suggestions',
              () => setState(() {
                _suggesting = true;
                _showComments = true;
              }),
              icon: Icons.rate_review_outlined,
              checked: _suggesting,
            ),
          ],
        ),
        TbButton(
          icon: Icons.picture_as_pdf_outlined,
          tooltip: 'Download as PDF (Ctrl+Shift+E)',
          onTap: () => unawaited(_exportPdf()),
        ),
        TbPrimary(
          icon: _dirty ? Icons.save_outlined : Icons.check_rounded,
          label: _dirty ? 'Save' : 'Saved',
          tooltip: _path == null
              ? 'Save (Ctrl+S)'
              : 'Save ${p.basename(_path!)} (Ctrl+S)',
          accent: _dirty ? kDocsAccent : const Color(0xFF64748B),
          onTap: () => unawaited(_save()),
        ),
      ],
      children: [
        TbButton(
          icon: Icons.search,
          tooltip: 'Search the document (Ctrl+F)',
          onTap: _openFind,
        ),
        TbButton(
          icon: Icons.undo,
          tooltip: 'Undo (Ctrl+Z)',
          onTap: _ctrl.hasUndo ? _ctrl.undo : null,
        ),
        TbButton(
          icon: Icons.redo,
          tooltip: 'Redo (Ctrl+Y)',
          onTap: _ctrl.hasRedo ? _ctrl.redo : null,
        ),
        TbButton(
          icon: Icons.print_outlined,
          tooltip: 'Print (Ctrl+P)',
          onTap: () => unawaited(_print()),
        ),
        TbButton(
          icon: Icons.format_paint_outlined,
          tooltip: 'Paint format',
          active: _painter != null,
          onTap: _copyFormat,
        ),
        TbCombo(
          value: _fitWidth ? 'Fit' : '${(_zoom * 100).round()}%',
          items: const [
            '50%',
            '75%',
            '90%',
            '100%',
            '125%',
            '150%',
            '200%',
            'Fit',
          ],
          width: 72,
          tooltip: 'Zoom',
          onSelected: (v) => setState(() {
            if (v.toLowerCase().startsWith('fit')) {
              _fitWidth = true;
            } else {
              final z = double.tryParse(v.replaceAll('%', ''));
              if (z != null) {
                _zoom = (z / 100).clamp(0.25, 5.0);
                _fitWidth = false;
              }
            }
          }),
        ),
        const TbDivider(),
        TbButton(
          icon: Icons.text_fields_rounded,
          tooltip: 'Styles',
          label: styleLabel,
          menu: [
            for (final (id, label) in _styleNames)
              MenuItemButton(
                onPressed: () => _style(id),
                child: Text(label, style: _styleStyle(id)),
              ),
          ],
        ),
        const TbDivider(),
        TbCombo(
          value: _fontName,
          items: OfficeFonts.instance.allNames,
          tooltip: 'Font',
          width: 128,
          itemStyle: (f) {
            final fam = OfficeFonts.instance.familyFor(f);
            return fam == null ? null : TextStyle(fontFamily: fam);
          },
          onSelected: (f) => _set('font', f == 'Calibri' ? null : f),
        ),
        const TbDivider(),
        TbButton(
          icon: Icons.remove,
          tooltip: 'Decrease font size (Ctrl+Shift+,)',
          onTap: () => _grow(false),
        ),
        TbCombo(
          value: _fmtPt(_fontPt),
          items: _fontSizes,
          tooltip: 'Font size',
          width: 52,
          onSelected: (v) {
            final d = double.tryParse(v);
            if (d != null && d >= 1 && d <= 1638) _set('size', _fmtPt(d));
          },
        ),
        TbButton(
          icon: Icons.add,
          tooltip: 'Increase font size (Ctrl+Shift+.)',
          onTap: () => _grow(true),
        ),
        const TbDivider(),
        TbButton(
          icon: Icons.format_bold,
          tooltip: 'Bold (Ctrl+B)',
          active: _has(Attribute.bold),
          onTap: () => _toggle(Attribute.bold),
        ),
        TbButton(
          icon: Icons.format_italic,
          tooltip: 'Italic (Ctrl+I)',
          active: _has(Attribute.italic),
          onTap: () => _toggle(Attribute.italic),
        ),
        TbButton(
          icon: Icons.format_underline,
          tooltip: 'Underline (Ctrl+U)',
          active: _has(Attribute.underline),
          onTap: () => _toggle(Attribute.underline),
        ),
        TbButton(
          icon: Icons.strikethrough_s,
          tooltip: 'Strikethrough',
          active: _has(Attribute.strikeThrough),
          onTap: () => _toggle(Attribute.strikeThrough),
        ),
        TbColorButton(
          icon: Icons.format_color_text,
          tooltip: 'Text color',
          color: parse(color, Colors.black),
          onPicked: (c) => _set('color', c == null ? null : _hex(c)),
        ),
        TbColorButton(
          icon: Icons.border_color_outlined,
          tooltip: 'Highlight color',
          highlight: true,
          noneLabel: 'None',
          color: parse(bg, Colors.transparent),
          onPicked: (c) => _set('background', c == null ? null : _hex(c)),
        ),
        const TbDivider(),
        TbButton(
          icon: Icons.link,
          tooltip: 'Insert link (Ctrl+K)',
          onTap: _insertLink,
        ),
        TbButton(
          icon: Icons.add_comment_outlined,
          tooltip: 'Add comment (Ctrl+Alt+M)',
          onTap: _addComment,
        ),
        TbButton(
          icon: Icons.add_photo_alternate_outlined,
          tooltip: 'Insert image',
          onTap: _insertPicture,
        ),
        TbButton(
          icon: Icons.table_chart_outlined,
          tooltip: 'Insert table',
          menu: [
            _TableGridPicker(onPick: _insertTable),
            MenuItemButton(
              onPressed: _insertTableDialog,
              child: const Text('Insert table…'),
            ),
          ],
        ),
        const TbDivider(),
        TbButton(
          icon: alignIcon,
          tooltip: 'Align',
          menu: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TbButton(
                  icon: Icons.format_align_left,
                  tooltip: 'Left (Ctrl+L)',
                  active: align == null,
                  onTap: () => _align(null),
                ),
                TbButton(
                  icon: Icons.format_align_center,
                  tooltip: 'Center (Ctrl+E)',
                  active: align == 'center',
                  onTap: () => _align(Attribute.centerAlignment),
                ),
                TbButton(
                  icon: Icons.format_align_right,
                  tooltip: 'Right (Ctrl+R)',
                  active: align == 'right',
                  onTap: () => _align(Attribute.rightAlignment),
                ),
                TbButton(
                  icon: Icons.format_align_justify,
                  tooltip: 'Justify (Ctrl+J)',
                  active: align == 'justify',
                  onTap: () => _align(Attribute.justifyAlignment),
                ),
              ],
            ),
          ],
        ),
        TbButton(
          icon: Icons.format_line_spacing,
          tooltip: 'Line spacing',
          menu: _spacingItems(),
        ),
        TbButton(
          icon: Icons.checklist,
          tooltip: 'Checklist (Ctrl+Shift+9)',
          active:
              sel['list']?.value == 'unchecked' ||
              sel['list']?.value == 'checked',
          onTap: () => _list(Attribute.unchecked),
        ),
        TbButton(
          icon: Icons.format_list_bulleted,
          tooltip: 'Bulleted list (Ctrl+Shift+8)',
          active: sel['list']?.value == 'bullet',
          onTap: () => _list(Attribute.ul),
        ),
        TbButton(
          icon: Icons.format_list_numbered,
          tooltip: 'Numbered list (Ctrl+Shift+7)',
          active: sel['list']?.value == 'ordered',
          onTap: () => _list(Attribute.ol),
        ),
        TbButton(
          icon: Icons.format_indent_decrease,
          tooltip: 'Decrease indent',
          onTap: () => _ctrl.indentSelection(false),
        ),
        TbButton(
          icon: Icons.format_indent_increase,
          tooltip: 'Increase indent',
          onTap: () => _ctrl.indentSelection(true),
        ),
        TbButton(
          icon: Icons.format_clear,
          tooltip: 'Clear formatting (Ctrl+\\)',
          onTap: _clearFormatting,
        ),
        if (embed?.type == 'doctable') ...[
          const TbDivider(),
          TbButton(
            icon: Icons.edit_note,
            label: 'Edit table',
            tooltip: 'Edit cells, add or remove rows and columns',
            onTap: () => _editTable(embed!.id, embed.offset),
            active: true,
          ),
          TbButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete table',
            onTap: () => _deleteEmbed(embed!.offset),
          ),
        ],
        if (embed?.type == 'docimage') ...[
          const TbDivider(),
          TbButton(
            icon: Icons.photo_size_select_large,
            label: 'Image size',
            tooltip: 'Width of the image',
            active: true,
            menu: [
              for (final (f, l) in [
                (0.25, '25% of the text width'),
                (0.5, '50%'),
                (0.75, '75%'),
                (1.0, 'Full width'),
              ])
                MenuItemButton(
                  onPressed: () => _resizePicture(embed!.id, embed.offset, f),
                  child: Text(l),
                ),
            ],
          ),
          TbButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete image',
            onTap: () => _deleteEmbed(embed!.offset),
          ),
        ],
      ],
    );
  }

  TextStyle _styleStyle(String id) => switch (id) {
    'h1' => const TextStyle(fontSize: 20, color: Color(0xFF2F5496)),
    'h2' => const TextStyle(fontSize: 17, color: Color(0xFF2F5496)),
    'h3' => const TextStyle(fontSize: 15, color: Color(0xFF1F3763)),
    'h4' => const TextStyle(
      fontSize: 14,
      fontStyle: FontStyle.italic,
      color: Color(0xFF2F5496),
    ),
    'quote' => const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
    'code' => TextStyle(
      fontSize: 13,
      fontFamily: OfficeFonts.instance.familyFor('Consolas'),
    ),
    _ => const TextStyle(fontSize: 14),
  };

  String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _wordCount() {
    final text = _ctrl.document.toPlainText();
    final paragraphs = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Word count'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('Pages', '${_pageCount()}'),
            _kv('Words', '$_words'),
            _kv(
              'Characters',
              '${text.replaceAll('\n', '').replaceAll('￼', '').length}',
            ),
            _kv('Characters excluding spaces', '$_chars'),
            _kv('Paragraphs', '$paragraphs'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return LayoutBuilder(
      builder: (context, c) {
        final basePageW = _page.width / 15; // twips → px at 96 dpi
        _effectiveZoom = _fitWidth
            ? ((c.maxWidth - 48) / basePageW).clamp(0.3, 4.0)
            : _zoom;
        final z = _effectiveZoom;
        final narrow = c.maxWidth < basePageW * z + 24;
        final pageW = _webLayout
            ? c.maxWidth - 24
            : (narrow ? c.maxWidth - 16 : basePageW * z);
        final padH = _webLayout ? 24.0 : (narrow ? 18.0 : _page.left / 15 * z);
        final padR = _webLayout ? 24.0 : (narrow ? 18.0 : _page.right / 15 * z);
        final padT = _webLayout ? 16.0 : _page.top / 15 * z;
        final padB = _webLayout ? 16.0 : _page.bottom / 15 * z;
        final pageH = _page.height / 15 * z;
        final contentH = pageH - padT - padB;
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent &&
                HardwareKeyboard.instance.isControlPressed) {
              setState(() {
                _fitWidth = false;
                _zoom = (_effectiveZoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1))
                    .clamp(0.25, 5.0);
              });
              GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
            }
          },
          onPointerUp: (_) => _applyPainter(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    if (_showRuler && !_webLayout)
                      Container(
                        color: officeCanvas(Theme.of(context).brightness),
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        alignment: Alignment.center,
                        child: _Ruler(
                          page: _page,
                          zoom: z,
                          pageW: pageW,
                          onMargins: (l, r, {required done}) {
                            if (done) {
                              _setPage(
                                (p) => p
                                  ..left = l
                                  ..right = r,
                              );
                            } else {
                              setState(() {
                                _page
                                  ..left = l
                                  ..right = r;
                              });
                            }
                          },
                        ),
                      ),
                    Expanded(
                      child: _pageScroller(
                        pageW,
                        pageH,
                        padH,
                        padR,
                        padT,
                        padB,
                        contentH,
                        z,
                      ),
                    ),
                  ],
                ),
              ),
              // Picture bar: outside the editor so its clicks never move the caret.
              ValueListenableBuilder<int?>(
                valueListenable: _imageSel,
                builder: (context, sel, _) {
                  final e = _embed;
                  if (sel == null || e == null || e.type != 'docimage')
                    return const SizedBox.shrink();
                  final align =
                      _ctrl.document
                              .querySegmentLeafNode(e.offset)
                              .line
                              ?.style
                              .attributes['align']
                              ?.value
                          as String?;
                  return Positioned(
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _picLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.topLeft,
                      followerAnchor: Alignment.bottomLeft,
                      offset: const Offset(0, -8),
                      child: _PictureBar(
                        align: align,
                        onAlign: (a) => _alignEmbed(e.offset, a),
                        onFit: (f) => _resizePicture(e.id, e.offset, f),
                        onDelete: () => _deleteEmbed(e.offset),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pageScroller(
    double pageW,
    double pageH,
    double padH,
    double padR,
    double padT,
    double padB,
    double contentH,
    double z,
  ) {
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.symmetric(vertical: _webLayout ? 8 : 24),
        child: Center(
          child: MouseRegion(
            cursor: _painter != null
                ? SystemMouseCursors.precise
                : MouseCursor.defer,
            child: Stack(
              children: [
                Container(
                  width: pageW,
                  constraints: BoxConstraints(
                    minHeight: _webLayout ? 0 : pageH,
                  ),
                  padding: EdgeInsets.fromLTRB(padH, padT, padR, padB),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _editorHeight,
                    builder: (context, _, child) => CustomPaint(
                      foregroundPainter: _webLayout
                          ? null
                          : _PageBreakPainter(
                              contentH,
                              _pageCount(),
                              padH,
                              padR,
                            ),
                      child: child,
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(z)),
                      child: Theme(
                        data: ThemeData.light(useMaterial3: true),
                        child: QuillEditor(
                          key: _editorKey,
                          controller: _ctrl,
                          focusNode: _focus,
                          scrollController: ScrollController(),
                          config: QuillEditorConfig(
                            scrollable: false,
                            autoFocus: true,
                            placeholder: 'Start typing…',
                            customStyles: _styles(context),
                            customStyleBuilder: _custom,
                            embedBuilders: [
                              _ImageEmbed(widget.doc, z, this),
                              _TableEmbed(widget.doc, z, onEdit: _editTable),
                              _BreakEmbed(),
                              _RuleEmbed(),
                              _SectionEmbed(),
                            ],
                            unknownEmbedBuilder: _UnknownEmbed(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_webLayout) ..._runningBands(pageW, padH, padR, z),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- suggestions

  /// Every edit while suggesting: new text is marked inserted, removed text
  /// is struck through instead of deleted (your own insertions are simply
  /// removed again).
  bool _onReplaceText(int index, int len, Object? data) {
    if (!_suggesting || _applyingSuggestion || data is! String) return true;
    final mark = suggestionMark(AppPrefs.effectiveAuthor, null);
    final sel = _ctrl.selection;
    final backspace =
        len > 0 &&
        data.isEmpty &&
        sel.isCollapsed &&
        sel.baseOffset == index + len;
    _applyingSuggestion = true;
    try {
      var at = index + len;
      if (len > 0) {
        var offset = index, removed = 0;
        for (final op
            in _ctrl.document.toDelta().slice(index, index + len).toList()) {
          final n = op.length!;
          final start = offset - removed;
          final attrs = op.attributes ?? const {};
          if (attrs['ins'] != null) {
            _ctrl.replaceText(start, n, '', null);
            removed += n;
          } else if (attrs['del'] == null && op.data is String) {
            _ctrl.formatText(
              start,
              n,
              Attribute('del', AttributeScope.inline, mark),
            );
          }
          offset += n;
        }
        at = index + len - removed;
      }
      if (data.isNotEmpty) {
        _ctrl.replaceText(at, 0, data, null);
        _ctrl.formatText(
          at,
          data.length,
          const Attribute<String?>('del', AttributeScope.inline, null),
        );
        _ctrl.formatText(
          at,
          data.length,
          Attribute('ins', AttributeScope.inline, mark),
        );
        _ctrl.updateSelection(
          TextSelection.collapsed(offset: at + data.length),
          ChangeSource.local,
        );
      } else {
        _ctrl.updateSelection(
          TextSelection.collapsed(offset: backspace ? index : at),
          ChangeSource.local,
        );
      }
    } finally {
      _applyingSuggestion = false;
    }
    if (!_dirty) setState(() => _dirty = true);
    return false;
  }

  /// Runs of suggested text: (kind, mark, start, end), in text order.
  List<({String kind, String mark, int start, int end})> _suggestions() {
    final out = <({String kind, String mark, int start, int end})>[];
    var offset = 0;
    for (final op in _ctrl.document.toDelta().toList()) {
      final n = op.length!;
      final a = op.attributes;
      final kind = a?['del'] != null
          ? 'del'
          : (a?['ins'] != null ? 'ins' : null);
      if (kind != null) {
        final mark = a![kind] as String;
        final last = out.lastOrNull;
        if (last != null &&
            last.kind == kind &&
            last.mark == mark &&
            last.end == offset) {
          out[out.length - 1] = (
            kind: kind,
            mark: mark,
            start: last.start,
            end: offset + n,
          );
        } else {
          out.add((kind: kind, mark: mark, start: offset, end: offset + n));
        }
      }
      offset += n;
    }
    return out;
  }

  bool get _hasSuggestions => _ctrl.document.toDelta().toList().any(
    (o) => o.attributes?['ins'] != null || o.attributes?['del'] != null,
  );

  void _resolve(
    ({String kind, String mark, int start, int end}) s,
    bool accept,
  ) {
    _applyingSuggestion = true;
    try {
      final len = s.end - s.start;
      final drop =
          (s.kind == 'del') == accept; // accepted deletion / rejected insertion
      if (drop) {
        _ctrl.replaceText(
          s.start,
          len,
          '',
          TextSelection.collapsed(offset: s.start),
        );
      } else {
        _ctrl.formatText(
          s.start,
          len,
          Attribute<String?>(s.kind, AttributeScope.inline, null),
        );
      }
    } finally {
      _applyingSuggestion = false;
    }
    setState(() => _dirty = true);
  }

  void _resolveAll(bool accept) {
    // From the end, so earlier offsets stay valid.
    for (final s in _suggestions().reversed) {
      _resolve(s, accept);
    }
  }

  // ------------------------------------------------------------ comments

  /// Comment ids with the document range each one marks, in text order.
  List<({String id, int start, int end})> _commentRanges() {
    final out = <String, ({String id, int start, int end})>{};
    var offset = 0;
    for (final op in _ctrl.document.toDelta().toList()) {
      final len = op.data is String ? (op.data as String).length : 1;
      final c = op.attributes?['comment'];
      if (c is String && widget.doc.comments.containsKey(c)) {
        final r = out[c];
        out[c] = (id: c, start: r?.start ?? offset, end: offset + len);
      }
      offset += len;
    }
    final list = out.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  void _addComment() {
    final sel = _ctrl.selection;
    if (sel.isCollapsed) {
      _snack('Select the text to comment on');
      return;
    }
    final id = 'n${DateTime.now().microsecondsSinceEpoch}';
    widget.doc.comments[id] = DocxComment(
      text: '',
      author: AppPrefs.effectiveAuthor,
    );
    _ctrl.formatSelection(Attribute('comment', AttributeScope.inline, id));
    setState(() {
      _showComments = true;
      _activeComment = id;
      _editingComment = id;
      _dirty = true;
    });
  }

  void _removeComment(String id) {
    for (final r in _commentRanges().where((r) => r.id == id)) {
      _ctrl.formatText(
        r.start,
        r.end - r.start,
        const Attribute<String?>('comment', AttributeScope.inline, null),
      );
    }
    setState(() {
      widget.doc.comments.remove(id);
      if (_activeComment == id) _activeComment = null;
      if (_editingComment == id) _editingComment = null;
      _dirty = true;
    });
  }

  void _focusComment(String id) {
    final r = _commentRanges().where((r) => r.id == id).firstOrNull;
    setState(() => _activeComment = id);
    _stylesCache = null;
    if (r != null) _selectAndReveal(r.start, r.end - r.start);
  }

  Widget _commentsPanel(ThemeData theme) {
    final ranges = _commentRanges();
    final suggestions = _suggestions();
    final text = _ctrl.document.toPlainText();
    final muted = DsColors.textSecondary(theme.brightness);
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: officeBar(theme.brightness),
        border: Border(
          left: BorderSide(color: DsColors.border(theme.brightness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OfficePanelHeader(
            suggestions.isEmpty
                ? 'Comments (${ranges.length})'
                : 'Comments ${ranges.length} · Suggestions ${suggestions.length}',
            trailing: TbButton(
              icon: Icons.close,
              tooltip: 'Hide comments',
              size: 26,
              onTap: () => setState(() => _showComments = false),
            ),
          ),
          Expanded(
            child: ranges.isEmpty && suggestions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Select text and choose Add comment (Ctrl+Alt+M) to start a discussion.',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    children: [
                      if (suggestions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _resolveAll(true),
                                  child: const Text('Accept all'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _resolveAll(false),
                                  child: const Text('Reject all'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final sg in suggestions)
                        _SuggestionCard(
                          key: ValueKey('s${sg.start}-${sg.kind}'),
                          kind: sg.kind,
                          mark: sg.mark,
                          quote: text
                              .substring(
                                sg.start.clamp(0, text.length),
                                sg.end.clamp(0, text.length),
                              )
                              .replaceAll('\n', ' ¶ '),
                          onTap: () =>
                              _selectAndReveal(sg.start, sg.end - sg.start),
                          onAccept: () => _resolve(sg, true),
                          onReject: () => _resolve(sg, false),
                        ),
                      for (final r in ranges)
                        _CommentCard(
                          key: ValueKey(r.id),
                          comment: widget.doc.comments[r.id]!,
                          quote: text
                              .substring(
                                r.start.clamp(0, text.length),
                                r.end.clamp(0, text.length),
                              )
                              .replaceAll('\n', ' '),
                          active: r.id == _activeComment,
                          editing: r.id == _editingComment,
                          onTap: () => _focusComment(r.id),
                          onEdit: () => setState(() => _editingComment = r.id),
                          onSaved: (v) => setState(() {
                            widget.doc.comments[r.id]!.text = v;
                            _editingComment = null;
                            _dirty = true;
                          }),
                          onCancel: () {
                            if (widget.doc.comments[r.id]!.text.isEmpty) {
                              _removeComment(r.id);
                            } else {
                              setState(() => _editingComment = null);
                            }
                          },
                          onResolve: () => _removeComment(r.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Header and footer bands in the page margins (double-click to edit).
  List<Widget> _runningBands(double pageW, double padH, double padR, double z) {
    final inset = 0.5 * 96 * z; // Word's default 0.5" header / footer distance
    Widget band(DocxRunning r, String kind) => _RunningBand(
      key: kind == 'Header' ? _headerKey : _footerKey,
      running: r,
      kind: kind,
      zoom: z,
      pages: _pageCount(),
      onChanged: () {
        r.dirty = true;
        if (!_dirty) setState(() => _dirty = true);
      },
    );
    return [
      Positioned(
        left: padH,
        right: padR,
        top: inset * 0.6,
        child: band(widget.doc.header, 'Header'),
      ),
      Positioned(
        left: padH,
        right: padR,
        bottom: inset * 0.6,
        child: band(widget.doc.footer, 'Footer'),
      ),
    ];
  }

  void _setRunning(DocxRunning r, String text, {String? align}) {
    setState(() {
      r
        ..text = text
        ..align = align ?? r.align
        ..dirty = true;
      _dirty = true;
    });
  }

  void _insertToc() {
    final heads = _headings();
    if (heads.isEmpty) {
      _snack(
        'Add headings (Format → Paragraph styles) to build a table of contents',
      );
      return;
    }
    final at = _ctrl.selection.start;
    final d = Delta()..retain(at);
    d.insert('Contents');
    d.insert('\n', {'header': 2});
    for (final h in heads) {
      d.insert('${'    ' * (h.level - 1)}${h.text}');
      d.insert('\n');
    }
    _ctrl.compose(d, TextSelection.collapsed(offset: at), ChangeSource.local);
  }

  /// Left panel (Google Docs' outline): search, headings, document details.
  Widget _panel(ThemeData theme) => OfficeSidePanel(
    child: ListenableBuilder(
      listenable: Listenable.merge([_countTick, _caretTick, _editorHeight]),
      builder: (context, _) => _panelBody(theme),
    ),
  );

  Widget _panelBody(ThemeData theme) {
    final q = _searchField.text;
    final hits = _matches(q);
    final heads = _headings();
    final text = _ctrl.document.toPlainText();
    final pages = _pageCount();
    final muted = DsColors.textSecondary(theme.brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchField,
                    focusNode: _searchFocus,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search document',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: officePill(theme.brightness, kDocsAccent),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (hits.isEmpty) return;
                      final next = hits.firstWhere(
                        (h) => h > _ctrl.selection.start,
                        orElse: () => hits.first,
                      );
                      _selectAndReveal(next, q.length);
                      _searchFocus.requestFocus();
                    },
                  ),
                ),
              ),
              TbButton(
                icon: Icons.chevron_left,
                tooltip: 'Hide panel',
                onTap: () => setState(() => _showNav = false),
              ),
            ],
          ),
        ),
        Expanded(
          child: q.isNotEmpty
              ? ListView(
                  children: [
                    OfficePanelHeader(
                      '${hits.length} result${hits.length == 1 ? '' : 's'}',
                    ),
                    for (final h in hits.take(300))
                      InkWell(
                        onTap: () => _selectAndReveal(h, q.length),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: text
                                      .substring((h - 30).clamp(0, h), h)
                                      .replaceAll('\n', ' '),
                                ),
                                TextSpan(
                                  text: text.substring(h, h + q.length),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    backgroundColor: kDocsAccent.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                TextSpan(
                                  text: text
                                      .substring(
                                        h + q.length,
                                        (h + q.length + 40).clamp(
                                          0,
                                          text.length,
                                        ),
                                      )
                                      .replaceAll('\n', ' '),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                  ],
                )
              : ListView(
                  children: [
                    const OfficePanelHeader('Outline'),
                    if (heads.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                        child: Text(
                          'Headings you add to the document will appear here.',
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      ),
                    for (final h in heads)
                      InkWell(
                        onTap: () => _selectAndReveal(h.offset, 0),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            14.0 + (h.level - 1) * 12,
                            6,
                            10,
                            6,
                          ),
                          child: Text(
                            h.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: h.level == 1
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Divider(height: 1, color: DsColors.border(theme.brightness)),
        const OfficePanelHeader('Details'),
        OfficeStat(
          'Page',
          '${_caretPage().clamp(1, pages)} of $pages',
          icon: Icons.description_outlined,
        ),
        OfficeStat('Words', '$_words', icon: Icons.notes),
        OfficeStat('Characters', '$_chars', icon: Icons.abc),
        OfficeStat(
          'Paper',
          '${_sizeName()} · ${_page.landscape ? 'Landscape' : 'Portrait'}',
          icon: Icons.crop_portrait,
        ),
        OfficeStat(
          'Zoom',
          '${(_effectiveZoom * 100).round()}%',
          icon: Icons.zoom_in,
        ),
        if (_painter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(
              'Paint format is on: select text to apply (Esc cancels).',
              style: TextStyle(fontSize: 12, color: kDocsAccent),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _replacePanel(ThemeData theme) => Positioned(
    top: 12,
    right: 20,
    child: _ReplacePanel(
      onClose: () => setState(() => _showReplace = false),
      find: (q, matchCase, {bool fromStart = false}) {
        final hits = _matches(q, matchCase: matchCase);
        if (hits.isEmpty) return false;
        final after = fromStart ? -1 : _ctrl.selection.end - 1;
        final next = hits.firstWhere(
          (h) => h > after,
          orElse: () => hits.first,
        );
        _selectAndReveal(next, q.length);
        return true;
      },
      replace: (q, r, matchCase) {
        final sel = _ctrl.selection;
        final cur = _ctrl.document.getPlainText(sel.start, sel.end - sel.start);
        final same = matchCase
            ? cur == q
            : cur.toLowerCase() == q.toLowerCase();
        if (!sel.isCollapsed && same) {
          _ctrl.replaceText(
            sel.start,
            sel.end - sel.start,
            r,
            TextSelection.collapsed(offset: sel.start + r.length),
          );
        }
      },
      replaceAll: (q, r, matchCase) {
        final hits = _matches(q, matchCase: matchCase);
        for (final h in hits.reversed) {
          _ctrl.replaceText(h, q.length, r, null);
        }
        return hits.length;
      },
    ),
  );
}

/// Dashed lines where pages would break (an estimate from the text height).
class _PageBreakPainter extends CustomPainter {
  _PageBreakPainter(this.contentH, this.pages, this.padL, this.padR);
  final double contentH, padL, padR;
  final int pages;

  @override
  void paint(Canvas canvas, Size size) {
    if (contentH <= 40) return;
    final paint = Paint()
      ..color = const Color(0x55808080)
      ..strokeWidth = 1;
    for (var i = 1; i < pages; i++) {
      final y = contentH * i;
      if (y > size.height) break;
      for (var x = -padL + 6; x < size.width + padR - 6; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), paint);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: 'Page ${i + 1}',
          style: const TextStyle(fontSize: 9, color: Color(0x99808080)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width + padR - tp.width - 8, y + 2));
    }
  }

  @override
  bool shouldRepaint(_PageBreakPainter old) =>
      old.contentH != contentH || old.pages != pages;
}

/// Word's hover grid: pick rows × columns in one move.
class _TableGridPicker extends StatefulWidget {
  const _TableGridPicker({required this.onPick});
  final void Function(int rows, int cols) onPick;

  @override
  State<_TableGridPicker> createState() => _TableGridPickerState();
}

class _TableGridPickerState extends State<_TableGridPicker> {
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
            _r == 0 ? 'Insert Table' : '$_c × $_r Table',
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
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.25,
                                )
                              : theme.colorScheme.surface,
                          border: Border.all(
                            color: r <= _r && c <= _c
                                ? theme.colorScheme.primary
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

/// Edits a table's cells; rows/columns can be added and removed. Returns the
/// new cells, an empty list to delete the table, or null to cancel.
class _TableEditorDialog extends StatefulWidget {
  const _TableEditorDialog({required this.rows});
  final List<List<String>> rows;

  @override
  State<_TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<_TableEditorDialog> {
  late final List<List<TextEditingController>> _cells;

  /// Controllers of deleted rows/columns: their text fields are still on
  /// screen for the frame that removes them, so they are disposed with the
  /// dialog, never at once.
  final _retired = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final cols = widget.rows.fold<int>(
      1,
      (m, r) => r.length > m ? r.length : m,
    );
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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('Edit Table'),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(
              () => _cells.add([
                for (var c = 0; c < _cols; c++) TextEditingController(),
              ]),
            ),
            icon: const Icon(Icons.table_rows_outlined, size: 18),
            label: const Text('Insert Row'),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              for (final r in _cells) {
                r.add(TextEditingController());
              }
            }),
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: const Text('Insert Column'),
          ),
          TextButton.icon(
            onPressed: _cells.length <= 1
                ? null
                : () => setState(() => _retired.addAll(_cells.removeLast())),
            icon: const Icon(Icons.remove, size: 18),
            label: const Text('Delete Row'),
          ),
          TextButton.icon(
            onPressed: _cols <= 1
                ? null
                : () => setState(() {
                    for (final r in _cells) {
                      _retired.add(r.removeLast());
                    }
                  }),
            icon: const Icon(Icons.remove, size: 18),
            label: const Text('Delete Column'),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 420,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(150),
              border: TableBorder.all(color: const Color(0xFFBFBFBF)),
              children: [
                for (final r in _cells)
                  TableRow(
                    children: [
                      for (final c in r)
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: TextField(
                            controller: c,
                            maxLines: null,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(6),
                            ),
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
          child: const Text('Delete Table'),
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
}

class _ReplacePanel extends StatefulWidget {
  const _ReplacePanel({
    required this.onClose,
    required this.find,
    required this.replace,
    required this.replaceAll,
  });
  final VoidCallback onClose;
  final bool Function(String q, bool matchCase, {bool fromStart}) find;
  final void Function(String q, String r, bool matchCase) replace;
  final int Function(String q, String r, bool matchCase) replaceAll;

  @override
  State<_ReplacePanel> createState() => _ReplacePanelState();
}

class _ReplacePanelState extends State<_ReplacePanel> {
  final _q = TextEditingController();
  final _r = TextEditingController();
  bool _case = false;
  String? _msg;

  @override
  void dispose() {
    _q.dispose();
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Find and Replace',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Find what',
              ),
              onSubmitted: (_) => _next(),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _r,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Replace with',
              ),
            ),
            CheckboxListTile(
              value: _case,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Match case'),
              onChanged: (v) => setState(() => _case = v ?? false),
            ),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_msg!, style: const TextStyle(fontSize: 12)),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    widget.replace(_q.text, _r.text, _case);
                    _next();
                  },
                  child: const Text('Replace'),
                ),
                OutlinedButton(
                  onPressed: () {
                    final n = widget.replaceAll(_q.text, _r.text, _case);
                    setState(
                      () => _msg = n == 0
                          ? 'No matches.'
                          : 'All done. Made $n replacement${n == 1 ? '' : 's'}.',
                    );
                  },
                  child: const Text('Replace All'),
                ),
                FilledButton(onPressed: _next, child: const Text('Find Next')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    if (_q.text.isEmpty) return;
    final ok = widget.find(_q.text, _case);
    setState(() => _msg = ok ? null : 'Word could not find "${_q.text}".');
  }
}

class _ImageEmbed extends EmbedBuilder {
  _ImageEmbed(this.doc, this.zoom, this.host);
  final DocxDocument doc;
  final double zoom;
  final _DocxEditorScreenState host;

  @override
  String get key => 'docimage';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final id = embedContext.node.value.data as String;
    final img = doc.images[id];
    if (img == null) return const SizedBox.shrink();
    final line = embedContext.node.parent;
    final align = line is Line ? line.style.attributes['align']?.value : null;
    final offset = embedContext.node.documentOffset;
    return ValueListenableBuilder<int?>(
      valueListenable: host._imageSel,
      builder: (context, sel, _) => _PictureBox(
        key: ValueKey(id),
        image: img,
        zoom: zoom,
        align: align as String?,
        selected: sel == offset,
        onSelect: () => host._selectEmbed(offset),
        onResize: (wEmu, hEmu) =>
            host._setPictureWidth(id, offset, wEmu, heightEmu: hEmu),
        onMove: (global) => host._moveEmbed(offset, global),
        onAlign: (a) => host._alignEmbed(offset, a),
        onDelete: () => host._deleteEmbed(offset),
        onFit: (f) => host._resizePicture(id, offset, f),
        link: host._picLink,
      ),
    );
  }
}

/// A picture in the text: click selects it; the eight handles resize it
/// (corners keep the proportions unless Shift is held), dragging the
/// picture moves it to another place in the text, and the bar above it
/// aligns, sizes or deletes it.
class _PictureBox extends StatefulWidget {
  const _PictureBox({
    super.key,
    required this.image,
    required this.zoom,
    required this.align,
    required this.selected,
    required this.onSelect,
    required this.onResize,
    required this.onMove,
    required this.onAlign,
    required this.onDelete,
    required this.onFit,
    required this.link,
  });

  final LayerLink link;
  final DocxImage image;
  final double zoom;
  final String? align;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double wEmu, double hEmu) onResize;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Attribute?> onAlign;
  final VoidCallback onDelete;
  final ValueChanged<double> onFit;

  @override
  State<_PictureBox> createState() => _PictureBoxState();
}

class _PictureBoxState extends State<_PictureBox> {
  Size? _live; // size while a handle is dragged
  Offset _drag = Offset.zero; // move preview
  bool _moving = false;
  Offset? _lastGlobal;

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    final z = widget.zoom;
    final w0 = img.widthEmu / 9525 * z, h0 = img.heightEmu / 9525 * z;
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : w0;
        final k = w0 > maxW ? maxW / w0 : 1.0;
        final size = _live ?? Size(w0 * k, h0 * k);
        final alignment = switch (widget.align) {
          'center' => Alignment.center,
          'right' => Alignment.centerRight,
          _ => Alignment.centerLeft,
        };
        const accent = kDocsAccent;
        Widget handle(Alignment a, MouseCursor cursor) {
          return Positioned(
            // Inside the picture so every handle is fully clickable.
            left: (a.x + 1) / 2 * (size.width - 12),
            top: (a.y + 1) / 2 * (size.height - 12),
            child: MouseRegion(
              cursor: cursor,
              child: _EagerPanDetector(
                onPanStart: (_) {},
                onPanUpdate: (d) => setState(() {
                  final cur = _live ?? size;
                  var w = cur.width + d.delta.dx * a.x;
                  var h = cur.height + d.delta.dy * a.y;
                  if (a.x != 0 &&
                      a.y != 0 &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    h = w * size.height / size.width; // corners keep the shape
                  }
                  _live = Size(w.clamp(16, maxW), h.clamp(16, 6000));
                }),
                onPanEnd: (_) {
                  final s = _live;
                  setState(() => _live = null);
                  if (s != null)
                    widget.onResize(s.width / z * 9525, s.height / z * 9525);
                },
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: accent, width: 1.6),
                    shape: a.x != 0 && a.y != 0
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                  ),
                ),
              ),
            ),
          );
        }

        final picture = Image.memory(
          img.bytes,
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            width: size.width,
            height: size.height,
            color: const Color(0x11000000),
            alignment: Alignment.center,
            child: const Text('Picture (kept as is)'),
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: maxW,
            child: Align(
              alignment: alignment,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  MouseRegion(
                    cursor: widget.selected
                        ? SystemMouseCursors.move
                        : SystemMouseCursors.click,
                    child: _EagerPanDetector(
                      // Pressing the picture claims the pointer at once, so the
                      // text editor does not start a text selection under it.
                      onPanStart: (_) => widget.onSelect(),
                      onPanUpdate: (d) => setState(() {
                        _drag += d.delta;
                        _lastGlobal = d.globalPosition;
                        if (_drag.distance > 4) _moving = true;
                      }),
                      onPanEnd: (_) {
                        final g = _lastGlobal;
                        final moved = _moving;
                        setState(() {
                          _moving = false;
                          _drag = Offset.zero;
                          _lastGlobal = null;
                        });
                        if (moved && g != null) widget.onMove(g);
                      },
                      child: Transform.translate(
                        offset: _drag,
                        child: Opacity(
                          opacity: _moving ? 0.6 : 1,
                          child: widget.selected
                              ? CompositedTransformTarget(
                                  link: widget.link,
                                  child: picture,
                                )
                              : picture,
                        ),
                      ),
                    ),
                  ),
                  if (widget.selected && !_moving) ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: accent, width: 1.6),
                          ),
                        ),
                      ),
                    ),
                    handle(
                      Alignment.topLeft,
                      SystemMouseCursors.resizeUpLeftDownRight,
                    ),
                    handle(
                      Alignment.topCenter,
                      SystemMouseCursors.resizeUpDown,
                    ),
                    handle(
                      Alignment.topRight,
                      SystemMouseCursors.resizeUpRightDownLeft,
                    ),
                    handle(
                      Alignment.centerLeft,
                      SystemMouseCursors.resizeLeftRight,
                    ),
                    handle(
                      Alignment.centerRight,
                      SystemMouseCursors.resizeLeftRight,
                    ),
                    handle(
                      Alignment.bottomLeft,
                      SystemMouseCursors.resizeUpRightDownLeft,
                    ),
                    handle(
                      Alignment.bottomCenter,
                      SystemMouseCursors.resizeUpDown,
                    ),
                    handle(
                      Alignment.bottomRight,
                      SystemMouseCursors.resizeUpLeftDownRight,
                    ),
                    if (_live != null)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${(_live!.width / z / 96 * 2.54).toStringAsFixed(1)} × ${(_live!.height / z / 96 * 2.54).toStringAsFixed(1)} cm',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pan detector that wins the gesture arena on pointer down (the editor's
/// own text-selection drag never starts underneath it).
class _EagerPanDetector extends StatelessWidget {
  const _EagerPanDetector({
    required this.child,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });
  final Widget child;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
        _EagerPan.new,
        (r) => r
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = onPanStart
          ..onUpdate = onPanUpdate
          ..onEnd = onPanEnd,
      ),
    },
    child: child,
  );
}

class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

class _PictureBar extends StatelessWidget {
  const _PictureBar({
    required this.align,
    required this.onAlign,
    required this.onFit,
    required this.onDelete,
  });
  final String? align;
  final ValueChanged<Attribute?> onAlign;
  final ValueChanged<double> onFit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(18),
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Theme(
        data: ThemeData.light(useMaterial3: true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TbButton(
              icon: Icons.format_align_left,
              tooltip: 'Align left',
              active: align == null,
              onTap: () => onAlign(null),
            ),
            TbButton(
              icon: Icons.format_align_center,
              tooltip: 'Center',
              active: align == 'center',
              onTap: () => onAlign(Attribute.centerAlignment),
            ),
            TbButton(
              icon: Icons.format_align_right,
              tooltip: 'Align right',
              active: align == 'right',
              onTap: () => onAlign(Attribute.rightAlignment),
            ),
            const TbDivider(),
            TbButton(
              icon: Icons.photo_size_select_large,
              tooltip: 'Size',
              label: 'Size',
              menu: [
                for (final (f, l) in [
                  (0.25, 'Small (25%)'),
                  (0.5, 'Medium (50%)'),
                  (0.75, 'Large (75%)'),
                  (1.0, 'Full width'),
                ])
                  MenuItemButton(onPressed: () => onFit(f), child: Text(l)),
              ],
            ),
            const TbDivider(),
            TbButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete image',
              onTap: onDelete,
            ),
          ],
        ),
      ),
    ),
  );
}

class _TableEmbed extends EmbedBuilder {
  _TableEmbed(this.doc, this.zoom, {required this.onEdit});
  final DocxDocument doc;
  final double zoom;
  final void Function(String id, int offset) onEdit;

  @override
  String get key => 'doctable';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final id = embedContext.node.value.data as String;
    final xml = doc.tables[id];
    if (xml == null) return const SizedBox.shrink();
    final rows = docxTableRows(xml);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return Tooltip(
      message: 'Double-click to edit the table',
      waitDuration: const Duration(milliseconds: 800),
      child: GestureDetector(
        onDoubleTap: () => onEdit(id, embedContext.node.documentOffset),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Table(
            border: TableBorder.all(color: const Color(0xFF7F7F7F), width: 0.7),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final r in rows)
                TableRow(
                  children: [
                    for (var i = 0; i < cols; i++)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6 * zoom,
                          vertical: 3 * zoom,
                        ),
                        child: Text(
                          i < r.length ? r[i] : '',
                          style: const TextStyle(
                            fontSize: 14.6,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakEmbed extends EmbedBuilder {
  @override
  String get key => 'docbreak';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFF9E9E9E))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Page Break',
            style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
          ),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFF9E9E9E))),
      ],
    ),
  );
}

class _UnknownEmbed extends EmbedBuilder {
  @override
  String get key => 'unknown';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const SizedBox.shrink();
}

class _SectionEmbed extends EmbedBuilder {
  @override
  String get key => 'docsect';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFB0B0B0))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Section break',
            style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
          ),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFB0B0B0))),
      ],
    ),
  );
}

class _RuleEmbed extends EmbedBuilder {
  @override
  String get key => 'dochr';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, thickness: 1, color: Color(0xFF7F7F7F)),
      );
}

/// Header or footer in the page margin: shows its text (page fields
/// filled in); double-click edits it, with alignment and page numbers.
class _RunningBand extends StatefulWidget {
  const _RunningBand({
    super.key,
    required this.running,
    required this.kind,
    required this.zoom,
    required this.pages,
    required this.onChanged,
  });
  final DocxRunning running;
  final String kind;
  final double zoom;
  final int pages;
  final VoidCallback onChanged;

  @override
  State<_RunningBand> createState() => _RunningBandState();
}

class _RunningBandState extends State<_RunningBand> {
  bool _editing = false;

  void edit() => setState(() => _editing = true);
  bool _hover = false;
  late final _text = TextEditingController(text: widget.running.text);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_RunningBand old) {
    super.didUpdateWidget(old);
    if (!_editing && _text.text != widget.running.text)
      _text.text = widget.running.text;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  TextAlign get _align => switch (widget.running.align) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    _ => TextAlign.center,
  };

  void _set({String? text, String? align}) {
    final r = widget.running;
    if (text != null) r.text = text;
    if (align != null) r.align = align;
    widget.onChanged();
    setState(() {});
  }

  void _insertField(String f) {
    final sel = _text.selection;
    final at = sel.isValid ? sel.start : _text.text.length;
    final t = _text.text.replaceRange(at, sel.isValid ? sel.end : at, f);
    _text.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: at + f.length),
    );
    _set(text: t);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.running;
    final style = TextStyle(
      fontSize: 10 * 4 / 3 * widget.zoom,
      color: const Color(0xFF404040),
      height: 1.3,
    );
    if (_editing) {
      return TapRegion(
        onTapOutside: (_) => setState(() => _editing = false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.kind == 'Footer') _bar(),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: kDocsAccent.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Theme(
                data: ThemeData.light(useMaterial3: true),
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  maxLines: null,
                  textAlign: _align,
                  style: style,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '${widget.kind} text',
                    contentPadding: const EdgeInsets.all(6),
                  ),
                  onChanged: (v) => _set(text: v),
                ),
              ),
            ),
            if (widget.kind == 'Header') _bar(),
          ],
        ),
      );
    }
    final shown = r.text
        .replaceAll('{PAGE}', '1')
        .replaceAll('{PAGES}', '${widget.pages}');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => setState(() => _editing = true),
        child: Container(
          constraints: const BoxConstraints(minHeight: 18),
          decoration: BoxDecoration(
            border: _hover
                ? Border(
                    bottom: BorderSide(
                      color: kDocsAccent.withValues(alpha: 0.35),
                    ),
                  )
                : null,
          ),
          child: Text(
            r.isEmpty
                ? (_hover
                      ? 'Double-click to add a ${widget.kind.toLowerCase()}'
                      : '')
                : shown,
            textAlign: r.isEmpty ? TextAlign.center : _align,
            style: r.isEmpty
                ? style.copyWith(
                    color: const Color(0xFFAAAAAA),
                    fontStyle: FontStyle.italic,
                  )
                : style,
          ),
        ),
      ),
    );
  }

  Widget _bar() => Theme(
    data: ThemeData.light(useMaterial3: true),
    child: Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '  ${widget.kind}  ',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            TbButton(
              icon: Icons.format_align_left,
              tooltip: 'Left',
              size: 26,
              active: widget.running.align == 'left',
              onTap: () => _set(align: 'left'),
            ),
            TbButton(
              icon: Icons.format_align_center,
              tooltip: 'Center',
              size: 26,
              active: widget.running.align == 'center',
              onTap: () => _set(align: 'center'),
            ),
            TbButton(
              icon: Icons.format_align_right,
              tooltip: 'Right',
              size: 26,
              active: widget.running.align == 'right',
              onTap: () => _set(align: 'right'),
            ),
            const TbDivider(),
            TbButton(
              icon: Icons.tag,
              label: 'Page #',
              tooltip: 'Insert page number',
              size: 26,
              onTap: () => _insertField('{PAGE}'),
            ),
            TbButton(
              icon: Icons.functions,
              label: 'Total',
              tooltip: 'Insert page count',
              size: 26,
              onTap: () => _insertField('{PAGES}'),
            ),
            const TbDivider(),
            TbButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove ${widget.kind.toLowerCase()}',
              size: 26,
              onTap: () {
                _text.clear();
                _set(text: '');
                setState(() => _editing = false);
              },
            ),
            TbButton(
              icon: Icons.check,
              tooltip: 'Done',
              size: 26,
              onTap: () => setState(() => _editing = false),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Google Docs-style ruler over the page: centimetre ticks, the margins
/// shaded, and the left / right margin markers dragged to change them.
class _Ruler extends StatefulWidget {
  const _Ruler({
    required this.page,
    required this.zoom,
    required this.pageW,
    required this.onMargins,
  });
  final DocxPageSetup page;
  final double zoom;
  final double pageW;
  final void Function(int left, int right, {required bool done}) onMargins;

  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  double? _left, _right; // twips while dragging

  @override
  Widget build(BuildContext context) {
    final twPx = widget.pageW / widget.page.width; // px per twip
    final left = _left ?? widget.page.left.toDouble();
    final right = _right ?? widget.page.right.toDouble();
    Widget marker(bool isLeft) {
      final x = isLeft ? left * twPx : widget.pageW - right * twPx;
      return Positioned(
        left: x - 7,
        top: 10,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() {
              final dt = d.delta.dx / twPx;
              if (isLeft) {
                _left = (left + dt)
                    .clamp(0, widget.page.width - right - 1440)
                    .toDouble();
              } else {
                _right = (right - dt)
                    .clamp(0, widget.page.width - left - 1440)
                    .toDouble();
              }
              widget.onMargins(left.round(), right.round(), done: false);
            }),
            onHorizontalDragEnd: (_) {
              widget.onMargins(
                (_left ?? left).round(),
                (_right ?? right).round(),
                done: true,
              );
              setState(() => _left = _right = null);
            },
            child: Tooltip(
              message: isLeft
                  ? 'Left margin ${(left / 567).toStringAsFixed(2)} cm'
                  : 'Right margin ${(right / 567).toStringAsFixed(2)} cm',
              child: CustomPaint(
                size: const Size(14, 12),
                painter: _MarkerPainter(),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.pageW,
      height: 24,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RulerPainter(
                twPx: twPx,
                pageTw: widget.page.width,
                left: left,
                right: right,
              ),
            ),
          ),
          marker(true),
          marker(false),
        ],
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = kDocsAccent);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => false;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.twPx,
    required this.pageTw,
    required this.left,
    required this.right,
  });
  final double twPx, left, right;
  final int pageTw;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8EAED),
    );
    canvas.drawRect(
      Rect.fromLTRB(left * twPx, 2, size.width - right * twPx, size.height - 2),
      Paint()..color = Colors.white,
    );
    final tick = Paint()
      ..color = const Color(0xFF80868B)
      ..strokeWidth = 1;
    const cm = 567.0; // twips
    for (var k = 1; k * cm / 4 < pageTw; k++) {
      final x = k * cm / 4 * twPx;
      final major = k % 4 == 0;
      final half = k % 2 == 0;
      canvas.drawLine(
        Offset(x, size.height - (major ? 0 : (half ? 7 : 4))),
        Offset(x, size.height),
        tick,
      );
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${k ~/ 4}',
            style: const TextStyle(fontSize: 9, color: Color(0xFF5F6368)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 2));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.twPx != twPx ||
      old.left != left ||
      old.right != right ||
      old.pageTw != pageTw;
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({
    super.key,
    required this.comment,
    required this.quote,
    required this.active,
    required this.editing,
    required this.onTap,
    required this.onEdit,
    required this.onSaved,
    required this.onCancel,
    required this.onResolve,
  });

  final DocxComment comment;
  final String quote;
  final bool active, editing;
  final VoidCallback onTap, onEdit, onCancel, onResolve;
  final ValueChanged<String> onSaved;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  late final _text = TextEditingController(text: widget.comment.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.comment;
    final initials = c.author
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final d = c.date.toLocal();
    final when =
        '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.active
              ? kDocsAccent
              : DsColors.border(theme.brightness),
          width: widget.active ? 1.6 : 1,
        ),
        boxShadow: widget.active
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: kDocsAccent.withValues(alpha: 0.15),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: const TextStyle(
                        fontSize: 11,
                        color: kDocsAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.author.isEmpty ? 'Anonymous' : c.author,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          when,
                          style: TextStyle(
                            fontSize: 11,
                            color: DsColors.textSecondary(theme.brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.editing) ...[
                    TbButton(
                      icon: Icons.check_circle_outline,
                      tooltip: 'Resolve (removes the comment)',
                      size: 26,
                      onTap: widget.onResolve,
                    ),
                    TbButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      size: 26,
                      onTap: widget.onEdit,
                    ),
                  ],
                ],
              ),
              if (widget.quote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 6),
                  child: Text(
                    '"${widget.quote}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: DsColors.textSecondary(theme.brightness),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              if (widget.editing) ...[
                TextField(
                  controller: _text,
                  autofocus: true,
                  maxLines: null,
                  minLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Add a comment…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kDocsAccent,
                      ),
                      onPressed: () => _text.text.trim().isEmpty
                          ? widget.onCancel()
                          : widget.onSaved(_text.text.trim()),
                      child: const Text('Comment'),
                    ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    c.text,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.kind,
    required this.mark,
    required this.quote,
    required this.onTap,
    required this.onAccept,
    required this.onReject,
  });

  final String kind, mark, quote;
  final VoidCallback onTap, onAccept, onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (author, date) = suggestionInfo(mark);
    final d = date.toLocal();
    final add = kind == 'ins';
    final color = add ? const Color(0xFF188038) : const Color(0xFFC5221F);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DsColors.border(theme.brightness)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author.isEmpty ? 'Anonymous' : author,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: DsColors.textSecondary(theme.brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TbButton(
                    icon: Icons.check,
                    tooltip: 'Accept suggestion',
                    size: 26,
                    onTap: onAccept,
                  ),
                  TbButton(
                    icon: Icons.close,
                    tooltip: 'Reject suggestion',
                    size: 26,
                    onTap: onReject,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: add ? 'Add: ' : 'Delete: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: '"$quote"',
                      style: TextStyle(
                        color: color,
                        decoration: add ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
