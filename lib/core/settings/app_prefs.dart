import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Small app-wide preferences read once at start-up (before the first frame)
/// so any code can use them synchronously. Settings writes go through
/// [AppPrefs.set*], which updates the value in memory and on disk.
abstract final class AppPrefs {
  static SharedPreferences? _p;

  static const _kUndo = 'undo_levels_v1';
  static const _kAuthor = 'comment_author_v1';
  static const _kEmbed = 'embed_fonts_default_v1';
  static const _kSplash = 'show_splash_v1';
  static const _kAutoOcr = 'auto_ocr_v1';
  static const _kRecentCount = 'recent_count_v1';
  static const _kAutoUpdate = 'auto_update_check_v1';

  /// Look for a newer GitHub release at start-up.
  static bool autoUpdateCheck = true;

  /// Undo steps kept per document (each large step lives on disk).
  static int undoLevels = 10;

  /// Name stored on new comments; empty = the computer's user name.
  static String commentAuthor = '';

  /// Edit: embed the font of new / edited text by default.
  static bool embedFontsByDefault = false;

  /// Logo animation when the app starts.
  static bool showSplash = true;

  /// OCR scanned pages in the background after opening.
  static bool autoOcr = false;

  /// How many recent files Home lists.
  static int recentCount = 12;

  static Future<void> load() async {
    try {
      final p = _p = await SharedPreferences.getInstance();
      undoLevels = p.getInt(_kUndo) ?? undoLevels;
      commentAuthor = p.getString(_kAuthor) ?? commentAuthor;
      embedFontsByDefault = p.getBool(_kEmbed) ?? embedFontsByDefault;
      showSplash = p.getBool(_kSplash) ?? showSplash;
      autoOcr = p.getBool(_kAutoOcr) ?? autoOcr;
      recentCount = p.getInt(_kRecentCount) ?? recentCount;
      autoUpdateCheck = p.getBool(_kAutoUpdate) ?? autoUpdateCheck;
    } catch (_) {
      // Defaults stay in place.
    }
  }

  /// Author for new comments.
  static String get effectiveAuthor => commentAuthor.trim().isNotEmpty
      ? commentAuthor.trim()
      : (Platform.environment['USER'] ??
          Platform.environment['USERNAME'] ??
          '');

  static Future<SharedPreferences> _prefs() async =>
      _p ??= await SharedPreferences.getInstance();

  static Future<void> setUndoLevels(int v) async {
    undoLevels = v.clamp(1, 100);
    await (await _prefs()).setInt(_kUndo, undoLevels);
  }

  static Future<void> setCommentAuthor(String v) async {
    commentAuthor = v.trim();
    await (await _prefs()).setString(_kAuthor, commentAuthor);
  }

  static Future<void> setEmbedFontsByDefault(bool v) async {
    embedFontsByDefault = v;
    await (await _prefs()).setBool(_kEmbed, v);
  }

  static Future<void> setShowSplash(bool v) async {
    showSplash = v;
    await (await _prefs()).setBool(_kSplash, v);
  }

  static Future<void> setAutoOcr(bool v) async {
    autoOcr = v;
    await (await _prefs()).setBool(_kAutoOcr, v);
  }

  static Future<void> setRecentCount(int v) async {
    recentCount = v.clamp(4, 50);
    await (await _prefs()).setInt(_kRecentCount, recentCount);
  }

  static Future<void> setAutoUpdateCheck(bool v) async {
    autoUpdateCheck = v;
    await (await _prefs()).setBool(_kAutoUpdate, v);
  }
}
