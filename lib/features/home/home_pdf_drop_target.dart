import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Wraps home content to accept PDF drops on desktop (`DS-UI-001` stub).
class HomePdfDropTarget extends StatelessWidget {
  const HomePdfDropTarget({
    super.key,
    required this.child,
    required this.onPdfDropped,
    this.enabled = true,
    this.onDragActiveChanged,
  });

  final Widget child;
  final Future<void> Function(LocalFileRef pdf) onPdfDropped;
  final bool enabled;

  /// Fired when a drag enters or leaves the drop surface (desktop only).
  final ValueChanged<bool>? onDragActiveChanged;

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
      onDragEntered: (_) => onDragActiveChanged?.call(true),
      onDragExited: (_) => onDragActiveChanged?.call(false),
      onDragDone: (details) async {
        onDragActiveChanged?.call(false);
        for (final f in details.files) {
          final path = f.path;
          if (path.isEmpty) continue;
          if (!const {
            '.pdf',
            '.docx',
            '.pptx',
          }.contains(p.extension(path).toLowerCase())) {
            continue;
          }
          if (!File(path).existsSync()) continue;
          await onPdfDropped(
            LocalFileRef(
              path: await LinuxDocumentPortal.resolve(path),
              displayName: p.basename(path),
            ),
          );
          return;
        }
      },
      child: child,
    );
  }
}
