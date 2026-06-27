import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/infrastructure/pdf/stamp/pdf_stamp_engine.dart';

/// Result of scanning a PDF for a header/footer added by Document Studio.
class HeaderFooterInspection {
  const HeaderFooterInspection({this.stampedPages = const [], this.spec});

  static const none = HeaderFooterInspection();

  /// Pages that currently carry the stamp.
  final List<int> stampedPages;

  /// Settings used last time, when readable.
  final HeaderFooterSpec? spec;

  bool get hasExisting => stampedPages.isNotEmpty;
}

/// Page geometry and document info needed to lay out a header/footer.
class HeaderFooterDocument {
  const HeaderFooterDocument({required this.pageSizesPt, required this.info});

  /// Display (rotated, cropped) size of every page.
  final List<(double, double)> pageSizesPt;
  final HfDocInfo info;
}

/// Headers & footers (and page numbers, as a preset) written with the
/// pure-Dart [PdfStampEngine]: tagged Form XObjects that can be found again,
/// replaced or removed, with the spec stored in the catalog for editing.
class PdfHeaderFooterService {
  const PdfHeaderFooterService({this.kind = PdfStampKind.headerFooter});

  /// Stamp family: [PdfStampKind.headerFooter] or [PdfStampKind.pageNumbers].
  final String kind;

  Future<(HeaderFooterDocument, HeaderFooterInspection)> load(
    Uint8List pdf, {
    required String fileName,
  }) async {
    final found = await PdfStampEngine.inspect(pdf);
    HeaderFooterSpec? spec;
    final json = found.settingsByKind[kind];
    if (json != null) {
      try {
        spec = HeaderFooterSpec.fromJson(
          (jsonDecode(json) as Map).cast<String, Object?>(),
        );
      } catch (_) {}
    }
    return (
      HeaderFooterDocument(
        pageSizesPt: found.pageSizesPt,
        info: HfDocInfo(
          fileName: fileName,
          pageCount: found.pageCount,
          title: found.title,
          author: found.author,
          subject: found.subject,
        ),
      ),
      HeaderFooterInspection(stampedPages: found.pagesWith(kind), spec: spec),
    );
  }

  /// Burns [spec], replacing any previous stamp of this [kind].
  Future<Uint8List> apply(
    Uint8List pdf, {
    required HeaderFooterSpec spec,
    required HfDocInfo info,
  }) {
    if (!spec.hasContent) throw ArgumentError('Header/footer is empty');
    return PdfStampEngine.applyHeaderFooter(
      pdf,
      spec: spec,
      info: info.withNow(DateTime.now()),
      kind: kind,
      settingsJson: jsonEncode(spec.toJson()),
    );
  }

  Future<Uint8List> remove(Uint8List pdf) => PdfStampEngine.remove(pdf, kind);
}
