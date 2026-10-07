import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Desktop drag-and-drop for PDF files (`DS-PLAT-DESK-001`).
class DesktopPdfDropTarget extends StatelessWidget {
  const DesktopPdfDropTarget({
    super.key,
    required this.child,
    required this.onPdfsDropped,
    this.enabled = true,
    this.allowMultiple = true,
  });

  final Widget child;
  final Future<void> Function(List<LocalFileRef> pdfs) onPdfsDropped;
  final bool enabled;
  final bool allowMultiple;

  static bool get supportsDesktopDrop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled || !supportsDesktopDrop) return child;

    return DropTarget(
      onDragDone: (details) async {
        final pdfs = <LocalFileRef>[];
        for (final f in details.files) {
          final path = f.path;
          if (path.isEmpty) continue;
          if (p.extension(path).toLowerCase() != '.pdf') continue;
          if (!File(path).existsSync()) continue;
          pdfs.add(LocalFileRef(path: path, displayName: p.basename(path)));
          if (!allowMultiple && pdfs.isNotEmpty) break;
        }
        if (pdfs.isNotEmpty) await onPdfsDropped(pdfs);
      },
      child: child,
    );
  }
}
