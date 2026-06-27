import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/image_viewer/image_viewer_screen.dart';
import 'package:document_studio/features/print/pdf_print_button.dart';
import 'package:document_studio/features/print/print_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const imageViewerRoutePath = '/image-viewer';

class ImageViewerDeps {
  const ImageViewerDeps({
    required this.fileStorage,
    required this.printService,
  });

  final FileStoragePort fileStorage;
  final PrintService printService;
}

ImageViewerDeps imageViewerDepsFromRef(WidgetRef ref) {
  return ImageViewerDeps(
    fileStorage: ref.read(fileStorageProvider),
    printService: ref.read(printServiceProvider),
  );
}

/// `extra` may be a [LocalFileRef] to open immediately.
GoRoute buildImageViewerRoute({
  ImageViewerDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: imageViewerRoutePath,
    builder: (context, state) {
      final initial = state.extra is LocalFileRef
          ? state.extra! as LocalFileRef
          : null;
      if (depsForTests != null) {
        return ImageViewerScreen(deps: depsForTests, initialFile: initial);
      }
      return Consumer(
        builder: (context, ref, _) {
          return ImageViewerScreen(
            deps: imageViewerDepsFromRef(ref),
            initialFile: initial,
          );
        },
      );
    },
  );
}
