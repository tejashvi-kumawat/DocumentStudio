import 'package:document_studio/features/pdf_markup/headers_footers_screen.dart';
import 'package:document_studio/features/pdf_markup/page_numbers_screen.dart';
import 'package:document_studio/features/pdf_markup/watermark_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const headersFootersRoutePath = '/headers-footers';
const pageNumbersRoutePath = '/page-numbers';
const watermarkRoutePath = '/watermark';

List<GoRoute> buildPdfMarkupRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return [
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: headersFootersRoutePath,
      builder: (context, state) {
        final args = PdfDocumentRouteArgs.tryParse(state.extra);
        return HeadersFootersScreen(
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: pageNumbersRoutePath,
      builder: (context, state) {
        final args = PdfDocumentRouteArgs.tryParse(state.extra);
        return PageNumbersScreen(
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: watermarkRoutePath,
      builder: (context, state) {
        final args = PdfDocumentRouteArgs.tryParse(state.extra);
        return WatermarkScreen(
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      },
    ),
  ];
}
