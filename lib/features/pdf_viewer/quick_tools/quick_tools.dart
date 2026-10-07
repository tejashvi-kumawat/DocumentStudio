import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One tool that can sit on the floating Quick Tools bar: a comment tool
/// ([markup]) or any viewer tool ([viewer]).
class QuickToolDef {
  const QuickToolDef.markup(this.id, this.section, MarkupTool this.markup)
    : viewer = null,
      label = null,
      icon = null;

  const QuickToolDef.viewer(
    this.id,
    this.section,
    ViewerToolId this.viewer, {
    required String this.label,
    required IconData this.icon,
  }) : markup = null;

  /// Stable key saved in the user's layout.
  final String id;

  /// Heading in the "More tools" panel.
  final String section;
  final MarkupTool? markup;
  final ViewerToolId? viewer;
  final String? label;
  final IconData? icon;

  String get title => markup?.label ?? label!;
}

const kQuickSections = [
  'Comment',
  'Mark up text',
  'Draw & shapes',
  'Edit & fill',
  'Pages',
  'Protect & export',
];

/// Everything that can be pinned (Acrobat's "Customize quick tools").
const kQuickTools = <QuickToolDef>[
  QuickToolDef.markup('select', 'Comment', MarkupTool.select),
  QuickToolDef.markup('note', 'Comment', MarkupTool.note),
  QuickToolDef.markup('text', 'Comment', MarkupTool.text),
  QuickToolDef.markup('callout', 'Comment', MarkupTool.callout),
  QuickToolDef.markup('link', 'Comment', MarkupTool.link),
  QuickToolDef.markup('image', 'Comment', MarkupTool.image),
  QuickToolDef.markup('highlight', 'Mark up text', MarkupTool.highlight),
  QuickToolDef.markup('underline', 'Mark up text', MarkupTool.underline),
  QuickToolDef.markup('strikeout', 'Mark up text', MarkupTool.strikeout),
  QuickToolDef.markup('squiggly', 'Mark up text', MarkupTool.squiggly),
  QuickToolDef.markup('pen', 'Draw & shapes', MarkupTool.pen),
  QuickToolDef.markup('highlighter', 'Draw & shapes', MarkupTool.highlighter),
  QuickToolDef.markup('eraser', 'Draw & shapes', MarkupTool.eraser),
  QuickToolDef.markup('line', 'Draw & shapes', MarkupTool.line),
  QuickToolDef.markup('arrow', 'Draw & shapes', MarkupTool.arrow),
  QuickToolDef.markup('rectangle', 'Draw & shapes', MarkupTool.rectangle),
  QuickToolDef.markup('ellipse', 'Draw & shapes', MarkupTool.ellipse),
  QuickToolDef.markup('polygon', 'Draw & shapes', MarkupTool.polygon),
  QuickToolDef.markup('cloud', 'Draw & shapes', MarkupTool.cloud),
  QuickToolDef.viewer(
    'editText',
    'Edit & fill',
    ViewerToolId.editText,
    label: 'Edit PDF',
    icon: Icons.edit_note,
  ),
  QuickToolDef.viewer(
    'fillForm',
    'Edit & fill',
    ViewerToolId.fillForm,
    label: 'Fill form',
    icon: Icons.assignment_outlined,
  ),
  QuickToolDef.viewer(
    'visualSign',
    'Edit & fill',
    ViewerToolId.visualSign,
    label: 'Sign',
    icon: Icons.draw_outlined,
  ),
  QuickToolDef.viewer(
    'redact',
    'Edit & fill',
    ViewerToolId.redact,
    label: 'Redact',
    icon: Icons.hide_source,
  ),
  QuickToolDef.viewer(
    'searchablePdf',
    'Edit & fill',
    ViewerToolId.searchablePdf,
    label: 'Recognize text (OCR)',
    icon: Icons.document_scanner_outlined,
  ),
  QuickToolDef.viewer(
    'crop',
    'Pages',
    ViewerToolId.crop,
    label: 'Crop pages',
    icon: Icons.crop,
  ),
  QuickToolDef.viewer(
    'rotate',
    'Pages',
    ViewerToolId.rotate,
    label: 'Rotate pages',
    icon: Icons.rotate_right,
  ),
  QuickToolDef.viewer(
    'extract',
    'Pages',
    ViewerToolId.extract,
    label: 'Extract pages',
    icon: Icons.output,
  ),
  QuickToolDef.viewer(
    'deletePages',
    'Pages',
    ViewerToolId.deletePages,
    label: 'Delete pages',
    icon: Icons.delete_outline,
  ),
  QuickToolDef.viewer(
    'insertBlank',
    'Pages',
    ViewerToolId.insertBlank,
    label: 'Add blank page',
    icon: Icons.note_add_outlined,
  ),
  QuickToolDef.viewer(
    'split',
    'Pages',
    ViewerToolId.split,
    label: 'Split',
    icon: Icons.call_split,
  ),
  QuickToolDef.viewer(
    'watermark',
    'Pages',
    ViewerToolId.watermark,
    label: 'Watermark',
    icon: Icons.branding_watermark_outlined,
  ),
  QuickToolDef.viewer(
    'headersFooters',
    'Pages',
    ViewerToolId.headersFooters,
    label: 'Header & footer',
    icon: Icons.view_agenda_outlined,
  ),
  QuickToolDef.viewer(
    'pageNumbers',
    'Pages',
    ViewerToolId.pageNumbers,
    label: 'Page numbers',
    icon: Icons.pin_outlined,
  ),
  QuickToolDef.viewer(
    'protect',
    'Protect & export',
    ViewerToolId.protect,
    label: 'Protect with password',
    icon: Icons.lock_outline,
  ),
  QuickToolDef.viewer(
    'compress',
    'Protect & export',
    ViewerToolId.compress,
    label: 'Compress',
    icon: Icons.compress,
  ),
  QuickToolDef.viewer(
    'metadata',
    'Protect & export',
    ViewerToolId.metadata,
    label: 'Properties',
    icon: Icons.info_outline,
  ),
  QuickToolDef.viewer(
    'exportImages',
    'Protect & export',
    ViewerToolId.exportImages,
    label: 'Export to images',
    icon: Icons.image_outlined,
  ),
  QuickToolDef.viewer(
    'officeConvert',
    'Protect & export',
    ViewerToolId.officeConvert,
    label: 'Convert to Office',
    icon: Icons.swap_horiz,
  ),
  QuickToolDef.viewer(
    'compare',
    'Protect & export',
    ViewerToolId.compare,
    label: 'Compare files',
    icon: Icons.compare,
  ),
];

