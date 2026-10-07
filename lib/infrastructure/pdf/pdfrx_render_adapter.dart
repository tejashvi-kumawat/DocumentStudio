import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:pdfrx/pdfrx.dart';

/// Opens go through [PdfDocumentCache]: validating a file before showing it
/// leaves the parsed document warm for the viewer instead of parsing twice.
class PdfrxRenderAdapter implements PdfRenderPort {
  @override
  Future<PdfDocumentInfo> loadInfo(
    LocalFileRef file, {
    String? password,
  }) async {
    final lease = await _acquire(file, password: password);
    try {
      // pdfrx 2.x no longer exposes Info dictionary via [PdfDocument.metadata].
      return PdfDocumentInfo(
        pageCount: lease.document.pages.length,
        encrypted: lease.document.isEncrypted,
      );
    } finally {
      lease.release();
    }
  }

  @override
  Future<bool> validateOpenable(LocalFileRef file, {String? password}) async {
    try {
      final lease = await _acquire(file, password: password);
      lease.release();
      return true;
    } on DocumentStudioError {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> extractPlainText(LocalFileRef file, {String? password}) async {
    final lease = await _acquire(file, password: password, allPages: true);
    try {
      final buf = StringBuffer();
      for (final page in lease.document.pages) {
        final text = await page.loadText();
        if (text == null) continue;
        final full = text.fullText.trim();
        if (full.isEmpty) continue;
        if (buf.isNotEmpty) buf.writeln();
        buf.write(full);
      }
      return buf.toString();
    } finally {
      lease.release();
    }
  }

  Future<PdfDocumentLease> _acquire(
    LocalFileRef file, {
    String? password,
    bool allPages = false,
  }) async {
    try {
      return await PdfDocumentCache.instance.acquire(
        file.path,
        password: password,
        loadAllPages: allPages,
      );
    } on PdfPasswordException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.passwordRequired,
        message: e.toString(),
        cause: e,
      );
    } on PdfException catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password')) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.passwordRequired,
          message: e.toString(),
          cause: e,
        );
      }
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: e.toString(),
        cause: e,
      );
    } on DocumentStudioError {
      rethrow;
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.renderFailed,
        message: e.toString(),
        cause: e,
      );
    }
  }
}
