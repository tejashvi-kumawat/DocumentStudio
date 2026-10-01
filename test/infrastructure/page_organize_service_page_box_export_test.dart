import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/organize/page_organize_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStructure extends Mock implements PdfStructurePort {}

class _MockStorage extends Mock implements FileStoragePort {}

void main() {
  late _MockStructure structure;
  late _MockStorage storage;
  late PageOrganizeService service;
  late Directory tempDir;

  const input = LocalFileRef(path: '/docs/locked.pdf', displayName: 'locked.pdf');
  final exportedBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);

  setUpAll(() {
    registerFallbackValue(
      const LocalFileRef(path: 'fallback', displayName: 'fallback.pdf'),
    );
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(PdfCropMarginPreset.small);
    registerFallbackValue(PdfPaperSize.a4);
  });

  setUp(() async {
    structure = _MockStructure();
    storage = _MockStorage();
    service = PageOrganizeService(
      structure: structure,
      storage: storage,
      jobs: JobRunner(),
    );
    tempDir = await Directory.systemTemp.createTemp('ds_page_box_svc_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> stubSaveFlow(String tempOut, String savePath) async {
    when(
      () => storage.createTempFile(
        prefix: any(named: 'prefix'),
        suffix: any(named: 'suffix'),
      ),
    ).thenAnswer((_) async => tempOut);
    when(
      () => storage.readBytes(any()),
    ).thenAnswer((_) async => exportedBytes);
    when(
      () => storage.pickSavePath(
        suggestedName: any(named: 'suggestedName'),
        bytes: any(named: 'bytes'),
        allowedExtensions: any(named: 'allowedExtensions'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async => savePath);
    when(
      () => storage.writeAtomic(
        destinationPath: any(named: 'destinationPath'),
        writeToTemp: any(named: 'writeToTemp'),
      ),
    ).thenAnswer((invocation) async {
      final writeToTemp = invocation.namedArguments[#writeToTemp]
          as Future<void> Function(String tempPath);
      final dest = invocation.namedArguments[#destinationPath] as String;
      final staging = '$dest.staging';
      await writeToTemp(staging);
      await File(dest).writeAsBytes(await File(staging).readAsBytes());
    });
  }

  group('cropPagesAndPromptSave', () {
    test('forwards passwordsByPath entry as cropPages password', () async {
      final tempOut = '${tempDir.path}/crop-temp.pdf';
      final savePath = '${tempDir.path}/cropped-out.pdf';
      await stubSaveFlow(tempOut, savePath);
      await File(tempOut).writeAsBytes(exportedBytes);

      when(
        () => structure.cropPages(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          margin: any(named: 'margin'),
          outputPath: any(named: 'outputPath'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((invocation) async {
        final outputPath = invocation.namedArguments[#outputPath] as String;
        await File(outputPath).writeAsBytes(exportedBytes);
        return LocalFileRef(path: outputPath, displayName: 'crop.pdf');
      });

      await service.cropPagesAndPromptSave(
        input: input,
        pageNumbers1Based: {1, 3},
        margin: PdfCropMarginPreset.medium,
        suggestedName: 'cropped-locked.pdf',
        passwordsByPath: {'/docs/locked.pdf': 'crop-secret'},
      );

      final captured = verify(
        () => structure.cropPages(
          input: captureAny(named: 'input'),
          pageNumbers1Based: captureAny(named: 'pageNumbers1Based'),
          margin: captureAny(named: 'margin'),
          outputPath: captureAny(named: 'outputPath'),
          password: captureAny(named: 'password'),
        ),
      ).captured;

      expect((captured[0] as LocalFileRef).path, input.path);
      expect(captured[1], {1, 3});
      expect(captured[2], PdfCropMarginPreset.medium);
      expect(captured[4], 'crop-secret');
    });

    test('passes null password when passwordsByPath missing path', () async {
      final tempOut = '${tempDir.path}/crop-temp2.pdf';
      final savePath = '${tempDir.path}/cropped-out2.pdf';
      await stubSaveFlow(tempOut, savePath);
      await File(tempOut).writeAsBytes(exportedBytes);

      when(
        () => structure.cropPages(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          margin: any(named: 'margin'),
          outputPath: any(named: 'outputPath'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((invocation) async {
        final outputPath = invocation.namedArguments[#outputPath] as String;
        await File(outputPath).writeAsBytes(exportedBytes);
        return LocalFileRef(path: outputPath, displayName: 'crop.pdf');
      });

      await service.cropPagesAndPromptSave(
        input: input,
        pageNumbers1Based: {2},
        margin: PdfCropMarginPreset.small,
        suggestedName: 'cropped-locked.pdf',
        passwordsByPath: const {'/other.pdf': 'unused'},
      );

      final password = verify(
        () => structure.cropPages(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          margin: any(named: 'margin'),
          outputPath: any(named: 'outputPath'),
          password: captureAny(named: 'password'),
        ),
      ).captured.single;

      expect(password, isNull);
    });
  });

  group('setPageSizeAndPromptSave', () {
    test('forwards passwordsByPath entry as setPageSize password', () async {
      final tempOut = '${tempDir.path}/resize-temp.pdf';
      final savePath = '${tempDir.path}/resized-out.pdf';
      await stubSaveFlow(tempOut, savePath);
      await File(tempOut).writeAsBytes(exportedBytes);

      when(
        () => structure.setPageSize(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          paperSize: any(named: 'paperSize'),
          outputPath: any(named: 'outputPath'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((invocation) async {
        final outputPath = invocation.namedArguments[#outputPath] as String;
        await File(outputPath).writeAsBytes(exportedBytes);
        return LocalFileRef(path: outputPath, displayName: 'resize.pdf');
      });

      await service.setPageSizeAndPromptSave(
        input: input,
        pageNumbers1Based: {2},
        paperSize: PdfPaperSize.legal,
        suggestedName: 'resized-locked.pdf',
        passwordsByPath: {'/docs/locked.pdf': 'resize-secret'},
      );

      final captured = verify(
        () => structure.setPageSize(
          input: captureAny(named: 'input'),
          pageNumbers1Based: captureAny(named: 'pageNumbers1Based'),
          paperSize: captureAny(named: 'paperSize'),
          outputPath: captureAny(named: 'outputPath'),
          password: captureAny(named: 'password'),
        ),
      ).captured;

      expect((captured[0] as LocalFileRef).path, input.path);
      expect(captured[1], {2});
      expect(captured[2], PdfPaperSize.legal);
      expect(captured[4], 'resize-secret');
    });

    test('skips empty passwordsByPath value for resize export', () async {
      final tempOut = '${tempDir.path}/resize-temp2.pdf';
      final savePath = '${tempDir.path}/resized-out2.pdf';
      await stubSaveFlow(tempOut, savePath);
      await File(tempOut).writeAsBytes(exportedBytes);

      when(
        () => structure.setPageSize(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          paperSize: any(named: 'paperSize'),
          outputPath: any(named: 'outputPath'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((invocation) async {
        final outputPath = invocation.namedArguments[#outputPath] as String;
        await File(outputPath).writeAsBytes(exportedBytes);
        return LocalFileRef(path: outputPath, displayName: 'resize.pdf');
      });

      await service.setPageSizeAndPromptSave(
        input: input,
        pageNumbers1Based: {1},
        paperSize: PdfPaperSize.a4,
        suggestedName: 'resized-locked.pdf',
        passwordsByPath: {'/docs/locked.pdf': ''},
      );

      final password = verify(
        () => structure.setPageSize(
          input: any(named: 'input'),
          pageNumbers1Based: any(named: 'pageNumbers1Based'),
          paperSize: any(named: 'paperSize'),
          outputPath: any(named: 'outputPath'),
          password: captureAny(named: 'password'),
        ),
      ).captured.single;

      expect(password, isNull);
    });
  });
}
