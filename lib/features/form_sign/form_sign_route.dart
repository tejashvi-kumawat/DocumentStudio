import 'package:document_studio/features/form_sign/fill_form_screen.dart';
import 'package:document_studio/features/form_sign/redact_screen.dart';
import 'package:document_studio/features/form_sign/visual_sign_screen.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/place_image_screen.dart';
import 'package:document_studio/features/pdf_viewer/viewer_markup_tool_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

export 'package:document_studio/features/pdf_viewer/place_image_screen.dart'
    show placeImageRoutePath, PlaceImageScreen;
export 'package:document_studio/features/pdf_viewer/viewer_markup_tool_screen.dart'
    show editTextRoutePath, drawInkRoutePath;

const fillFormRoutePath = '/forms/fill';
const visualSignRoutePath = '/sign/visual';
const redactRoutePath = '/redact';

List<GoRoute> buildFormSignRoutes({
  GlobalKey<NavigatorState>? parentNavigatorKey,
}) {
  return [
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: fillFormRoutePath,
      builder: (context, state) => fillFormScreenFromExtra(state.extra),
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: visualSignRoutePath,
      builder: (context, state) {
        final args = PdfDocumentRouteArgs.tryParse(state.extra);
        return VisualSignScreen(
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: placeImageRoutePath,
      builder: (context, state) {
        final args = PdfDocumentRouteArgs.tryParse(state.extra);
        return PlaceImageScreen(
          initialFile: args?.file,
          initialPassword: args?.password,
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: editTextRoutePath,
      builder: (context, state) => editTextScreenFromExtra(state.extra),
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: drawInkRoutePath,
      builder: (context, state) => drawInkScreenFromExtra(state.extra),
    ),
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: redactRoutePath,
      builder: (context, state) => const RedactScreen(),
    ),
  ];
}
