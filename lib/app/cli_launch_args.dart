import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:path/path.dart' as p;

/// Parsed process arguments for desktop shell / "Open with" launches.
///
/// Examples:
/// - `document_studio.exe C:\docs\a.pdf`
/// - `document_studio.exe --tool compress C:\docs\a.pdf`
/// - `document_studio.exe --tool merge a.pdf b.pdf`
class CliLaunchArgs {
  const CliLaunchArgs({
    this.files = const [],
    this.tool,
  });

  final List<String> files;
  final String? tool;

  static const imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'tif',
    'tiff',
    'bmp',
    'gif',
  };

  bool get hasWork => files.isNotEmpty || (tool != null && tool!.isNotEmpty);

  ViewerToolId? get viewerTool {
    final t = tool?.trim().toLowerCase();
    if (t == null || t.isEmpty || t == 'open') return null;
    return switch (t) {
      'compress' => ViewerToolId.compress,
      'protect' || 'encrypt' => ViewerToolId.protect,
      'unlock' || 'decrypt' => ViewerToolId.unlock,
      'split' => ViewerToolId.split,
      'merge' || 'organize' => ViewerToolId.workspaceMerge,
      'ocr' || 'searchable' => ViewerToolId.searchablePdf,
      'watermark' => ViewerToolId.watermark,
      'metadata' => ViewerToolId.metadata,
      'redact' => ViewerToolId.redact,
      'export' || 'images' => ViewerToolId.exportImages,
      _ => null,
    };
  }

  static bool isImagePath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return imageExtensions.contains(ext);
  }

  static bool isPdfPath(String path) =>
      p.extension(path).toLowerCase() == '.pdf';

  /// Prefer [Platform.executableArguments]; falls back to [Platform.environment]
  /// `DS_OPEN_FILES` (pipe-separated) for tests / wrappers.
  static CliLaunchArgs fromProcess() {
    final fromArgs = parse(Platform.executableArguments);
    if (fromArgs.hasWork) return fromArgs;
    final env = Platform.environment['DS_OPEN_FILES'];
    if (env == null || env.trim().isEmpty) return const CliLaunchArgs();
    final paths = env
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parse(paths);
  }

  static CliLaunchArgs parse(List<String> args) {
    String? tool;
    final files = <String>[];
    for (var i = 0; i < args.length; i++) {
      final a = args[i].trim();
      if (a.isEmpty) continue;
      if (a == '--tool' || a == '-t') {
        if (i + 1 < args.length) {
          tool = args[++i].trim();
        }
        continue;
      }
      if (a.startsWith('--tool=')) {
        tool = a.substring('--tool='.length).trim();
        continue;
      }
      // Flutter / embedder noise
      if (a.startsWith('-') || a.startsWith('--')) continue;
      final normalized = p.normalize(a);
      if (File(normalized).existsSync()) {
        files.add(normalized);
      }
    }
    return CliLaunchArgs(files: files, tool: tool);
  }

  List<LocalFileRef> get fileRefs => [
        for (final path in files)
          LocalFileRef(path: path, displayName: p.basename(path)),
      ];
}
