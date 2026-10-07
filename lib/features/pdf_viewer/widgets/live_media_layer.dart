import 'package:document_studio/core/pdf/large_doc_policy.dart';

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/infrastructure/pdf/pdf_media_annotations.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Multimedia annotations of the open document, indexed once per saved
/// version (off the UI isolate) so pages without media pay nothing.
class PdfMediaIndex extends ChangeNotifier {
  Map<int, List<PdfMediaAnnotation>> _byPage = const {};
  String? _key;
  DocumentSession? _session;
  bool _disposed = false;

  List<PdfMediaAnnotation> forPage(int page) => _byPage[page] ?? const [];

  bool get isEmpty => _byPage.isEmpty;

  /// Re-indexes when [session] or its content version changed.
  Future<void> sync(DocumentSession session) async {
    _session = session;
    final key = '${session.sourcePath}:${session.revision}';
    if (key == _key) return;
    _key = key;
    try {
      // Skip the scan for very large files (it parses the whole document).
      final bytes = await LargeDocPolicy.readBounded(session);
      if (bytes == null) return;
      final found = await Isolate.run(() => indexPdfMedia(bytes));
      if (_disposed || _key != key) return;
      _byPage = found;
      notifyListeners();
    } catch (_) {
      // No media overlay is better than a broken viewer.
    }
  }

  /// Extracts and opens [annot] with the system player.
  Future<String?> play(PdfMediaAnnotation annot) async {
    if (annot.uri != null) {
      final ok = await launchUrl(
        annot.uri!,
        mode: LaunchMode.externalApplication,
      );
      return ok ? null : 'Could not open ${annot.uri}';
    }
    final session = _session;
    if (session == null || !annot.embedded) {
      return 'This media type cannot be played here.';
    }
    final Uint8List? data = await () async {
      final bytes = await session.readCurrentBytes();
      final live = readPdfMediaAnnotations(bytes, annot.page);
      for (final a in live) {
        if ((a.normRect.center - annot.normRect.center).distance < 1e-4) {
          return a.extract();
        }
      }
      return null;
    }();
    if (data == null) return 'The embedded media could not be read.';
    final dir = await Directory.systemTemp.createTemp('ds-media-');
    var name = annot.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (p.extension(name).isEmpty) name = '$name.mp4';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(data, flush: true);
    final ok = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    return ok ? null : 'No player is installed for ${p.extension(name)} files.';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Play badge over each media annotation of one page (Acrobat poster style).
Widget? buildMediaPageOverlay({
  required Size pageSize,
  required List<PdfMediaAnnotation> annotations,
  required Future<void> Function(PdfMediaAnnotation annot) onPlay,
}) {
  if (annotations.isEmpty) return null;
  return Positioned.fill(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (final a in annotations)
          Positioned(
            left: a.normRect.left * pageSize.width,
            top: a.normRect.top * pageSize.height,
            width: a.normRect.width * pageSize.width,
            height: a.normRect.height * pageSize.height,
            child: _MediaBadge(annot: a, onPlay: onPlay),
          ),
      ],
    ),
  );
}

class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.annot, required this.onPlay});

  final PdfMediaAnnotation annot;
  final Future<void> Function(PdfMediaAnnotation annot) onPlay;

  @override
  Widget build(BuildContext context) {
    final playable = annot.canPlay;
    final icon = switch (annot.kind) {
      PdfMediaKind.audio => Icons.volume_up,
      PdfMediaKind.threeD => Icons.view_in_ar,
      _ => playable ? Icons.play_arrow_rounded : Icons.block,
    };
    return Tooltip(
      message: playable
          ? 'Play ${annot.fileName}'
          : 'This interactive content is not supported',
      child: MouseRegion(
        cursor: playable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onPlay(annot)),
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) {
                final d = (c.biggest.shortestSide * 0.28).clamp(28.0, 64.0);
                return Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: Icon(icon, color: Colors.white, size: d * 0.62),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
