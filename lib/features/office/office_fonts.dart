import 'package:document_studio/core/fonts/font_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Office font names → bundled families loaded for display. Word and
/// PowerPoint files name Calibri, Arial, Times New Roman…; we draw them with
/// the metric-compatible twins from the font library (Carlito, Arimo,
/// Tinos…) so line breaks match the original.
class OfficeFonts extends ChangeNotifier {
  OfficeFonts._();

  static final OfficeFonts instance = OfficeFonts._();

  final Map<String, String?> _family = {};
  final Set<String> _loading = {};

  /// Common Office fonts, shown first in font lists.
  static const officeNames = [
    'Calibri',
    'Calibri Light',
    'Cambria',
    'Aptos',
    'Arial',
    'Arial Narrow',
    'Times New Roman',
    'Georgia',
    'Garamond',
    'Book Antiqua',
    'Century Gothic',
    'Franklin Gothic',
    'Segoe UI',
    'Verdana',
    'Tahoma',
    'Trebuchet MS',
    'Courier New',
    'Consolas',
    'Impact',
  ];

  /// Every font the lists offer: Office names, then the bundled library.
  List<String> get allNames {
    final lib = FontLibrary.instance.library.map((f) => f.family);
    return [...officeNames, ...lib.where((f) => !officeNames.contains(f))];
  }

  /// Flutter font family drawing [name], or null while it loads (listeners
  /// are told when it is ready) or when nothing fits.
  String? familyFor(String name) {
    if (_family.containsKey(name)) return _family[name];
    if (_loading.add(name)) _load(name);
    return null;
  }

  /// Loads every font in [names] (the document's fonts) up front.
  void preload(Iterable<String> names) {
    for (final n in names) {
      familyFor(n);
    }
  }

  /// Waits until every font in [names] is loaded (before exporting).
  Future<void> ensure(Iterable<String> names) async {
    for (final n in names) {
      familyFor(n);
      final f = _pending[n];
      if (f != null) await f;
    }
  }

  final Map<String, Future<void>> _pending = {};

  Future<void> _load(String name) => _pending[name] = _loadNow(name);

  Future<void> _loadNow(String name) async {
    final lib = FontLibrary.instance;
    await lib.ensureLoaded();
    final key = name == 'Aptos'
        ? 'Inter'
        : name == 'Calibri Light'
        ? 'Calibri'
        : name;
    LibraryFamily? fam;
    for (final f in lib.library) {
      if (f.family == key) fam = f;
    }
    if (fam == null) {
      final alias = lib.libraryFamilyFor(key);
      for (final f in lib.library) {
        if (f.family == alias) fam = f;
      }
    }
    if (fam == null) {
      _family[name] = null;
      return;
    }
    final flutterFamily = 'dsoffice_${fam.family.replaceAll(' ', '_')}';
    try {
      final loader = FontLoader(flutterFamily);
      for (final (file, _, _) in fam.files) {
        loader.addFont(rootBundle.load('assets/fonts/library/$file'));
      }
      await loader.load();
      _family[name] = flutterFamily;
    } catch (_) {
      _family[name] = null;
    }
    notifyListeners();
  }
}
