import 'package:document_studio/features/compose/template_gallery_screen.dart'
    show templateGalleryRoutePath;
import 'package:document_studio/features/compose/compose_templates.dart';
import 'package:flutter/rendering.dart' show RenderEditable;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compose/compose_highlight.dart';
import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_pdf.dart';
import 'package:document_studio/features/compose/compose_snippets.dart';
import 'package:document_studio/features/compose/compose_starters.dart';
import 'package:document_studio/features/compose/math_raster.dart';
import 'package:document_studio/features/compose/parsers/html_to_model.dart';
import 'package:document_studio/features/compose/parsers/latex_to_model.dart';
import 'package:document_studio/features/compose/parsers/markdown_to_model.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

const composeRoutePath = '/compose';

/// Compiles [source] to PDF bytes, entirely on this device.
Future<(Uint8List, ComposeDoc)> compileCompose(
  ComposeLanguage language,
  String source, {
  String? baseDir,
  String pageSize = 'A4',
  bool? serif,
  double? fontSize,
  double? marginPt,
}) async {
  var doc = switch (language) {
    ComposeLanguage.markdown => markdownToCompose(source, pageSize: pageSize),
    ComposeLanguage.html => htmlToCompose(source, pageSize: pageSize),
    ComposeLanguage.latex => latexToCompose(source),
  };
  if (language != ComposeLanguage.latex) {
    doc = doc.copyWith(
      serif: serif,
      baseFontSize: fontSize,
      marginPt: marginPt,
    );
  }
  final bytes = await renderComposePdf(
    doc,
    fonts: await ComposeFonts.load(),
    math: MathRaster.instance.render,
    baseDir: baseDir,
  );
  return (bytes, doc);
}

