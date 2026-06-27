import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/create_pdf_screen.dart';
import 'package:document_studio/features/conversion/images_to_pdf_screen.dart';
import 'package:document_studio/features/conversion/office_convert_screen.dart';
import 'package:document_studio/features/conversion/pdf_to_images_screen.dart';
import 'package:document_studio/features/conversion/scan_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/infrastructure/conversion/blank_pdf_service.dart';
import 'package:document_studio/infrastructure/conversion/conversion_format.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route paths — register in [app_router.dart].
const createPdfRoutePath = '/create-pdf';
const imagesToPdfRoutePath = '/images-to-pdf';
const pdfToImagesRoutePath = '/pdf-to-images';
const scanRoutePath = '/scan';
const officeConvertRoutePath = '/office-convert';

/// Optional handoff from the PDF viewer (file + current page for export).
class PdfToImagesRouteArgs {
  const PdfToImagesRouteArgs({
    required this.file,
    this.page1,
    this.password,
  });

  final LocalFileRef file;
  final int? page1;
  final String? password;
}

CreatePdfDeps createPdfDepsFromRef(WidgetRef ref) {
  return CreatePdfDeps(
    fileStorage: ref.read(fileStorageProvider),
    textToPdf: TextToPdfService(),
    blankPdf: BlankPdfService(),
  );
}

ImagesToPdfDeps imagesToPdfDepsFromRef(WidgetRef ref) {
  return ImagesToPdfDeps(
    fileStorage: ref.read(fileStorageProvider),
    imagesToPdf: ImagesToPdfService(),
    jobs: ref.read(jobRunnerProvider),
  );
}

PdfToImagesDeps pdfToImagesDepsFromRef(WidgetRef ref) {
  return PdfToImagesDeps(
    fileStorage: ref.read(fileStorageProvider),
    pdfToImages: PdfToImagesService(),
    jobs: ref.read(jobRunnerProvider),
  );
}

/// Short alias routes for format-specific catalog rows ([DS-CNV-FMT-*]).
List<GoRoute> buildConversionFormatAliasRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  GoRoute redirect(String targetFormat, String path) {
    return GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: path,
      redirect: (context, state) {
        final q = Map<String, String>.from(state.uri.queryParameters);
        q['format'] = targetFormat;
        return Uri(
          path: state.uri.path.startsWith('/pdf-to')
              ? pdfToImagesRoutePath
              : imagesToPdfRoutePath,
          queryParameters: q.isEmpty ? null : q,
        ).toString();
      },
    );
  }

  return [
    redirect('jpeg', '/jpg-to-pdf'),
    redirect('jpeg', '/jpeg-to-pdf'),
    redirect('png', '/png-to-pdf'),
    redirect('webp', '/webp-to-pdf'),
    redirect('tiff', '/tiff-to-pdf'),
    redirect('bmp', '/bmp-to-pdf'),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: '/pdf-to-jpg',
      redirect: (_, state) {
        final q = Map<String, String>.from(state.uri.queryParameters);
        q['format'] = 'jpeg';
        return Uri(path: pdfToImagesRoutePath, queryParameters: q).toString();
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: '/pdf-to-png',
      redirect: (_, state) {
        final q = Map<String, String>.from(state.uri.queryParameters);
        q['format'] = 'png';
        return Uri(path: pdfToImagesRoutePath, queryParameters: q).toString();
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: '/pdf-to-webp',
      redirect: (_, state) {
        final q = Map<String, String>.from(state.uri.queryParameters);
        q['format'] = 'webp';
        return Uri(path: pdfToImagesRoutePath, queryParameters: q).toString();
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: '/pdf-to-tiff',
      redirect: (_, state) {
        final q = Map<String, String>.from(state.uri.queryParameters);
        q['format'] = 'tiff';
        return Uri(path: pdfToImagesRoutePath, queryParameters: q).toString();
      },
    ),
  ];
}

GoRoute buildOfficeConvertRoute({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: officeConvertRoutePath,
    builder: (context, state) {
      final extra = state.extra;
      final initial = extra is LocalFileRef
          ? extra
          : PdfDocumentRouteArgs.tryParse(extra)?.file;
      return OfficeConvertScreen(initialFile: initial);
    },
  );
}

GoRoute buildScanRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: scanRoutePath,
    builder: (context, state) => const ScanScreen(),
  );
}

/// Standalone route definition — wire into app router separately.
GoRoute buildCreatePdfRoute({
  CreatePdfDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: createPdfRoutePath,
    builder: (context, state) {
      if (depsForTests != null) {
        return CreatePdfScreen(deps: depsForTests);
      }
      return Consumer(
        builder: (context, ref, _) {
          return CreatePdfScreen(deps: createPdfDepsFromRef(ref));
        },
      );
    },
  );
}

GoRoute buildImagesToPdfRoute({
  ImagesToPdfDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: imagesToPdfRoutePath,
    builder: (context, state) {
      final options =
          ImagesToPdfRouteOptions.fromQuery(state.uri.queryParameters['format']);
      if (depsForTests != null) {
        return ImagesToPdfScreen(
          deps: depsForTests,
          routeOptions: options,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return ImagesToPdfScreen(
            deps: imagesToPdfDepsFromRef(ref),
            routeOptions: options,
          );
        },
      );
    },
  );
}

GoRoute buildPdfToImagesRoute({
  PdfToImagesDeps? depsForTests,
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: pdfToImagesRoutePath,
    builder: (context, state) {
      final options =
          PdfToImagesRouteOptions.fromQuery(state.uri.queryParameters['format']);
      final extra = state.extra;
      LocalFileRef? initialPdf;
      int? initialPage;
      String? initialPassword;
      if (extra is PdfToImagesRouteArgs) {
        initialPdf = extra.file;
        initialPage = extra.page1;
        initialPassword = extra.password;
      } else if (extra is LocalFileRef) {
        initialPdf = extra;
      }
      final pageParam = state.uri.queryParameters['page'];
      final pageFromQuery = int.tryParse(pageParam ?? '');
      if (initialPage == null &&
          pageFromQuery != null &&
          pageFromQuery >= 1) {
        initialPage = pageFromQuery;
      }
      if (depsForTests != null) {
        return PdfToImagesScreen(
          deps: depsForTests,
          routeOptions: options,
          initialPdf: initialPdf,
          initialPage1: initialPage,
          initialPassword: initialPassword,
        );
      }
      return Consumer(
        builder: (context, ref, _) {
          return PdfToImagesScreen(
            deps: pdfToImagesDepsFromRef(ref),
            routeOptions: options,
            initialPdf: initialPdf,
            initialPage1: initialPage,
            initialPassword: initialPassword,
          );
        },
      );
    },
  );
}
