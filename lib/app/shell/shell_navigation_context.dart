import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preserves open-document context when switching Home ↔ Tools in the shell.
@immutable
class ShellNavigationContext {
  const ShellNavigationContext({this.activeDocument, this.toolReturnViewer});

  final PdfDocumentRouteArgs? activeDocument;
  final ViewerRouteArgs? toolReturnViewer;

  ShellNavigationContext copyWith({
    PdfDocumentRouteArgs? activeDocument,
    ViewerRouteArgs? toolReturnViewer,
    bool clearToolReturn = false,
  }) {
    return ShellNavigationContext(
      activeDocument: activeDocument ?? this.activeDocument,
      toolReturnViewer: clearToolReturn
          ? null
          : (toolReturnViewer ?? this.toolReturnViewer),
    );
  }
}

class ShellNavigationContextNotifier extends Notifier<ShellNavigationContext> {
  @override
  ShellNavigationContext build() => const ShellNavigationContext();

  void setActiveDocument(PdfDocumentRouteArgs? document) {
    if (document == null) {
      state = ShellNavigationContext(toolReturnViewer: state.toolReturnViewer);
      return;
    }
    state = state.copyWith(activeDocument: document);
  }

  void rememberToolReturnFromViewer(ViewerRouteArgs viewer) {
    state = state.copyWith(
      activeDocument: PdfDocumentRouteArgs(
        file: viewer.file,
        password: viewer.password,
      ),
      toolReturnViewer: viewer,
    );
  }

  void clearToolReturn() {
    state = state.copyWith(clearToolReturn: true);
  }
}

final shellNavigationContextProvider =
    NotifierProvider<ShellNavigationContextNotifier, ShellNavigationContext>(
      ShellNavigationContextNotifier.new,
    );
