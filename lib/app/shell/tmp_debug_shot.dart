// TEMPORARY visual-verification hook; delete before finishing.
import 'dart:async';
import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

void tmpDebugShot(ProviderContainer container) {
  final out = Platform.environment['DS_SHOT'];
  if (out == null) return;
  final open = Platform.environment['DS_OPEN'];
  final width = double.tryParse(Platform.environment['DS_W'] ?? '');
  Timer(const Duration(seconds: 3), () async {
    if (width != null) await windowManager.setSize(Size(width, 760));
    if (open != null) {
      for (final p in open.split(',')) {
        container.read(documentTabsControllerProvider).openDocument(
              LocalFileRef(path: p, displayName: p.split('/').last),
            );
      }
      if (Platform.environment['DS_HOME'] == '1') {
        container.read(documentTabsControllerProvider).showHome();
      }
    }
  });
  Timer(const Duration(seconds: 8), () async {
    final rv = WidgetsBinding.instance.renderViews.first;
    final layer = rv.debugLayer! as OffsetLayer;
    final img = layer.toImageSync(Offset.zero & rv.size, pixelRatio: 1);
    final bd = await img.toByteData();
    File('$out.rgba').writeAsBytesSync(bd!.buffer.asUint8List());
    File('$out.txt').writeAsStringSync('${img.width} ${img.height}');
    exit(0);
  });
}
