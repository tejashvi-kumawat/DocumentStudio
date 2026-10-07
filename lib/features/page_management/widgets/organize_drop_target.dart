import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Desktop/tablet file drop onto the organize workspace.
class OrganizeDropTarget extends StatelessWidget {
  const OrganizeDropTarget({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.enabled = true,
  });

  final Widget child;
  final Future<void> Function(List<LocalFileRef> pdfs) onFilesDropped;
  final bool enabled;

  bool get _supportsDrop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled || !_supportsDrop) return child;

    return DropTarget(
      onDragDone: (details) async {
        final pdfs = <LocalFileRef>[];
        for (final f in details.files) {
          final path = f.path;
          if (path.isEmpty) continue;
          if (p.extension(path).toLowerCase() != '.pdf') continue;
          if (!File(path).existsSync()) continue;
          pdfs.add(LocalFileRef(path: path, displayName: p.basename(path)));
        }
        if (pdfs.isNotEmpty) await onFilesDropped(pdfs);
      },
      child: child,
    );
  }
}
