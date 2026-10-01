import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/pdf/pdf_open_limits.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_open_validation.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePdfRenderPort implements PdfRenderPort {
  _FakePdfRenderPort(this._handler);

  final Future<PdfDocumentInfo> Function(
    LocalFileRef file, {
    String? password,
  }) _handler;

  @override
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password}) =>
      _handler(file, password: password);

  @override
  Future<bool> validateOpenable(LocalFileRef file, {String? password}) async {
    await _handler(file, password: password);
    return true;
  }

  @override
  Future<String> extractPlainText(LocalFileRef file, {String? password}) async =>
      '';
}

void main() {
  const file = LocalFileRef(path: '/locked.pdf', displayName: 'locked.pdf');

  group('validatePdfViewerDocumentOpen', () {
    test('succeeds without prompt when document opens', () async {
      var prompts = 0;
      final result = await validatePdfViewerDocumentOpen(
        pdf: _FakePdfRenderPort((f, {password}) async {
          expect(f.path, file.path);
          expect(password, isNull);
          return const PdfDocumentInfo(pageCount: 3);
        }),
        file: file,
        promptPassword: () async {
          prompts++;
          return 'unused';
        },
      );

      expect(result.success, isTrue);
      expect(result.password, isNull);
      expect(prompts, 0);
    });

    test('prompts and retries when password required', () async {
      var attempts = 0;
      var prompts = 0;

      final result = await validatePdfViewerDocumentOpen(
        pdf: _FakePdfRenderPort((f, {password}) async {
          attempts++;
          if (attempts == 1) {
            expect(password, isNull);
            throw const DocumentStudioError(
              code: DocumentStudioErrorCode.passwordRequired,
              message: 'Password required',
            );
          }
          expect(password, 'good');
          return const PdfDocumentInfo(pageCount: 1);
        }),
        file: file,
        promptPassword: () async {
          prompts++;
          return 'good';
        },
      );

      expect(result.success, isTrue);
      expect(result.password, 'good');
      expect(prompts, 1);
      expect(attempts, 2);
    });

    test('rejects oversize file before engine open ([DS-EDGE-004])', () async {
      final dir = Directory.systemTemp.createTempSync('ds_open_val_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final big = File('${dir.path}/big.pdf')..writeAsBytesSync(List.filled(4096, 0));
      final bigRef = LocalFileRef(path: big.path, displayName: 'big.pdf');

      var engineCalls = 0;
      final result = await validatePdfViewerDocumentOpen(
        pdf: _FakePdfRenderPort((f, {password}) async {
          engineCalls++;
          return const PdfDocumentInfo(pageCount: 1);
        }),
        file: bigRef,
        promptPassword: () async => null,
        maxOpenBytes: 1024,
      );

      expect(result.success, isFalse);
      expect(result.error?.code, DocumentStudioErrorCode.outOfMemory);
      expect(engineCalls, 0);
    });

    test('returns error when user cancels password', () async {
      final result = await validatePdfViewerDocumentOpen(
        pdf: _FakePdfRenderPort((f, {password}) async {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.passwordRequired,
            message: 'Password required',
          );
        }),
        file: file,
        promptPassword: () async => null,
      );

      expect(result.success, isFalse);
      expect(
        result.error?.code,
        DocumentStudioErrorCode.passwordRequired,
      );
    });
  });
}
