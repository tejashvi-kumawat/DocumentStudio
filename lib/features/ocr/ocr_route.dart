import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/features/ocr/image_ocr_screen.dart';
import 'package:document_studio/features/ocr/searchable_pdf_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const imageOcrRoutePath = '/ocr/image';
const searchablePdfRoutePath = '/ocr/searchable-pdf';

class ImageOcrDeps {
  const ImageOcrDeps({
    required this.fileStorage,
    required this.ocrPort,
  });

  final FileStoragePort fileStorage;
  final OcrPort ocrPort;
}

class SearchablePdfDeps {
  const SearchablePdfDeps({
    required this.fileStorage,
    required this.searchablePdfPort,
  });

  final FileStoragePort fileStorage;
  final SearchablePdfPort searchablePdfPort;
}

ImageOcrDeps imageOcrDepsFromRef(WidgetRef ref) {
  return ImageOcrDeps(
    fileStorage: ref.read(fileStorageProvider),
    ocrPort: ref.read(ocrPortProvider),
  );
}

SearchablePdfDeps searchablePdfDepsFromRef(WidgetRef ref) {
  return SearchablePdfDeps(
    fileStorage: ref.read(fileStorageProvider),
    searchablePdfPort: ref.read(searchablePdfPortProvider),
  );
}

GoRoute buildImageOcrRoute({
  ImageOcrDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: imageOcrRoutePath,
    builder: (context, state) {
      if (depsForTests != null) {
        return ImageOcrScreen(deps: depsForTests);
      }
      return Consumer(
        builder: (context, ref, _) {
          return ImageOcrScreen(deps: imageOcrDepsFromRef(ref));
        },
      );
    },
  );
}

GoRoute buildSearchablePdfRoute({
  SearchablePdfDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: searchablePdfRoutePath,
    builder: (context, state) {
      final args = PdfDocumentRouteArgs.tryParse(state.extra);
      if (depsForTests != null) {
        return SearchablePdfScreen(
          deps: depsForTests,
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return SearchablePdfScreen(
            deps: searchablePdfDepsFromRef(ref),
            initialFile: args?.file,
            initialPassword: args?.password,
          );
        },
      );
    },
  );
}
