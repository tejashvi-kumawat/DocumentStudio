import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/pdf_accessibility_checker.dart';

/// PDF/A readiness report (what blocks long-term archiving). This reports
/// problems; it does not convert. A real conversion needs embedded fonts and
/// a colour profile, which only the original authoring tool can supply.
List<A11yFinding> checkPdfArchiveReadiness(Uint8List bytes) {
  final out = <A11yFinding>[];
  try {
    final doc = PdfEditDocument.open(bytes);
    if (doc.isEncrypted) {
      out.add(
        const A11yFinding(
          A11ySeverity.fail,
          'Encryption',
          'PDF/A forbids encryption. Remove the password first.',
        ),
      );
    }
    final cat = doc.catalog;

    // XMP identification.
    final meta = doc.resolve(cat['Metadata']);
    var claims = false;
    if (meta is PdfStream) {
      final text = String.fromCharCodes(meta.data.take(60000));
      claims = text.contains('pdfaid:part');
    }
    out.add(
      claims
          ? const A11yFinding(
              A11ySeverity.pass,
              'PDF/A identification',
              'The file declares a PDF/A part.',
            )
          : const A11yFinding(
              A11ySeverity.warning,
              'PDF/A identification',
              'No pdfaid entry in the metadata, so it is not marked as PDF/A.',
            ),
    );

    // Output intent (colour profile).
    out.add(
      cat.containsKey('OutputIntents')
          ? const A11yFinding(
              A11ySeverity.pass,
              'Colour profile',
              'An output intent is present.',
            )
          : const A11yFinding(
              A11ySeverity.warning,
              'Colour profile',
              'No output intent / ICC profile for device colours.',
            ),
    );

    // Scripts and embedded media.
    final names = doc.dictOf(cat['Names']);
    final risky =
        cat.containsKey('OpenAction') ||
        cat.containsKey('AA') ||
        (names != null && names.containsKey('JavaScript'));
    out.add(
      risky
          ? const A11yFinding(
              A11ySeverity.fail,
              'Scripts and actions',
              'JavaScript or automatic actions are not allowed in PDF/A.',
            )
          : const A11yFinding(
              A11ySeverity.pass,
              'Scripts and actions',
              'No scripts found.',
            ),
    );

    // Fonts must be embedded.
    final seen = <int>{};
    var fonts = 0;
    var unembedded = 0;
    for (var p = 1; p <= doc.pageCount; p++) {
      final page = doc.pageDict(p);
      final res = doc.dictOf(doc.inherited(page, 'Resources'));
      final fd = doc.dictOf(res?['Font']);
      if (fd == null) continue;
      for (final v in fd.entries.values) {
        if (v is PdfRef && !seen.add(v.num)) continue;
        final f = doc.dictOf(v);
        if (f == null) continue;
        fonts++;
        final sub = f.nameOf('Subtype');
        if (sub == 'Type3') continue;
        PdfDict? desc = doc.dictOf(f['FontDescriptor']);
        if (sub == 'Type0') {
          final df = doc.resolve(f['DescendantFonts']);
          if (df is PdfArray && df.items.isNotEmpty) {
            desc = doc.dictOf(doc.dictOf(df.items.first)?['FontDescriptor']);
          }
        }
        final embedded =
            desc != null &&
            (desc.containsKey('FontFile') ||
                desc.containsKey('FontFile2') ||
                desc.containsKey('FontFile3'));
        if (!embedded) unembedded++;
      }
    }
    if (fonts > 0) {
      out.add(
        unembedded == 0
            ? A11yFinding(
                A11ySeverity.pass,
                'Fonts',
                'All $fonts fonts are embedded.',
              )
            : A11yFinding(
                A11ySeverity.fail,
                'Fonts',
                '$unembedded of $fonts fonts are not embedded (this includes '
                    'text added with the standard Helvetica/Times/Courier fonts).',
              ),
      );
    }
  } catch (_) {
    out.add(
      const A11yFinding(
        A11ySeverity.warning,
        'Check incomplete',
        'The file could not be fully read.',
      ),
    );
  }
  return out;
}
