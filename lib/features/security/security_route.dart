import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/security/metadata_editor_screen.dart';
import 'package:document_studio/features/security/protect_screen.dart';
import 'package:document_studio/features/security/remove_metadata_screen.dart';
import 'package:document_studio/features/security/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const protectRoutePath = '/protect';
const unlockRoutePath = '/unlock';
const metadataRoutePath = '/metadata';
const removeMetadataRoutePath = '/remove-metadata';

/// Handoff from viewer document properties → metadata editor.
class MetadataEditorRouteArgs extends PdfDocumentRouteArgs {
  const MetadataEditorRouteArgs({required super.file, super.password});
}

ProtectDeps protectDepsFromRef(WidgetRef ref) {
  return ProtectDeps(
    fileStorage: ref.read(fileStorageProvider),
    encryptPort: ref.read(pdfEncryptPortProvider),
  );
}

UnlockDeps unlockDepsFromRef(WidgetRef ref) {
  return UnlockDeps(
    fileStorage: ref.read(fileStorageProvider),
    encryptPort: ref.read(pdfEncryptPortProvider),
  );
}

MetadataEditorDeps metadataEditorDepsFromRef(WidgetRef ref) {
  return MetadataEditorDeps(
    fileStorage: ref.read(fileStorageProvider),
    pdf: ref.read(pdfRenderPortProvider),
    metadataPort: ref.read(pdfMetadataPortProvider),
  );
}

RemoveMetadataDeps removeMetadataDepsFromRef(WidgetRef ref) {
  return RemoveMetadataDeps(
    fileStorage: ref.read(fileStorageProvider),
    metadataPort: ref.read(pdfMetadataPortProvider),
  );
}

GoRoute buildProtectRoute({
  ProtectDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: protectRoutePath,
    builder: (context, state) {
      LocalFileRef? initialFile;
      final extra = state.extra;
      if (extra is LocalFileRef) {
        initialFile = extra;
      }
      if (depsForTests != null) {
        return ProtectScreen(deps: depsForTests, initialFile: initialFile);
      }
      return Consumer(
        builder: (context, ref, _) {
          return ProtectScreen(
            deps: protectDepsFromRef(ref),
            initialFile: initialFile,
          );
        },
      );
    },
  );
}

GoRoute buildUnlockRoute({
  UnlockDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: unlockRoutePath,
    builder: (context, state) {
      final args = PdfDocumentRouteArgs.tryParse(state.extra);
      if (depsForTests != null) {
        return UnlockScreen(
          deps: depsForTests,
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return UnlockScreen(
            deps: unlockDepsFromRef(ref),
            initialFile: args?.file,
            initialPassword: args?.password,
          );
        },
      );
    },
  );
}

GoRoute buildMetadataEditorRoute({
  MetadataEditorDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: metadataRoutePath,
    builder: (context, state) {
      LocalFileRef? initialFile;
      String? initialPassword;
      final extra = state.extra;
      if (extra is MetadataEditorRouteArgs) {
        initialFile = extra.file;
        initialPassword = extra.password;
      } else if (extra is LocalFileRef) {
        initialFile = extra;
      }
      if (depsForTests != null) {
        return MetadataEditorScreen(
          deps: depsForTests,
          initialFile: initialFile,
          initialPassword: initialPassword,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return MetadataEditorScreen(
            deps: metadataEditorDepsFromRef(ref),
            initialFile: initialFile,
            initialPassword: initialPassword,
          );
        },
      );
    },
  );
}

GoRoute buildRemoveMetadataRoute({
  RemoveMetadataDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: removeMetadataRoutePath,
    builder: (context, state) {
      final args = PdfDocumentRouteArgs.tryParse(state.extra);
      if (depsForTests != null) {
        return RemoveMetadataScreen(
          deps: depsForTests,
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return RemoveMetadataScreen(
            deps: removeMetadataDepsFromRef(ref),
            initialFile: args?.file,
            initialPassword: args?.password,
          );
        },
      );
    },
  );
}

List<GoRoute> buildSecurityRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return [
    buildProtectRoute(parentNavigatorKey: parentNavigatorKey),
    buildUnlockRoute(parentNavigatorKey: parentNavigatorKey),
    buildMetadataEditorRoute(parentNavigatorKey: parentNavigatorKey),
    buildRemoveMetadataRoute(parentNavigatorKey: parentNavigatorKey),
  ];
}
