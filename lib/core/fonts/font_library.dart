import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// A font the user added (TrueType). Usable for new text and embedded in the
/// PDF so it looks the same everywhere.
class InstalledFont {
  InstalledFont({
    required this.id,
    required this.path,
    required this.ttf,
    required this.flutterFamily,
  });

  final String id;
  final String path;
  final TtfFont ttf;

  /// Family name registered with Flutter for the on-screen preview.
  final String flutterFamily;

  /// Family as shown to the user ([libraryFamily] for bundled fonts).
  String get familyName => libraryFamily ?? ttf.family;

  /// Set for fonts from the bundled library (not removable).
  String? libraryFamily;

  String get label {
    final style = [if (ttf.bold) 'Bold', if (ttf.italic) 'Italic'].join(' ');
    return style.isEmpty ? familyName : '$familyName $style';
  }
}

/// One family of the bundled font library (assets/fonts/library).
class LibraryFamily {
  const LibraryFamily(this.family, this.category, this.files);

  final String family;

  /// `sans-serif`, `serif`, `monospace`, `display`, `handwriting`.
  final String category;

  /// (asset file, bold, italic).
  final List<(String, bool, bool)> files;

  String fileFor({required bool bold, required bool italic}) {
    (String, bool, bool)? best;
    var bestScore = -1;
    for (final f in files) {
      final score = (f.$2 == bold ? 2 : 0) + (f.$3 == italic ? 1 : 0);
      if (score > bestScore) {
        best = f;
        bestScore = score;
      }
    }
    return best!.$1;
  }
}

/// The user's installed fonts (app support/fonts/*.ttf), plus the bundled
/// metric-compatible Liberation fonts used to embed the standard families.
class FontLibrary extends ChangeNotifier {
  FontLibrary._();

  static final FontLibrary instance = FontLibrary._();

  final List<InstalledFont> _fonts = [];
  final Set<String> _registered = {};
  bool _loaded = false;

  List<InstalledFont> get fonts => List.unmodifiable(_fonts);

  Directory? get _dir {
    final root = StoragePaths.maybeInstance?.root.path;
    return root == null ? null : Directory(p.join(root, 'fonts'));
  }

  final List<LibraryFamily> _library = [];
  final Map<String, InstalledFont> _libLoaded = {};

  /// The bundled font library (76 families), loaded with [ensureLoaded].
  List<LibraryFamily> get library => List.unmodifiable(_library);

