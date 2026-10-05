import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
}) async {
  final doc = switch (language) {
    ComposeLanguage.markdown => markdownToCompose(source, pageSize: pageSize),
    ComposeLanguage.html => htmlToCompose(source, pageSize: pageSize),
    ComposeLanguage.latex => latexToCompose(source),
  };
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
  const ComposeScreen({super.key, this.language = ComposeLanguage.markdown});

  final ComposeLanguage language;

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
  ComposeDoc? _doc;
  String? _error;
  int _ms = 0;

  // Autocomplete.
  List<ComposeSnippet> _suggestions = const [];
  int _prefixLength = 0;

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
    super.dispose();
  }

  String get _draftKey => 'compose_draft_${_lang.extension}';

  Future<void> _restoreDraft() async {
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

  void _onChanged() {
    _updateSuggestions();
    _dirtyAfterCompile = true;
    if (_autoCompile) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 650),
        () => unawaited(_compile()),
      );
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
      );
      if (!mounted) return;
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
          const Duration(milliseconds: 300),
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
                      child: TextField(
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
                          contentPadding: EdgeInsets.fromLTRB(8, 10, 12, 40),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_suggestions.isNotEmpty)
            Material(
              elevation: 2,
              color: theme.colorScheme.surfaceContainerHigh,
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  children: [
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Tooltip(
                          message: '${s.help}\n\n${s.preview}',
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              s.trigger ?? s.label,
                              style: const TextStyle(
                                fontFamily: 'DS Mono',
                                fontSize: 12.5,
                              ),
                            ),
                            avatar: const Icon(Icons.keyboard_tab, size: 14),
                            onPressed: () => _acceptSuggestion(s),
                          ),
                        ),
                      ),
                  ],
                ),
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

/// The compiled PDF as page images (rendered on this device, swapped in
/// only when ready, so the preview never flashes empty while you type).
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

  @override
  void didUpdateWidget(covariant _PdfPagesPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _scheduleRender();
  }

  @override
  void dispose() {
    for (final i in _pages) {
      i.dispose();
    }
    super.dispose();
  }

  void _scheduleRender() {
    if (_width <= 0) return;
    unawaited(_render(widget.revision, _width));
  }

  Future<void> _render(int revision, double width) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(
        widget.bytes,
        sourceName: 'compose-$revision',
      );
      final images = <ui.Image>[];
      for (final page in doc.pages.take(60)) {
        final w = (width * _zoom * dpr).clamp(200.0, 4000.0);
        final h = w * page.height / page.width;
        final img = await page.render(
          fullWidth: w,
          fullHeight: h,
          backgroundColor: 0xffffffff,
        );
        if (img == null) continue;
        images.add(await img.createImage());
        img.dispose();
        if (revision != widget.revision) break;
      }
      if (!mounted || revision != widget.revision) {
        for (final i in images) {
          i.dispose();
        }
        return;
      }
      final old = _pages;
      setState(() {
        _pages = images;
        _renderedFor = revision;
      });
      for (final i in old) {
        i.dispose();
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
                        filterQuality: FilterQuality.medium,
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