QuickToolDef? quickToolById(String id) {
  for (final t in kQuickTools) {
    if (t.id == id) return t;
  }
  return null;
}

/// The user's quick tools: which are pinned to the bar, in what order.
/// Saved on this device; the bar follows changes at once.
class QuickToolsConfig extends ChangeNotifier {
  QuickToolsConfig._();

  static final QuickToolsConfig instance = QuickToolsConfig._();

  static const defaults = [
    'select',
    'note',
    'highlight',
    'pen',
    'text',
    'editText',
  ];
  static const _key = 'quick_tools_v1';

  List<String> _pinned = List.of(defaults);
  String? _recent;
  bool _loaded = false;

  List<String> get pinned => List.unmodifiable(_pinned);

  /// The last tool used from "More tools" that is not pinned: it stays on
  /// the bar until another one replaces it.
  String? get recent =>
      _recent == null || _pinned.contains(_recent) ? null : _recent;

  bool isPinned(String id) => _pinned.contains(id);

  /// Reads the saved layout once.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(_key);
      if (saved != null) {
        _pinned = [
          for (final id in saved)
            if (quickToolById(id) != null) id,
        ];
        notifyListeners();
      }
    } catch (_) {
      // Defaults stay.
    }
  }

  void pin(String id, {int? at}) {
    if (_pinned.contains(id) || quickToolById(id) == null) return;
    _pinned.insert(
      at == null ? _pinned.length : at.clamp(0, _pinned.length),
      id,
    );
    _changed();
  }

  void unpin(String id) {
    if (_pinned.remove(id)) _changed();
  }

  void toggle(String id) => isPinned(id) ? unpin(id) : pin(id);

  void move(int from, int to) {
    if (from < 0 || from >= _pinned.length) return;
    final id = _pinned.removeAt(from);
    _pinned.insert(to.clamp(0, _pinned.length), id);
    _changed();
  }

  void reset() {
    _pinned = List.of(defaults);
    _recent = null;
    _changed();
  }

  void used(String id) {
    if (_pinned.contains(id) || _recent == id) return;
    _recent = id;
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_key, _pinned))
        .catchError((_) => false);
  }
}
