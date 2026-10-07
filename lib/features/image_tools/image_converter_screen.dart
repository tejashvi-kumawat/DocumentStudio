import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/image_tools/image_tools_deps.dart';
import 'package:document_studio/infrastructure/image/image_processing_port.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

enum _Status { waiting, working, done, failed }

class _Item {
  _Item(this.file);

  final LocalFileRef file;
  _Status status = _Status.waiting;
  String? output;
  String? error;
  int? outBytes;
}

/// Batch image converter: drop many pictures, pick a format (JPG, PNG, GIF,
/// BMP, TIFF, ICO), optionally resize, and convert them all at once.
class ImageConverterScreen extends StatefulWidget {
  const ImageConverterScreen({super.key, required this.deps});

  final ImageToolsDeps deps;

  @override
  State<ImageConverterScreen> createState() => _ImageConverterScreenState();
}

class _ImageConverterScreenState extends State<ImageConverterScreen> {
  final List<_Item> _items = [];
  ImageOutputFormat _format = ImageOutputFormat.png;
  int _quality = 88;
  int? _maxWidth;
  String? _outDir;
  bool _running = false;
  bool _dragging = false;

  FileStoragePort get _storage => widget.deps.fileStorage;

  Future<void> _pick() async {
    final files = await _storage.pickOpenFiles(
      allowedExtensions: kImageInputExtensions,
    );
    _add(files);
  }

  void _add(Iterable<LocalFileRef> files) {
    if (files.isEmpty) return;
    final known = _items.map((e) => e.file.path).toSet();
    setState(() {
      for (final f in files) {
        if (known.add(f.path) && kImageInputExtensions.contains(f.extension)) {
          _items.add(_Item(f));
        }
      }
    });
  }

  Future<void> _chooseFolder() async {
    final dir = await _storage.pickOutputDirectory(
      dialogTitle: 'Where should converted images go?',
    );
    if (dir != null && mounted) setState(() => _outDir = dir);
  }

  Future<void> _convert() async {
    if (_running || _items.isEmpty) return;
    setState(() => _running = true);
    final port = widget.deps.imageProcessing;
    for (final item in _items) {
      if (!mounted) return;
      setState(() {
        item.status = _Status.working;
        item.error = null;
      });
      try {
        final bytes = await _storage.readBytes(item.file);
        final decoded = await port.decode(bytes);
        final w = _maxWidth;
        final rendered = await port.render(
          decoded,
          ImageEditSpec(
            width: w != null && w < decoded.width ? w : null,
            format: _format,
            jpegQuality: _quality,
          ),
        );
        final dir = _outDir ?? p.dirname(item.file.path);
        var out = p.join(
          dir,
          '${p.basenameWithoutExtension(item.file.displayName)}.${_format.extension}',
        );
        // Never overwrite the original or an earlier result.
        var n = 1;
        while (File(out).existsSync()) {
          out = p.join(
            dir,
            '${p.basenameWithoutExtension(item.file.displayName)}-$n.${_format.extension}',
          );
          n++;
        }
        await File(out).writeAsBytes(rendered.bytes, flush: true);
        if (!mounted) return;
        setState(() {
          item.status = _Status.done;
          item.output = out;
          item.outBytes = rendered.bytes.length;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          item.status = _Status.failed;
          item.error = '$e';
        });
      }
    }
    if (mounted) setState(() => _running = false);
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final done = _items.where((e) => e.status == _Status.done).length;

    final list = DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        _add([
          for (final f in d.files)
            LocalFileRef(path: f.path, displayName: p.basename(f.path)),
        ]);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _dragging
                ? DsColors.primary
                : DsColors.border(theme.brightness),
            width: _dragging ? 2 : 1,
          ),
        ),
        child: _items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 44,
                      color: DsColors.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Drop images here',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'JPG, PNG, WebP, GIF, BMP, TIFF, ICO and more',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _pick,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose images'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        return ListTile(
                          dense: true,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Image.file(
                                File(it.file.path),
                                fit: BoxFit.cover,
                                cacheWidth: 120,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.image_not_supported_outlined,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            it.file.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            switch (it.status) {
                              _Status.waiting =>
                                it.file.extension.toUpperCase(),
                              _Status.working => 'Converting…',
                              _Status.done =>
                                '→ ${p.basename(it.output!)} · ${_size(it.outBytes)}',
                              _Status.failed => it.error ?? 'Failed',
                            },
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: switch (it.status) {
                            _Status.working => const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            _Status.done => const Icon(
                              Icons.check_circle,
                              color: DsColors.success,
                              size: 20,
                            ),
                            _Status.failed => const Icon(
                              Icons.error_outline,
                              color: DsColors.error,
                              size: 20,
                            ),
                            _Status.waiting => IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _running
                                  ? null
                                  : () => setState(() => _items.removeAt(i)),
                            ),
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _running ? null : _pick,
                          icon: const Icon(Icons.add),
                          label: const Text('Add more'),
                        ),
                        TextButton(
                          onPressed: _running
                              ? null
                              : () => setState(_items.clear),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );

    final settings = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Convert to', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in ImageOutputFormat.values)
                  ChoiceChip(
                    label: Text(f.label.split(' ').first),
                    selected: _format == f,
                    onSelected: _running
                        ? null
                        : (_) => setState(() => _format = f),
                  ),
              ],
            ),
            if (_format.isLossy) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('Quality'),
                  const Spacer(),
                  Text('$_quality'),
                ],
              ),
              Slider(
                min: 40,
                max: 100,
                divisions: 60,
                value: _quality.toDouble(),
                onChanged: _running
                    ? null
                    : (v) => setState(() => _quality = v.round()),
              ),
            ],
            const SizedBox(height: 10),
            Text('Size', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            DropdownButton<int?>(
              value: _maxWidth,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('Keep original size'),
                ),
                DropdownMenuItem(
                  value: 3840,
                  child: Text('Max width 3840 px (4K)'),
                ),
                DropdownMenuItem(
                  value: 1920,
                  child: Text('Max width 1920 px (Full HD)'),
                ),
                DropdownMenuItem(value: 1280, child: Text('Max width 1280 px')),
                DropdownMenuItem(value: 800, child: Text('Max width 800 px')),
                DropdownMenuItem(value: 512, child: Text('Max width 512 px')),
              ],
              onChanged: _running ? null : (v) => setState(() => _maxWidth = v),
            ),
            const SizedBox(height: 10),
            Text('Save to', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _running ? null : _chooseFolder,
              icon: const Icon(Icons.folder_outlined, size: 18),
              label: Text(
                _outDir == null
                    ? 'Next to the originals'
                    : p.basename(_outDir!),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _items.isEmpty || _running ? null : _convert,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.transform),
              label: Text(
                _running
                    ? 'Converting…'
                    : _items.isEmpty
                    ? 'Convert'
                    : 'Convert ${_items.length} image${_items.length == 1 ? '' : 's'}',
              ),
            ),
            if (done > 0 && !_running) ...[
              const SizedBox(height: 10),
              Text(
                '$done converted. Originals were not changed.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: DsToolAppBar(
        title: 'Image converter',
        subtitle: 'Convert images between formats on this device',
        icon: Icons.transform,
        onBack: () => context.canPop() ? context.pop() : context.go('/'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 340,
                    child: SingleChildScrollView(child: settings),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: SingleChildScrollView(child: settings),
                  ),
                ],
              ),
      ),
    );
  }
}