  Future<void> _loadLibraryIndex() async {
    try {
      final raw = await rootBundle.loadString('assets/fonts/library/index.json');
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list.cast<Map<String, dynamic>>()) {
        _library.add(
          LibraryFamily(
            e['family'] as String,
            (e['category'] as String?) ?? '',
            [
              for (final f in (e['files'] as List<dynamic>)
                  .cast<Map<String, dynamic>>())
                (f['file'] as String, f['bold'] == true, f['italic'] == true),
            ],
          ),
        );
      }
    } catch (_) {
      // No library in this build: user fonts and Liberation still work.
    }
  }

  /// Loads (once) the bundled [family] in the closest style.
  Future<InstalledFont?> loadLibraryFont(
    String family, {
    bool bold = false,
    bool italic = false,
  }) async {
    await ensureLoaded();
    LibraryFamily? fam;
    for (final f in _library) {
      if (f.family == family) fam = f;
    }
    if (fam == null) return null;
    final file = fam.fileFor(bold: bold, italic: italic);
    final cached = _libLoaded[file];
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load('assets/fonts/library/$file');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final ttf = TtfFont.parse(Uint8List.fromList(bytes));
      if (ttf == null) return null;
      final flutterFamily = 'dslib_${file.hashCode.toUnsigned(32)}';
      if (_registered.add(flutterFamily)) {
        final loader = FontLoader(flutterFamily)..addFont(Future.value(data));
        await loader.load();
      }
      final font = InstalledFont(
        id: 'lib:$file',
        path: 'assets/fonts/library/$file',
        ttf: ttf,
        flutterFamily: flutterFamily,
      )..libraryFamily = fam.family;
      _libLoaded[file] = font;
      return font;
    } catch (_) {
      return null;
    }
  }

  /// Font identification: the bundled family that best stands in for a PDF
  /// font name — the same family when we ship it (`ABCDEF+Montserrat-Bold`),
  /// otherwise its metric-compatible twin (Calibri → Carlito, Cambria →
  /// Caladea, Georgia → Gelasio, Arial → Arimo, Times → Tinos, Courier →
  /// Cousine) or a close look-alike.
  String? libraryFamilyFor(String baseFont) {
    var name = baseFont.contains('+')
        ? baseFont.substring(baseFont.indexOf('+') + 1)
        : baseFont;
    final n = _norm(name);
    if (n.isEmpty) return null;
    String? best;
    for (final f in _library) {
      final fam = _norm(f.family);
      if (fam.length >= 3 &&
          n.startsWith(fam) &&
          (best == null || fam.length > _norm(best).length)) {
        best = f.family;
      }
    }
    if (best != null) return best;
    for (final (key, fam) in _aliases) {
      if (n.startsWith(key) && _library.any((f) => f.family == fam)) return fam;
    }
    return null;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static const _aliases = <(String, String)>[
    ('calibri', 'Carlito'),
    ('cambria', 'Caladea'),
    ('georgia', 'Gelasio'),
    ('arialnarrow', 'Roboto Condensed'),
    ('arial', 'Arimo'),
    ('helvetica', 'Arimo'),
    ('timesnewroman', 'Tinos'),
    ('times', 'Tinos'),
    ('couriernew', 'Cousine'),
    ('courier', 'Cousine'),
    ('segoeui', 'Open Sans'),
    ('verdana', 'Noto Sans'),
    ('tahoma', 'Noto Sans'),
    ('trebuchet', 'Fira Sans'),
    ('candara', 'Cabin'),
    ('corbel', 'Source Sans 3'),
    ('gillsans', 'Cabin'),
    ('futura', 'Josefin Sans'),
    ('centurygothic', 'Quicksand'),
    ('franklingothic', 'Libre Franklin'),
    ('garamond', 'EB Garamond'),
    ('baskerville', 'Libre Baskerville'),
    ('bookantiqua', 'PT Serif'),
    ('palatino', 'PT Serif'),
    ('bookman', 'Domine'),
    ('constantia', 'Merriweather'),
    ('minion', 'Crimson Text'),
    ('myriad', 'Source Sans 3'),
    ('consolas', 'Inconsolata'),
    ('menlo', 'JetBrains Mono'),
    ('monaco', 'JetBrains Mono'),
    ('lucidaconsole', 'Source Code Pro'),
    ('sfpro', 'Inter'),
    ('sanfrancisco', 'Inter'),
    ('impact', 'Anton'),
    ('cmr', 'Old Standard TT'),
    ('lmroman', 'Old Standard TT'),
  ];

  /// Identifies and loads the font for a PDF font name: the user's own font
  /// of that family first, then the bundled library. Null when nothing fits.
  Future<InstalledFont?> resolveOriginal(String baseFont) async {
    await ensureLoaded();
    final own = _matchUser(baseFont);
    if (own != null) return own;
    final fam = libraryFamilyFor(baseFont);
    if (fam == null) return null;
    final n = baseFont.toLowerCase();
    return loadLibraryFont(
      fam,
      bold: RegExp(r'bold|black|heavy|semibold|demi').hasMatch(n),
      italic: RegExp(r'italic|oblique').hasMatch(n),
    );
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await _loadLibraryIndex();
    final dir = _dir;
    if (dir == null || !dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (f.path.toLowerCase().endsWith('.ttf')) await _register(f);
    }
    notifyListeners();
  }

  Future<InstalledFont?> _register(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ttf = TtfFont.parse(bytes);
      if (ttf == null) return null;
      final id = p.basename(file.path);
      if (_fonts.any((f) => f.id == id)) return null;
      final family = 'dsuser_${id.hashCode.toUnsigned(32)}';
      if (_registered.add(family)) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      final font = InstalledFont(
        id: id,
        path: file.path,
        ttf: ttf,
        flutterFamily: family,
      );
      _fonts.add(font);
      return font;
    } catch (_) {
      return null;
    }
  }

  /// Copies [source] into the library. Null when it is not a usable
  /// TrueType font (OpenType/CFF and collections are not supported).
  Future<InstalledFont?> install(String source) async {
    final dir = _dir;
    if (dir == null) return null;
    final bytes = await File(source).readAsBytes();
    if (TtfFont.parse(bytes) == null) return null;
    await dir.create(recursive: true);
    final dest = File(p.join(dir.path, p.basename(source)));
    await dest.writeAsBytes(bytes, flush: true);
    final font = await _register(dest);
    notifyListeners();
    return font;
  }

  Future<void> remove(InstalledFont font) async {
    _fonts.removeWhere((f) => f.id == font.id);
    try {
      await File(font.path).delete();
    } catch (_) {}
    notifyListeners();
  }

  /// Installed font whose family matches the original PDF font name
  /// (e.g. `ABCDEF+Calibri-Bold` → an installed Calibri Bold).
  InstalledFont? matchOriginal(String baseFont) {
    final own = _matchUser(baseFont);
    if (own != null) return own;
    // Library fonts already identified and loaded (see [resolveOriginal]).
    final fam = libraryFamilyFor(baseFont);
    if (fam == null) return null;
    final n = baseFont.toLowerCase();
    final wantBold = RegExp(r'bold|black|heavy|semibold|demi').hasMatch(n);
    final wantItalic = RegExp(r'italic|oblique').hasMatch(n);
    InstalledFont? best;
    for (final f in _libLoaded.values) {
      if (f.libraryFamily != fam) continue;
      if (best == null ||
          (f.ttf.bold == wantBold && f.ttf.italic == wantItalic)) {
        best = f;
      }
    }
    return best;
  }

  InstalledFont? _matchUser(String baseFont) {
    final n = baseFont.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    InstalledFont? best;
    for (final f in _fonts) {
      final fam = f.ttf.family.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (fam.isEmpty || !n.contains(fam)) continue;
      final wantBold = RegExp(r'bold|black|heavy|semibold').hasMatch(n);
      final wantItalic = RegExp(r'italic|oblique').hasMatch(n);
      if (best == null ||
          (f.ttf.bold == wantBold && f.ttf.italic == wantItalic)) {
        best = f;
      }
    }
    return best;
  }

  static final Map<String, TtfFont> _bundled = {};

  /// Bundled Liberation font equivalent to a standard family, so text can be
  /// embedded without the user supplying a font.
  Future<TtfFont?> bundledFor({
    required String family, // sans | serif | mono
    required bool bold,
    required bool italic,
  }) async {
    final base = switch (family) {
      'serif' => 'LiberationSerif',
      'mono' => 'LiberationMono',
      _ => 'LiberationSans',
    };
    final style = switch ((bold, italic)) {
      (true, true) => 'BoldItalic',
      (true, false) => 'Bold',
      (false, true) => 'Italic',
      _ => 'Regular',
    };
    final key = '$base-$style';
    final cached = _bundled[key];
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load('assets/fonts/text/$key.ttf');
      final ttf = TtfFont.parse(data.buffer.asUint8List());
      if (ttf != null) _bundled[key] = ttf;
      return ttf;
    } catch (_) {
      return null;
    }
  }

  /// Bytes for a stored font (for tests / export).
  Future<Uint8List?> bytesOf(InstalledFont f) async {
    try {
      return await File(f.path).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