/// Overleaf-style writer: source on the left, live PDF on the right (or a
/// switch between them on a narrow window), syntax colouring, snippets with
/// help for every command / tag, autocomplete, open / save source, export.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({
    super.key,
    this.language = ComposeLanguage.markdown,
    this.templateId,
  });

  final ComposeLanguage language;

  /// Start from this template instead of the saved draft.
  final String? templateId;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late ComposeLanguage _lang = widget.language;
  late final ComposeEditingController _ctrl = ComposeEditingController(
    language: _lang,
  );
  final _focus = FocusNode(debugLabel: 'compose-editor');
  final _editorScroll = ScrollController();

  String _name = 'Untitled';
  bool _templateApplied = false;
  String? _sourcePath;
  String _pageSize = 'A4';
  bool _autoCompile = true;
  bool _showHelp = false;
  bool _previewOnNarrow = false;
  double _split = 0.5;

  Timer? _debounce;
  Timer? _draftTimer;
  bool _compiling = false;
  bool _dirtyAfterCompile = false;
  Uint8List? _pdf;
  int _pdfRevision = 0;

  /// Inputs of the last successful compile; used to skip no-op rebuilds.
  String? _lastCompileFingerprint;
  ComposeDoc? _doc;
  String? _error;
  int _ms = 0;

  // Autocomplete.
  List<ComposeSnippet> _suggestions = const [];
  int _prefixLength = 0;
  int _selIndex = 0;
  final _fieldKey = GlobalKey();
  final _editorStackKey = GlobalKey();
  Offset? _caret;

  // Format (Markdown / HTML; LaTeX sets these in \documentclass).
  bool _serif = false;
  double _fontSize = 11;
  double _marginPt = 56;

  // Find & replace.
  bool _findOpen = false;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  int _findIndex = -1;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _draftTimer?.cancel();
    _ctrl
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    _editorScroll.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  String get _draftKey => 'compose_draft_${_lang.extension}';

  Future<void> _restoreDraft() async {
    final tpl = widget.templateId == null
        ? null
        : templateById(widget.templateId!);
    if (tpl != null && tpl.language == _lang && !_templateApplied) {
      _templateApplied = true;
      _name = tpl.name;
      _ctrl.text = tpl.source;
      _ctrl.selection = const TextSelection.collapsed(offset: 0);
      unawaited(_compile());
      return;
    }
    String? text;
    try {
      text = (await SharedPreferences.getInstance()).getString(_draftKey);
    } catch (_) {}
    if (!mounted) return;
    _ctrl.text = (text == null || text.trim().isEmpty)
        ? composeStarter(_lang)
        : text;
    _ctrl.selection = const TextSelection.collapsed(offset: 0);
    unawaited(_compile());
  }

  /// Longer pause before auto-compile on large sources so typing does not
  /// thrash parse → PDF → preview.
  Duration _compileDebounce({bool afterBusy = false}) {
    final n = _ctrl.text.length;
    final baseMs = n < 20000
        ? 650
        : n < 80000
        ? 1200
        : 1800;
    if (!afterBusy) return Duration(milliseconds: baseMs);
    return Duration(milliseconds: (baseMs ~/ 2).clamp(300, 1500));
  }

  String _compileFingerprint() {
    final baseDir = _sourcePath == null ? '' : p.dirname(_sourcePath!);
    return '${_lang.name}\x00$_pageSize\x00$_serif\x00$_fontSize'
        '\x00$_marginPt\x00$baseDir\x00${_ctrl.text}';
  }

  void _onChanged() {
    _updateSuggestions();
    _dirtyAfterCompile = true;
    if (_autoCompile) {
      _debounce?.cancel();
      _debounce = Timer(_compileDebounce(), () => unawaited(_compile()));
    }
    // Drafts survive closing the app (per language).
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await (await SharedPreferences.getInstance()).setString(
          _draftKey,
          _ctrl.text,
        );
      } catch (_) {}
    });
    if (mounted) setState(() {});
  }

  Future<void> _compile() async {
    if (_compiling) {
      _dirtyAfterCompile = true;
      return;
    }
    final fingerprint = _compileFingerprint();
    if (fingerprint == _lastCompileFingerprint && _pdf != null) {
      _dirtyAfterCompile = false;
      return;
    }
    _compiling = true;
    _dirtyAfterCompile = false;
    if (mounted) setState(() {});
    final sw = Stopwatch()..start();
    try {
      final (bytes, doc) = await compileCompose(
        _lang,
        _ctrl.text,
        baseDir: _sourcePath == null ? null : p.dirname(_sourcePath!),
        pageSize: _pageSize,
        serif: _serif,
        fontSize: _fontSize,
        marginPt: _marginPt,
      );
      if (!mounted) return;
      _lastCompileFingerprint = fingerprint;
      setState(() {
        _pdf = bytes;
        _pdfRevision++;
        _doc = doc;
        _error = null;
        _ms = sw.elapsedMilliseconds;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _compiling = false;
      if (mounted) setState(() {});
      // Typed while compiling: one more pass.
      if (_dirtyAfterCompile && _autoCompile && mounted) {
        _debounce?.cancel();
        _debounce = Timer(
          _compileDebounce(afterBusy: true),
          () => unawaited(_compile()),
        );
      }
    }
  }

  void _updateSuggestions() {
    final sel = _ctrl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    final before = _ctrl.text.substring(0, sel.baseOffset);
    final m = switch (_lang) {
      ComposeLanguage.latex =>
        RegExp(r'\\[A-Za-z]{1,}$').firstMatch(before) ??
            RegExp(r'\\begin\{[A-Za-z]*$').firstMatch(before),
      ComposeLanguage.html =>
        RegExp(r'<[A-Za-z]{1,}$').firstMatch(before) ??
            RegExp(r'\\[A-Za-z]{2,}$').firstMatch(before),
      ComposeLanguage.markdown => RegExp(r'\\[A-Za-z]{2,}$').firstMatch(before),
    };
    if (m == null) {
      if (_suggestions.isNotEmpty) _suggestions = const [];
      return;
    }
    final typed = m.group(0)!;
    final list = [
      for (final s in snippetsFor(_lang))
        if (s.trigger != null &&
            s.trigger!.startsWith(typed) &&
            s.trigger != typed)
          s,
    ];
    final exact = [
      for (final s in snippetsFor(_lang))
        if (s.trigger == typed) s,
    ];
    _prefixLength = typed.length;
    _suggestions = [...exact, ...list].take(12).toList();
    _selIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateCaret());
  }

  /// Where the caret is on screen, for the suggestion list.
  void _locateCaret() {
    if (!mounted) return;
    RenderEditable? editable;
    void visit(Element e) {
      if (editable != null) return;
      final ro = e.renderObject;
      if (ro is RenderEditable) {
        editable = ro;
        return;
      }
      e.visitChildren(visit);
    }

    (_fieldKey.currentContext as Element?)?.visitChildren(visit);
    final stackBox =
        _editorStackKey.currentContext?.findRenderObject() as RenderBox?;
    final ed = editable;
    if (ed == null || stackBox == null || !ed.attached) return;
    final sel = _ctrl.selection;
    if (!sel.isValid) return;
    final rect = ed.getLocalRectForCaret(TextPosition(offset: sel.baseOffset));
    final global = ed.localToGlobal(rect.bottomLeft);
    final local = stackBox.globalToLocal(global);
    if (_caret != local) setState(() => _caret = local);
  }

  /// Arrow keys / Enter / Tab / Esc drive the suggestion list.
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    // Enter after \begin{env} closes the environment (LaTeX), like Overleaf.
    if (_suggestions.isEmpty &&
        _lang == ComposeLanguage.latex &&
        k == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      final sel = _ctrl.selection;
      if (sel.isValid && sel.isCollapsed) {
        final before = _ctrl.text.substring(0, sel.baseOffset);
        final lineStart = before.lastIndexOf('\n') + 1;
        final line = before.substring(lineStart);
        final m = RegExp(r'^(\s*)\\begin\{([^}]+)\}(\[[^\]]*\])?\s*$')
            .firstMatch(line);
        if (m != null) {
          final env = m.group(2)!;
          final indent = m.group(1)!;
          final after = _ctrl.text.substring(sel.baseOffset);
          final open = RegExp('\\\\begin\\{${RegExp.escape(env)}\\}')
              .allMatches(_ctrl.text)
              .length;
          final close = RegExp('\\\\end\\{${RegExp.escape(env)}\\}')
              .allMatches(_ctrl.text)
              .length;
          if (open > close || !after.contains('\\end{$env}')) {
            final item = const {'itemize', 'enumerate'}.contains(env)
                ? '\\item '
                : '';
            _ctrl.insertSnippet('\n$indent  $item\$|\n$indent\\end{$env}');
            return KeyEventResult.handled;
          }
        }
      }
    }
    if (_suggestions.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _selIndex = (_selIndex + 1) % _suggestions.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selIndex =
            (_selIndex - 1 + _suggestions.length) % _suggestions.length,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.tab) {
      _acceptSuggestion(
        _suggestions[_selIndex.clamp(0, _suggestions.length - 1)],
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() => _suggestions = const []);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------- find / replace

  List<int> _matches() {
    final q = _findCtrl.text;
    if (q.isEmpty) return const [];
    final t = _ctrl.text.toLowerCase();
    final needle = q.toLowerCase();
    final out = <int>[];
    var i = t.indexOf(needle);
    while (i >= 0) {
      out.add(i);
      i = t.indexOf(needle, i + needle.length);
    }
    return out;
  }

  void _findStep(int dir) {
    final m = _matches();
    if (m.isEmpty) return;
    _findIndex = (_findIndex + dir) % m.length;
    if (_findIndex < 0) _findIndex += m.length;
    final at = m[_findIndex];
    _ctrl.selection = TextSelection(
      baseOffset: at,
      extentOffset: at + _findCtrl.text.length,
    );
    _focus.requestFocus();
    setState(() {});
  }

  void _replaceOne() {
    final sel = _ctrl.selection;
    if (sel.isValid &&
        !sel.isCollapsed &&
        sel.textInside(_ctrl.text).toLowerCase() ==
            _findCtrl.text.toLowerCase()) {
      _ctrl.insertSnippet(_replaceCtrl.text);
    }
    _findStep(1);
  }

  void _replaceAll() {
    final q = _findCtrl.text;
    if (q.isEmpty) return;
    final re = RegExp(RegExp.escape(q), caseSensitive: false);
    final n = re.allMatches(_ctrl.text).length;
    _ctrl.text = _ctrl.text.replaceAll(re, _replaceCtrl.text);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Replaced $n')));
  }

  // -------------------------------------------------------------- outline

  /// Headings of the source with their offsets (for "Outline").
  List<(int level, String title, int offset)> _outline() {
    final out = <(int, String, int)>[];
    final t = _ctrl.text;
    final re = switch (_lang) {
      ComposeLanguage.latex => RegExp(
        r'\\(chapter|section|subsection|subsubsection)\*?\{([^}]*)\}',
      ),
      ComposeLanguage.markdown => RegExp(r'^(#{1,6})\s+(.+)$', multiLine: true),
      ComposeLanguage.html => RegExp(
        r'<h([1-6])[^>]*>([\s\S]*?)</h>',
        caseSensitive: false,
      ),
    };
    for (final m in re.allMatches(t)) {
      final level = switch (_lang) {
        ComposeLanguage.latex =>
          const {
                'chapter': 1,
                'section': 1,
                'subsection': 2,
                'subsubsection': 3,
              }[m.group(1)] ??
              1,
        ComposeLanguage.markdown => m.group(1)!.length,
        ComposeLanguage.html => int.parse(m.group(1)!),
      };
      out.add((
        level,
        m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
        m.start,
      ));
    }
    return out;
  }

  void _jumpTo(int offset) {
    _ctrl.selection = TextSelection.collapsed(offset: offset);
    _focus.requestFocus();
    // Scroll roughly to the line.
    final line = '\n'.allMatches(_ctrl.text.substring(0, offset)).length;
    if (_editorScroll.hasClients) {
      final y = (line * 13.5 * _Gutter.lineHeight - 80).clamp(
        0.0,
        _editorScroll.position.maxScrollExtent,
      );
      _editorScroll.animateTo(
        y,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _applyTemplate(ComposeTemplate t) async {
    final ok =
        _ctrl.text.trim().isEmpty ||
        await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Start from "${t.name}"?'),
                content: const Text('This replaces the text in the editor.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Replace'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!ok) return;
    _ctrl.text = t.source;
    _ctrl.selection = const TextSelection.collapsed(offset: 0);
    unawaited(_compile());
  }

  void _acceptSuggestion(ComposeSnippet s) {
    _ctrl.completeWith(_prefixLength, s.insert);
    _suggestions = const [];
    _focus.requestFocus();
    setState(() {});
  }

  void _insert(String snippet) {
    _ctrl.insertSnippet(snippet);
    _focus.requestFocus();
  }

  Future<void> _switchLanguage(ComposeLanguage l) async {
    if (l == _lang) return;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _draftKey,
        _ctrl.text,
      );
    } catch (_) {}
    setState(() {
      _lang = l;
      _ctrl.language = l;
      _sourcePath = null;
      _suggestions = const [];
    });
    await _restoreDraft();
  }

  Future<void> _openFile() async {
    final storage = ref.read(fileStorageProvider);
    final picked = await storage.pickOpenFile(
      allowedExtensions: const ['md', 'markdown', 'txt', 'html', 'htm', 'tex'],
    );
    if (picked == null) return;
    final text = await File(picked.path).readAsString();
    final ext = p.extension(picked.path).toLowerCase();
    final lang = switch (ext) {
      '.tex' => ComposeLanguage.latex,
      '.html' || '.htm' => ComposeLanguage.html,
      _ => ComposeLanguage.markdown,
    };
    setState(() {
      _lang = lang;
      _ctrl.language = lang;
      _sourcePath = picked.path;
      _name = p.basenameWithoutExtension(picked.path);
    });
    _ctrl.text = text;
    unawaited(_compile());
  }

  Future<void> _saveSource() async {
    final storage = ref.read(fileStorageProvider);
    final bytes = Uint8List.fromList(utf8.encode(_ctrl.text));
    final path = await storage.pickSavePath(
      suggestedName: '$_name.${_lang.extension}',
      bytes: bytes,
      allowedExtensions: [_lang.extension],
    );
    if (path == null) return;
    await File(path).writeAsString(_ctrl.text, flush: true);
    if (!mounted) return;
    setState(() {
      _sourcePath = path;
      _name = p.basenameWithoutExtension(path);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved ${p.basename(path)}')));
  }

  Future<void> _exportPdf() async {
    if (_dirtyAfterCompile || _pdf == null) await _compile();
    final bytes = _pdf;
    if (bytes == null || !mounted) return;
    final storage = ref.read(fileStorageProvider);
    final path = await storage.pickSavePath(
      suggestedName: '$_name.pdf',
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (path == null) return;
    await storage.writeAtomic(
      destinationPath: path,
      writeToTemp: (t) => File(t).writeAsBytes(bytes, flush: true),
    );
    if (!mounted) return;
    showDocumentSaveResultActions(
      context,
      file: LocalFileRef(
        path: path,
        displayName: p.basename(path),
        sizeBytes: bytes.length,
      ),
      message: 'PDF saved: ${p.basename(path)}',
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _ctrl.dark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;
    final showPreview = wide || _previewOnNarrow;
    final showEditor = wide || !_previewOnNarrow;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_exportPdf()),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_exportPdf()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_compile()),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _insert(_wrap('bold')),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _insert(_wrap('italic')),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _findOpen = !_findOpen),
        const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
            setState(() => _showHelp = !_showHelp),
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  '$_name.${_lang.extension}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<ComposeLanguage>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final l in ComposeLanguage.values)
                    ButtonSegment(value: l, label: Text(l.label)),
                ],
                selected: {_lang},
                onSelectionChanged: (s) => unawaited(_switchLanguage(s.first)),
              ),
            ],
          ),
          actions: [
            if (!wide)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit_note, size: 18),
                      label: Text('Edit'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text('Preview'),
                    ),
                  ],
                  selected: {_previewOnNarrow},
                  onSelectionChanged: (s) {
                    setState(() => _previewOnNarrow = s.first);
                    if (s.first && _dirtyAfterCompile) unawaited(_compile());
                  },
                ),
              ),
            IconButton(
              tooltip: 'Open .md / .html / .tex',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => unawaited(_openFile()),
            ),
            IconButton(
              tooltip: 'Save source',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => unawaited(_saveSource()),
            ),
            IconButton(
              tooltip: 'Help: every command / tag (Ctrl+/)',
              isSelected: _showHelp,
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => setState(() => _showHelp = !_showHelp),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: () => unawaited(_exportPdf()),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Export PDF'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final editor = _editorPane(theme);
            final preview = _previewPane(theme);
            final help = _showHelp
                ? SizedBox(
                    width: wide ? 340 : c.maxWidth,
                    child: _SnippetPanel(
                      language: _lang,
                      onInsert: (s) {
                        _insert(s.insert);
                        if (!wide) setState(() => _showHelp = false);
                      },
                      onClose: () => setState(() => _showHelp = false),
                    ),
                  )
                : null;
            if (!wide) {
              if (help != null) return help;
              return showPreview ? preview : editor;
            }
            final available = c.maxWidth - (help == null ? 0 : 340) - 6;
            final leftW = (available * _split).clamp(280.0, available - 280);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?help,
                if (help != null) const VerticalDivider(width: 1),
                if (showEditor) SizedBox(width: leftW, child: editor),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => setState(() {
                      _split = ((leftW + d.delta.dx) / available).clamp(
                        0.2,
                        0.8,
                      );
                    }),
                    child: Container(
                      width: 6,
                      color: DsColors.border(theme.brightness),
                    ),
                  ),
                ),
                Expanded(child: preview),
              ],
            );
          },
        ),
      ),
    );
  }

  String _wrap(String what) => switch ((_lang, what)) {
    (ComposeLanguage.latex, 'bold') => r'\textbf{$SEL$|}',
    (ComposeLanguage.latex, _) => r'\textit{$SEL$|}',
    (ComposeLanguage.html, 'bold') => r'<b>$SEL$|</b>',
    (ComposeLanguage.html, _) => r'<i>$SEL$|</i>',
    (_, 'bold') => r'**$SEL$|**',
    _ => r'*$SEL$|*',
  };

  List<(IconData, String, String)> get _quick => switch (_lang) {
    ComposeLanguage.latex => [
      (Icons.title, 'Section', r'\section{$SEL$|}'),
      (Icons.format_bold, 'Bold (Ctrl+B)', r'\textbf{$SEL$|}'),
      (Icons.format_italic, 'Italic (Ctrl+I)', r'\textit{$SEL$|}'),
      (
        Icons.format_list_bulleted,
        'Bulleted list',
        '\\begin{itemize}\n  \\item \$|\n\\end{itemize}',
      ),
      (
        Icons.format_list_numbered,
        'Numbered list',
        '\\begin{enumerate}\n  \\item \$|\n\\end{enumerate}',
      ),
      (Icons.functions, 'Inline maths', r'$$|$'),
      (
        Icons.calculate_outlined,
        'Equation',
        '\\begin{equation}\n  \$|\n\\end{equation}',
      ),
      (
        Icons.table_chart_outlined,
        'Table',
        '\\begin{tabular}{|l|l|}\n  \\hline\n  \$|A & B \\\\\n  \\hline\n\\end{tabular}',
      ),
      (
        Icons.image_outlined,
        'Figure',
        '\\begin{figure}[h]\n  \\centering\n  \\includegraphics[width=0.6\\textwidth]{\$|image.png}\n  \\caption{Caption}\n\\end{figure}',
      ),
      (Icons.link, 'Link', r'\href{https://$|}{$SEL}'),
      (Icons.notes, 'Footnote', r'\footnote{$|}'),
    ],
    ComposeLanguage.html => [
      (Icons.title, 'Heading', r'<h2>$SEL$|</h2>'),
      (Icons.format_bold, 'Bold (Ctrl+B)', r'<b>$SEL$|</b>'),
      (Icons.format_italic, 'Italic (Ctrl+I)', r'<i>$SEL$|</i>'),
      (
        Icons.format_list_bulleted,
        'Bulleted list',
        '<ul>\n  <li>\$|</li>\n</ul>',
      ),
      (
        Icons.format_list_numbered,
        'Numbered list',
        '<ol>\n  <li>\$|</li>\n</ol>',
      ),
      (Icons.functions, 'Inline maths', r'\($|\)'),
      (
        Icons.table_chart_outlined,
        'Table',
        '<table>\n  <tr><th>A</th><th>B</th></tr>\n  <tr><td>\$|</td><td></td></tr>\n</table>',
      ),
      (Icons.image_outlined, 'Image', r'<img src="$|image.png" width="60%">'),
      (Icons.link, 'Link', r'<a href="https://$|">$SEL</a>'),
    ],
    ComposeLanguage.markdown => [
      (Icons.title, 'Heading', r'## $SEL$|'),
      (Icons.format_bold, 'Bold (Ctrl+B)', r'**$SEL$|**'),
      (Icons.format_italic, 'Italic (Ctrl+I)', r'*$SEL$|*'),
      (Icons.format_list_bulleted, 'Bulleted list', '- \$|\n- '),
      (Icons.format_list_numbered, 'Numbered list', '1. \$|\n2. '),
      (Icons.check_box_outlined, 'Task list', '- [ ] \$|'),
      (Icons.functions, 'Inline maths', r'$$|$'),
      (Icons.code, 'Code block', '```\n\$SEL\$|\n```'),
      (
        Icons.table_chart_outlined,
        'Table',
        '| A | B |\n|---|---|\n| \$| |   |',
      ),
      (Icons.image_outlined, 'Image', r'![caption]($|image.png)'),
      (Icons.link, 'Link', r'[$SEL$|](https://)'),
      (Icons.format_quote, 'Quote', r'> $SEL$|'),
    ],
  };

  Widget _menuButton({
    required IconData icon,
    required String label,
    required List<Widget> children,
  }) {
    return MenuAnchor(
      menuChildren: children,
      builder: (context, menu, _) => TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: Icon(icon, size: 18),
        label: Text('$label ▾', style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _findBar(ThemeData theme) {
    final m = _matches();
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _findCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Find',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _findIndex = -1),
                onSubmitted: (_) => _findStep(1),
              ),
            ),
            Text(
              m.isEmpty
                  ? '0'
                  : '${_findIndex < 0 ? 0 : _findIndex + 1}/${m.length}',
              style: theme.textTheme.labelSmall,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _findStep(-1),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _findStep(1),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _replaceCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Replace with',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            TextButton(onPressed: _replaceOne, child: const Text('Replace')),
            TextButton(onPressed: _replaceAll, child: const Text('All')),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _findOpen = false),
            ),
          ],
        ),
      ),
    );
  }

  /// Overleaf-style completion list under the caret.
  Widget _suggestionPopup(ThemeData theme, BoxConstraints box) {
    const w = 360.0;
    final c = _caret!;
    final left = c.dx.clamp(
      0.0,
      (box.maxWidth - w - 40).clamp(0.0, double.infinity),
    );
    final rowH = 44.0;
    final h = (_suggestions.length * rowH).clamp(rowH, rowH * 6);
    final below = c.dy + h + 8 < box.maxHeight;
    return Positioned(
      left: left,
      top: below ? c.dy + 4 : null,
      bottom: below
          ? null
          : (box.maxHeight - c.dy + 22).clamp(0.0, box.maxHeight),
      width: w,
      height: h,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surface,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _suggestions.length,
          itemExtent: rowH,
          itemBuilder: (context, i) {
            final s = _suggestions[i];
            final sel = i == _selIndex;
            return InkWell(
              onTap: () => _acceptSuggestion(s),
              child: Container(
                color: sel ? DsColors.primary.withValues(alpha: 0.12) : null,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          s.trigger ?? s.label,
                          style: const TextStyle(
                            fontFamily: 'DS Mono',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (sel)
                          Text('Tab ↹', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    Text(
                      s.help,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _editorPane(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final sel = _ctrl.selection;
    final before = sel.isValid
        ? _ctrl.text.substring(0, sel.baseOffset.clamp(0, _ctrl.text.length))
        : '';
    final line = '\n'.allMatches(before).length + 1;
    final col = before.length - (before.lastIndexOf('\n') + 1) + 1;
    final lines = '\n'.allMatches(_ctrl.text).length + 1;
    return ColoredBox(
      color: dark ? const Color(0xFF161B22) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: dark
                ? DsColors.surfaceContainerDark
                : DsColors.surfaceContainerLight,
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: [
                  _menuButton(
                    icon: Icons.add_box_outlined,
                    label: 'Insert',
                    children: [
                      for (final cat in {
                        for (final sn in snippetsFor(_lang)) sn.category,
                      })
                        SubmenuButton(
                          menuChildren: [
                            for (final sn in snippetsFor(
                              _lang,
                            ).where((x) => x.category == cat))
                              MenuItemButton(
                                onPressed: () => _insert(sn.insert),
                                trailingIcon: sn.trigger == null
                                    ? null
                                    : Text(
                                        sn.trigger!,
                                        style: const TextStyle(
                                          fontFamily: 'DS Mono',
                                          fontSize: 11,
                                        ),
                                      ),
                                child: Tooltip(
                                  message: sn.help,
                                  child: Text(sn.label),
                                ),
                              ),
                          ],
                          child: Text(cat),
                        ),
                    ],
                  ),
                  _menuButton(
                    icon: Icons.auto_awesome_mosaic_outlined,
                    label: 'Templates',
                    children: [
                      MenuItemButton(
                        leadingIcon: const Icon(
                          Icons.grid_view_rounded,
                          size: 18,
                        ),
                        onPressed: () => context.push(templateGalleryRoutePath),
                        child: const Text('Browse all templates…'),
                      ),
                      const Divider(height: 8),
                      for (final t in templatesFor(_lang))
                        MenuItemButton(
                          onPressed: () => _applyTemplate(t),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.name),
                              Text(
                                t.description,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  _menuButton(
                    icon: Icons.format_list_bulleted,
                    label: 'Outline',
                    children: [
                      for (final (level, title, offset) in _outline())
                        MenuItemButton(
                          onPressed: () => _jumpTo(offset),
                          child: Padding(
                            padding: EdgeInsets.only(left: 12.0 * (level - 1)),
                            child: Text(title.isEmpty ? '(untitled)' : title),
                          ),
                        ),
                      if (_outline().isEmpty)
                        const MenuItemButton(
                          onPressed: null,
                          child: Text('No headings yet'),
                        ),
                    ],
                  ),
                  if (_lang != ComposeLanguage.latex)
                    _menuButton(
                      icon: Icons.text_format,
                      label: 'Format',
                      children: [
                        MenuItemButton(
                          trailingIcon: _serif
                              ? null
                              : const Icon(Icons.check, size: 16),
                          onPressed: () {
                            setState(() => _serif = false);
                            unawaited(_compile());
                          },
                          child: const Text('Sans-serif text'),
                        ),
                        MenuItemButton(
                          trailingIcon: _serif
                              ? const Icon(Icons.check, size: 16)
                              : null,
                          onPressed: () {
                            setState(() => _serif = true);
                            unawaited(_compile());
                          },
                          child: const Text('Serif text'),
                        ),
                        const Divider(height: 8),
                        for (final fs in const [10.0, 11.0, 12.0, 14.0])
                          MenuItemButton(
                            trailingIcon: _fontSize == fs
                                ? const Icon(Icons.check, size: 16)
                                : null,
                            onPressed: () {
                              setState(() => _fontSize = fs);
                              unawaited(_compile());
                            },
                            child: Text('${fs.round()} pt text'),
                          ),
                        const Divider(height: 8),
                        for (final (label, m) in const [
                          ('Narrow margins', 36.0),
                          ('Normal margins', 56.0),
                          ('Wide margins', 80.0),
                        ])
                          MenuItemButton(
                            trailingIcon: _marginPt == m
                                ? const Icon(Icons.check, size: 16)
                                : null,
                            onPressed: () {
                              setState(() => _marginPt = m);
                              unawaited(_compile());
                            },
                            child: Text(label),
                          ),
                      ],
                    ),
                  IconButton(
                    tooltip: 'Find & replace (Ctrl+F)',
                    iconSize: 19,
                    visualDensity: VisualDensity.compact,
                    isSelected: _findOpen,
                    icon: const Icon(Icons.find_replace),
                    onPressed: () => setState(() => _findOpen = !_findOpen),
                  ),
                  const VerticalDivider(width: 12, indent: 8, endIndent: 8),
                  for (final (icon, tip, snippet) in _quick)
                    IconButton(
                      tooltip: tip,
                      iconSize: 19,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(icon),
                      onPressed: () => _insert(snippet),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (_findOpen) _findBar(theme),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final gutterW = 14.0 + '$lines'.length * 8;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Gutter(
                      text: _ctrl.text,
                      width: gutterW,
                      wrapWidth: box.maxWidth - gutterW - 20,
                      controller: _editorScroll,
                      dark: dark,
                    ),
                    Expanded(
                      child: Stack(
                        key: _editorStackKey,
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: _onEditorKey,
                              child: TextField(
                                key: _fieldKey,
                                controller: _ctrl,
                                focusNode: _focus,
                                scrollController: _editorScroll,
                                maxLines: null,
                                expands: true,
                                keyboardType: TextInputType.multiline,
                                textAlignVertical: TextAlignVertical.top,
                                autocorrect: false,
                                enableSuggestions: false,
                                smartQuotesType: SmartQuotesType.disabled,
                                smartDashesType: SmartDashesType.disabled,
                                style: TextStyle(
                                  fontFamily: 'DS Mono',
                                  fontSize: 13.5,
                                  height: _Gutter.lineHeight,
                                  color: dark
                                      ? const Color(0xFFE6EDF3)
                                      : const Color(0xFF1F2328),
                                ),
                                strutStyle: const StrutStyle(
                                  fontFamily: 'DS Mono',
                                  fontSize: 13.5,
                                  height: _Gutter.lineHeight,
                                  forceStrutHeight: true,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.fromLTRB(
                                    8,
                                    10,
                                    12,
                                    40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_suggestions.isNotEmpty && _caret != null)
                            _suggestionPopup(theme, box),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: dark
                ? DsColors.surfaceContainerDark
                : DsColors.surfaceContainerLight,
            child: Row(
              children: [
                Text(
                  'Ln $line, Col $col  ·  $lines lines',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                Text(_lang.label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPane(ThemeData theme) {
    final warnings = _doc?.warnings ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.brightness == Brightness.dark
              ? DsColors.surfaceContainerDark
              : DsColors.surfaceContainerLight,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _compiling ? null : () => unawaited(_compile()),
                  icon: _compiling
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Recompile'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Recompile as you type',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: _autoCompile,
                        onChanged: (v) => setState(() => _autoCompile = v),
                      ),
                      Text('Auto', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
                if (_lang != ComposeLanguage.latex) ...[
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _pageSize,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in const ['A4', 'Letter', 'A5', 'Legal'])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _pageSize = v);
                      unawaited(_compile());
                    },
                  ),
                ],
                const Spacer(),
                if (_pdf != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      '${_ms}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (_error != null)
          MaterialBanner(
            content: Text(
              _error!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            leading: const Icon(Icons.error_outline, color: Colors.red),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Hide'),
              ),
            ],
          )
        else if (warnings.isNotEmpty)
          Container(
            color: const Color(0xFFFFF8E1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              'Shown as plain text (not supported yet): ${warnings.take(8).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6D4C00),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: _pdf == null
              ? const Center(child: CircularProgressIndicator())
              : _PdfPagesPreview(bytes: _pdf!, revision: _pdfRevision),
        ),
      ],
    );
  }
}

/// Line numbers that scroll with the editor. A long line that wraps gets
/// one number and blank rows for its continuation, like Overleaf.
class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.text,
    required this.width,
    required this.wrapWidth,
    required this.controller,
    required this.dark,
  });

  static const lineHeight = 1.5;
  static const _fontSize = 13.5;
  final String text;
  final double width;
  final double wrapWidth;
  final ScrollController controller;
  final bool dark;

  static String? _cacheKey;
  static String _cacheValue = '';

  /// "1\n2\n\n3…": wrapped rows left blank.
  String _numbers() {
    final key = '${text.hashCode}|${text.length}|${wrapWidth.round()}';
    if (key == _cacheKey) return _cacheValue;
    final out = StringBuffer();
    final tp = TextPainter(textDirection: TextDirection.ltr);
    const style = TextStyle(fontFamily: 'DS Mono', fontSize: _fontSize);
    // Monospace: width per character from one sample.
    tp.text = const TextSpan(text: 'MMMMMMMMMM', style: style);
    tp.layout();
    final charW = tp.width / 10;
    final perRow = charW <= 0
        ? 1 << 20
        : (wrapWidth / charW).floor().clamp(1, 1 << 20);
    var n = 1;
    for (final line in text.split('\n')) {
      out.write(n++);
      var rows = 1;
      if (line.length > perRow * 0.7) {
        // Real word wrapping (the editor breaks at spaces).
        tp.text = TextSpan(text: line, style: style);
        tp.layout(maxWidth: wrapWidth);
        rows = tp.computeLineMetrics().length.clamp(1, 1 << 20);
      }
      for (var i = 1; i < rows; i++) {
        out.write('\n');
      }
      out.write('\n');
    }
    _cacheKey = key;
    return _cacheValue = out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'DS Mono',
      fontSize: 12,
      color: dark ? const Color(0xFF6E7681) : const Color(0xFF8C959F),
    );
    final numbers = _numbers();
    return Container(
      width: width,
      color: dark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final offset = controller.hasClients ? controller.offset : 0.0;
          return ClipRect(
            child: Transform.translate(
              offset: Offset(0, 10 - offset),
              child: OverflowBox(
                alignment: Alignment.topRight,
                maxHeight: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    numbers,
                    textAlign: TextAlign.right,
                    style: style,
                    strutStyle: const StrutStyle(
                      fontFamily: 'DS Mono',
                      fontSize: _fontSize,
                      height: lineHeight,
                      forceStrutHeight: true,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The compiled PDF as page images. Previous pages stay visible while the
/// new revision rasters page-by-page so the top of the doc updates quickly.
class _PdfPagesPreview extends StatefulWidget {
  const _PdfPagesPreview({required this.bytes, required this.revision});

  final Uint8List bytes;
  final int revision;

  @override
  State<_PdfPagesPreview> createState() => _PdfPagesPreviewState();
}

class _PdfPagesPreviewState extends State<_PdfPagesPreview> {
  List<ui.Image> _pages = const [];
  double _zoom = 1;
  int _renderedFor = -1;
  double _width = 0;

  /// Bumped on every render start so in-flight work can cancel itself.
  int _renderSeq = 0;

  @override
  void didUpdateWidget(covariant _PdfPagesPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _scheduleRender();
  }

  @override
  void dispose() {
    _renderSeq++;
    for (final i in _pages) {
      i.dispose();
    }
    super.dispose();
  }

  void _scheduleRender() {
    if (_width <= 0) return;
    unawaited(_render(widget.revision, _width));
  }

  bool _renderStillCurrent(int seq, int revision) =>
      mounted && seq == _renderSeq && revision == widget.revision;

  Future<void> _render(int revision, double width) async {
    final seq = ++_renderSeq;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(
        widget.bytes,
        sourceName: 'compose-$revision',
      );
      if (!_renderStillCurrent(seq, revision)) return;

      final pageCount = doc.pages.length.clamp(0, 60);
      for (var i = 0; i < pageCount; i++) {
        final page = doc.pages[i];
        // Supersampled so text stays crisp when the image is scaled down.
        final w = (width * _zoom * (dpr < 2 ? 2.0 : dpr) * 1.25).clamp(
          400.0,
          5000.0,
        );
        final h = w * page.height / page.width;
        final img = await page.render(
          fullWidth: w,
          fullHeight: h,
          backgroundColor: 0xffffffff,
        );
        if (img == null) continue;
        final uiImage = await img.createImage();
        img.dispose();
        if (!_renderStillCurrent(seq, revision)) {
          uiImage.dispose();
          return;
        }
        ui.Image? toDispose;
        setState(() {
          final next = List<ui.Image>.of(_pages);
          if (i < next.length) {
            toDispose = next[i];
            next[i] = uiImage;
          } else {
            next.add(uiImage);
          }
          _pages = next;
          _renderedFor = revision;
        });
        toDispose?.dispose();
      }
      if (!_renderStillCurrent(seq, revision)) return;
      if (_pages.length > pageCount) {
        final excess = _pages.sublist(pageCount);
        setState(() => _pages = _pages.sublist(0, pageCount));
        for (final img in excess) {
          img.dispose();
        }
      }
    } catch (_) {
    } finally {
      await doc?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 32).clamp(160.0, 1400.0);
        if ((w - _width).abs() > 40 ||
            _renderedFor != widget.revision && _width == 0) {
          _width = w;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scheduleRender();
          });
        }
        return Stack(
          children: [
            Container(
              color: const Color(0xFF525659),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _pages.length,
                itemBuilder: (context, i) {
                  final img = _pages[i];
                  final dw = w * _zoom;
                  return Center(
                    child: Container(
                      width: dw,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: RawImage(
                        image: img,
                        width: dw,
                        height: dw * img.height / img.width,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Zoom out',
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: _zoom <= 0.5
                          ? null
                          : () {
                              setState(
                                () => _zoom = (_zoom - 0.25).clamp(0.5, 3),
                              );
                              _scheduleRender();
                            },
                    ),
                    Text('${(_zoom * 100).round()}%'),
                    IconButton(
                      tooltip: 'Zoom in',
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _zoom >= 3
                          ? null
                          : () {
                              setState(
                                () => _zoom = (_zoom + 0.25).clamp(0.5, 3),
                              );
                              _scheduleRender();
                            },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('${_pages.length} p.'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Searchable reference of every snippet: syntax, help, click to insert.
class _SnippetPanel extends StatefulWidget {
  const _SnippetPanel({
    required this.language,
    required this.onInsert,
    required this.onClose,
  });

  final ComposeLanguage language;
  final ValueChanged<ComposeSnippet> onInsert;
  final VoidCallback onClose;

  @override
  State<_SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends State<_SnippetPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = snippetsFor(widget.language);
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? all
        : all
              .where(
                (s) =>
                    s.label.toLowerCase().contains(q) ||
                    s.help.toLowerCase().contains(q) ||
                    (s.trigger ?? '').toLowerCase().contains(q) ||
                    s.insert.toLowerCase().contains(q),
              )
              .toList();
    final byCat = <String, List<ComposeSnippet>>{};
    for (final s in list) {
      (byCat[s.category] ??= []).add(s);
    }
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.language.label} reference',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search commands, tags, symbols…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Text(
              'Click to insert at the cursor. Selected text is wrapped. '
              'While typing, matching commands appear under the editor.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final e in byCat.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Text(
                      e.key.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: DsColors.primary,
                      ),
                    ),
                  ),
                  for (final s in e.value)
                    InkWell(
                      onTap: () => widget.onInsert(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.preview,
                                style: const TextStyle(
                                  fontFamily: 'DS Mono',
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(s.help, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
