import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:document_studio/features/image_tools/image_tools_deps.dart';
import 'package:document_studio/features/image_tools/image_tools_screen.dart';
import 'package:document_studio/infrastructure/image/image_package_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route path for lead to register in [app_router.dart].
const imageToolsRoutePath = '/image-tools';

ImageToolsDeps imageToolsDepsFromRef(WidgetRef ref) {
  return ImageToolsDeps(
    fileStorage: ref.read(fileStorageProvider),
    imageProcessing: ImagePackageAdapter(),
  );
}

/// Standalone route definition — wire into app router separately.
///
/// `extra` may be a [LocalFileRef] to open immediately.
GoRoute buildImageToolsRoute({
  ImageToolsDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: imageToolsRoutePath,
    builder: (context, state) {
      final initial = state.extra is LocalFileRef
          ? state.extra! as LocalFileRef
          : null;
      if (depsForTests != null) {
        return ImageToolsScreen(deps: depsForTests, initialFile: initial);
      }
      return Consumer(
        builder: (context, ref, _) {
          return ImageToolsScreen(
            deps: imageToolsDepsFromRef(ref),
            initialFile: initial,
          );
        },
      );
    },
  );
}
