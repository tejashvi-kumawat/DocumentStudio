import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:pdfrx/pdfrx.dart' show PdfLinkHandlerParams;

/// Follows an in-document link: internal dest → [controller.goToDest], else URL.
Future<void> handlePdfViewerLinkTap({
  required BuildContext context,
  required PdfViewerController controller,
  required PdfLink link,
}) async {
  final dest = link.dest;
  if (dest != null) {
    await controller.goToDest(dest);
    return;
  }
  final uri = link.url;
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open link: $uri')));
  }
}
