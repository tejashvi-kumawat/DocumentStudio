import 'dart:async';
import 'dart:io';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Opens Document Studio's own file browser (no system dialog) and returns
/// the chosen paths, or null when cancelled.
Future<List<String>?> showDsFileBrowser(
  BuildContext context, {
  List<String>? extensions,
  bool multiple = false,
  String title = 'Open',
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _DsFileBrowser(
      extensions: extensions
          ?.map((e) => e.toLowerCase().replaceFirst('.', ''))
          .toSet(),
      multiple: multiple,
      title: title,
    ),
  );
}

class _Place {
  const _Place(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

class _Entry {
  _Entry(this.path, this.isDir, this.size, this.modified);
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  String get name => p.basename(path);
}

enum _Sort { name, modified, size }

class _DsFileBrowser extends StatefulWidget {
  const _DsFileBrowser({
    required this.extensions,
    required this.multiple,
    required this.title,
  });

  final Set<String>? extensions;
  final bool multiple;
  final String title;

  @override
  State<_DsFileBrowser> createState() => _DsFileBrowserState();
}

class _DsFileBrowserState extends State<_DsFileBrowser> {
  static const _lastDirKey = 'ds_file_browser_last_dir';
  static const _recentKey = 'ds_file_browser_recent_dirs';

  String _dir = '';
  List<_Entry> _entries = const [];
  String? _error;
  bool _loading = true;
  bool _showHidden = false;
  _Sort _sort = _Sort.name;
  bool _ascending = true;
  String _filter = '';
  final Set<String> _selected = {};
  int? _anchor;
  List<String> _recent = const [];
  final _pathCtrl = TextEditingController();
  final _focus = FocusNode();

  String get _home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    String start = _home;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastDirKey);
      if (last != null && Directory(last).existsSync()) start = last;
      _recent = prefs.getStringList(_recentKey) ?? const [];
    } catch (_) {}
    await _open(start);
    _focus.requestFocus();
  }

  List<_Place> get _places {
    final h = _home;
    final out = <_Place>[
      _Place('Home', h, Icons.home_outlined),
      _Place('Desktop', p.join(h, 'Desktop'), Icons.desktop_windows_outlined),
      _Place('Documents', p.join(h, 'Documents'), Icons.description_outlined),
      _Place('Downloads', p.join(h, 'Downloads'), Icons.download_outlined),
      _Place('Pictures', p.join(h, 'Pictures'), Icons.image_outlined),
    ];
    if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = '${String.fromCharCode(c)}:\\';
        if (Directory(drive).existsSync())
          out.add(
            _Place(
              'Drive ${String.fromCharCode(c)}:',
              drive,
              Icons.storage_outlined,
            ),
          );
      }
    } else {
      out.add(const _Place('Computer', '/', Icons.computer_outlined));
      for (final root in [
        if (Platform.isMacOS) '/Volumes',
        '/media/${Platform.environment['USER'] ?? ''}',
        '/mnt',
        '/run/media/${Platform.environment['USER'] ?? ''}',
      ]) {
        final d = Directory(root);
        if (!d.existsSync()) continue;
        try {
          for (final v in d.listSync().whereType<Directory>()) {
            out.add(_Place(p.basename(v.path), v.path, Icons.usb_outlined));
          }
        } catch (_) {}
      }
    }
    return [
      for (final pl in out)
        if (Directory(pl.path).existsSync()) pl,
    ];
  }

  Future<void> _open(String dir) async {
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
      _anchor = null;
    });
    try {
      final d = Directory(dir);
      final list = <_Entry>[];
      await for (final e in d.list(followLinks: true)) {
        try {
          final st = await e.stat();
          final isDir = st.type == FileSystemEntityType.directory;
          list.add(_Entry(e.path, isDir, st.size, st.modified));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _dir = d.absolute.path;
        _entries = list;
        _loading = false;
        _pathCtrl.text = _dir;
      });
      try {
        await (await SharedPreferences.getInstance()).setString(
          _lastDirKey,
          _dir,
        );
      } catch (_) {}
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Cannot open this folder: ${e.osError?.message ?? e.message}';
        });
      }
    }
  }

  List<_Entry> get _visible {
    final f = _filter.toLowerCase();
    final ext = widget.extensions;
    final out = _entries.where((e) {
      if (!_showHidden && e.name.startsWith('.')) return false;
      if (f.isNotEmpty && !e.name.toLowerCase().contains(f)) return false;
      if (e.isDir) return true;
      if (ext == null || ext.isEmpty) return true;
      return ext.contains(
        p.extension(e.path).toLowerCase().replaceFirst('.', ''),
      );
    }).toList();
    int cmp(_Entry a, _Entry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final r = switch (_sort) {
        _Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _Sort.modified => a.modified.compareTo(b.modified),
        _Sort.size => a.size.compareTo(b.size),
      };
      return _ascending ? r : -r;
    }

    out.sort(cmp);
    return out;
  }

  Future<void> _finish(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = [_dir, ..._recent.where((d) => d != _dir)].take(8).toList();
      await prefs.setStringList(_recentKey, r);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(paths);
  }

  void _tap(int index, _Entry e) {
    final kb = HardwareKeyboard.instance;
    setState(() {
      if (e.isDir) {
        _selected
          ..clear()
          ..add(e.path);
      } else if (widget.multiple && (kb.isControlPressed || kb.isMetaPressed)) {
        _selected.contains(e.path)
            ? _selected.remove(e.path)
            : _selected.add(e.path);
      } else if (widget.multiple && kb.isShiftPressed && _anchor != null) {
        final vis = _visible;
        final a = _anchor!.clamp(0, vis.length - 1), b = index;
        _selected
          ..clear()
          ..addAll([
            for (var i = (a < b ? a : b); i <= (a < b ? b : a); i++)
              if (!vis[i].isDir) vis[i].path,
          ]);
      } else {
        _selected
          ..clear()
          ..add(e.path);
      }
      _anchor = index;
    });
  }

  void _activate(_Entry e) {
    if (e.isDir) {
      unawaited(_open(e.path));
    } else {
      unawaited(_finish([e.path]));
    }
  }

  void _openSelected() {
    final files = _selected
        .where((s) => !FileSystemEntity.isDirectorySync(s))
        .toList();
    if (files.isNotEmpty) {
      unawaited(_finish(files));
      return;
    }
    if (_selected.length == 1) unawaited(_open(_selected.first));
  }

  String _size(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(1)} GB';
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 720;
    final vis = _visible;
    final parent = p.dirname(_dir);
    final segments = <String>[];
    var acc = _dir;
    while (true) {
      segments.insert(0, acc);
      final up = p.dirname(acc);
      if (up == acc) break;
      acc = up;
    }
    final filesSelected = _selected
        .where((s) => !FileSystemEntity.isDirectorySync(s))
        .length;

    final places = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final pl in _places)
          ListTile(
            dense: true,
            leading: Icon(pl.icon, size: 18),
            title: Text(pl.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: _dir == pl.path,
            onTap: () => unawaited(_open(pl.path)),
          ),
        if (_recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'RECENT FOLDERS',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final r in _recent)
            if (Directory(r).existsSync())
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 18),
                title: Text(
                  p.basename(r).isEmpty ? r : p.basename(r),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  r,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5),
                ),
                onTap: () => unawaited(_open(r)),
              ),
        ],
      ],
    );

    final list = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          )
        : vis.isEmpty
        ? Center(
            child: Text(
              _filter.isEmpty
                  ? 'No matching files here'
                  : 'Nothing matches "$_filter"',
            ),
          )
        : ListView.builder(
            itemCount: vis.length,
            itemExtent: 40,
            itemBuilder: (context, i) {
              final e = vis[i];
              final sel = _selected.contains(e.path);
              final ext = p.extension(e.path).toLowerCase();
              return Material(
                color: sel
                    ? DsColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                child: InkWell(
                  onTapDown: (_) => _tap(i, e), // instant select
                  onTap: () {},
                  onDoubleTap: () => _activate(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          e.isDir
                              ? Icons.folder_rounded
                              : ext == '.pdf'
                              ? Icons.picture_as_pdf_rounded
                              : const {
                                  '.png',
                                  '.jpg',
                                  '.jpeg',
                                  '.webp',
                                  '.gif',
                                  '.bmp',
                                  '.tif',
                                  '.tiff',
                                  '.heic',
                                }.contains(ext)
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 20,
                          color: e.isDir
                              ? const Color(0xFFE9A13B)
                              : (ext == '.pdf'
                                    ? DsColors.primary
                                    : theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!narrow) ...[
                          SizedBox(
                            width: 130,
                            child: Text(
                              _date(e.modified),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              e.isDir ? '' : _size(e.size),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall,
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

    Widget sortHeader(
      String label,
      _Sort s, {
      double? width,
      bool expand = false,
    }) {
      final w = InkWell(
        onTap: () => setState(() {
          if (_sort == s) {
            _ascending = !_ascending;
          } else {
            _sort = s;
            _ascending = s == _Sort.name;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: s == _Sort.size
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_sort == s)
                Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                ),
            ],
          ),
        ),
      );
      return expand ? Expanded(child: w) : SizedBox(width: width, child: w);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          if (parent != _dir) unawaited(_open(parent));
        },
        const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            setState(() => _showHidden = !_showHidden),
      },
      child: Focus(
        focusNode: _focus,
        child: Dialog(
          insetPadding: EdgeInsets.all(narrow ? 8 : 32),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: narrow ? size.width : 960,
            height: narrow ? size.height : 620,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(widget.title, style: theme.textTheme.titleMedium),
                      const SizedBox(width: 16),
                      IconButton(
                        tooltip: 'Up (Backspace)',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: parent == _dir
                            ? null
                            : () => unawaited(_open(parent)),
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            children: [
                              for (final seg in segments.reversed)
                                Row(
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                      ),
                                      onPressed: () => unawaited(_open(seg)),
                                      child: Text(
                                        p.basename(seg).isEmpty
                                            ? seg
                                            : p.basename(seg),
                                      ),
                                    ),
                                    if (seg != segments.last)
                                      const Icon(Icons.chevron_right, size: 16),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: narrow ? 120 : 200,
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                            hintText: 'Filter',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _filter = v),
                        ),
                      ),
                      IconButton(
                        tooltip: _showHidden
                            ? 'Hide hidden files (Ctrl+H)'
                            : 'Show hidden files (Ctrl+H)',
                        isSelected: _showHidden,
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _showHidden = !_showHidden),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!narrow) ...[
                        SizedBox(width: 210, child: places),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 30),
                                  sortHeader('Name', _Sort.name, expand: true),
                                  if (!narrow) ...[
                                    sortHeader(
                                      'Modified',
                                      _Sort.modified,
                                      width: 130,
                                    ),
                                    sortHeader('Size', _Sort.size, width: 80),
                                  ],
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(child: list),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      if (narrow)
                        PopupMenuButton<String>(
                          tooltip: 'Places',
                          icon: const Icon(Icons.place_outlined),
                          onSelected: (v) => unawaited(_open(v)),
                          itemBuilder: (_) => [
                            for (final pl in _places)
                              PopupMenuItem(
                                value: pl.path,
                                child: Text(pl.label),
                              ),
                          ],
                        ),
                      Expanded(
                        child: TextField(
                          controller: _pathCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Location',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) {
                            final t = v.trim();
                            if (FileSystemEntity.isDirectorySync(t)) {
                              unawaited(_open(t));
                            } else if (File(t).existsSync()) {
                              unawaited(_finish([t]));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (widget.extensions != null &&
                          widget.extensions!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            widget.extensions!.map((e) => '.$e').join(' '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _selected.isEmpty ? null : _openSelected,
                        child: Text(
                          filesSelected > 1
                              ? 'Open $filesSelected files'
                              : 'Open',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
