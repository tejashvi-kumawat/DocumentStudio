import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/document_workspace/workspace_inspector_panel.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_protect_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_unlock_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/security/protect_screen.dart';
import 'package:document_studio/features/security/unlock_screen.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage implements FileStoragePort {
  @override
  Future<String> createTempFile({
    required String prefix,
    String? suffix,
  }) async =>
      '/tmp/$prefix${suffix ?? '.pdf'}';

  @override
  Future<LocalFileRef?> pickSaveFile({
    String? suggestedName,
    List<String>? allowedExtensions,
  }) async {
    return LocalFileRef(
      path: '/tmp/${suggestedName ?? 'out.pdf'}',
      displayName: suggestedName ?? 'out.pdf',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingEncrypt implements PdfEncryptPort {
  int encryptCalls = 0;
  int decryptCalls = 0;
  String? lastUserPassword;
  String? lastDecryptPassword;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<LocalFileRef> encryptWithPassword({
    required LocalFileRef input,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    String? inputPassword,
    PdfEncryptPermissions permissions = const PdfEncryptPermissions(),
  }) async {
    encryptCalls++;
    lastUserPassword = userPassword;
    return LocalFileRef(path: outputPath, displayName: 'protected.pdf');
  }

  @override
  Future<LocalFileRef> decryptToFile({
    required LocalFileRef input,
    required String outputPath,
    required String password,
  }) async {
    decryptCalls++;
    lastDecryptPassword = password;
    return LocalFileRef(path: outputPath, displayName: 'unlocked.pdf');
  }
}

void main() {
  const file = LocalFileRef(path: '/tmp/sec.pdf', displayName: 'sec.pdf');

  testWidgets(
    'Tools ProtectScreen: enter password and Apply calls encrypt',
    (tester) async {
      final encrypt = _RecordingEncrypt();
      await tester.binding.setSurfaceSize(const Size(480, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileStorageProvider.overrideWithValue(_FakeStorage()),
            pdfEncryptPortProvider.overrideWithValue(encrypt),
          ],
          child: MaterialApp(
            home: ProtectScreen(
              deps: ProtectDeps(
                fileStorage: _FakeStorage(),
                encryptPort: encrypt,
              ),
              initialFile: file,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byKey(const Key('protect_user_password')),
        'secret123',
      );
      await tester.enterText(
        find.byKey(const Key('protect_confirm_password')),
        'secret123',
      );
      await tester.pump();

      await tester.tap(find.text('Encrypt & save as'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(encrypt.encryptCalls, 1);
      expect(encrypt.lastUserPassword, 'secret123');
    },
  );

  testWidgets(
    'Tools UnlockScreen: enter password and Apply calls decrypt',
    (tester) async {
      final encrypt = _RecordingEncrypt();
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileStorageProvider.overrideWithValue(_FakeStorage()),
            pdfEncryptPortProvider.overrideWithValue(encrypt),
          ],
          child: MaterialApp(
            home: UnlockScreen(
              deps: UnlockDeps(
                fileStorage: _FakeStorage(),
                encryptPort: encrypt,
              ),
              initialFile: file,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byKey(const Key('unlock_password')),
        'open-me',
      );
      await tester.pump();

      await tester.tap(find.text('Decrypt & save as'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(encrypt.decryptCalls, 1);
      expect(encrypt.lastDecryptPassword, 'open-me');
    },
  );

  testWidgets(
    'Viewer protect panel: password + Apply encrypts open PDF',
    (tester) async {
      final encrypt = _RecordingEncrypt();
      final tabs = DocumentTabsController()..openDocument(file);

      await tester.binding.setSurfaceSize(const Size(420, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileStorageProvider.overrideWithValue(_FakeStorage()),
            pdfEncryptPortProvider.overrideWithValue(encrypt),
            documentTabsControllerProvider.overrideWithValue(tabs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ViewerProtectPanel(
                handoff: PdfViewerDocumentHandoff(file: file),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('viewer_protect_user_password')),
        'viewer-pw',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('viewer_protect_apply')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        if (encrypt.encryptCalls > 0) break;
      }

      expect(encrypt.encryptCalls, 1);
      expect(encrypt.lastUserPassword, 'viewer-pw');
    },
  );

  testWidgets(
    'Viewer unlock panel: password + Apply decrypts open PDF',
    (tester) async {
      final encrypt = _RecordingEncrypt();
      final tabs = DocumentTabsController()..openDocument(file);

      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileStorageProvider.overrideWithValue(_FakeStorage()),
            pdfEncryptPortProvider.overrideWithValue(encrypt),
            documentTabsControllerProvider.overrideWithValue(tabs),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ViewerUnlockPanel(
                handoff: PdfViewerDocumentHandoff(
                  file: file,
                  password: 'cached',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Hand-off seeds the field; overwrite then Apply.
      await tester.enterText(
        find.byKey(const Key('viewer_unlock_password')),
        'unlock-pw',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('viewer_unlock_apply')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        if (encrypt.decryptCalls > 0) break;
      }

      expect(encrypt.decryptCalls, 1);
      expect(encrypt.lastDecryptPassword, 'unlock-pw');
    },
  );

  testWidgets(
    'Workspace Protect and Unlock taps launch viewer tools',
    (tester) async {
      final launched = <ViewerToolId>[];
      final page = OrganizePageRef.fromFilePage(file, 1);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 700,
                child: WorkspaceInspectorPanel(
                  page: page,
                  selectionCount: 1,
                  passwordsByPath: const {},
                  documentTools: [
                    WorkspaceDocumentToolItem(
                      id: 'protect',
                      label: 'Protect',
                      icon: Icons.lock_outline,
                      onPressed: () => launched.add(ViewerToolId.protect),
                    ),
                    WorkspaceDocumentToolItem(
                      id: 'unlock',
                      label: 'Unlock',
                      icon: Icons.lock_open_outlined,
                      onPressed: () => launched.add(ViewerToolId.unlock),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('workspace_doc_tool_protect')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('workspace_doc_tool_unlock')));
      await tester.pump();

      expect(launched, [ViewerToolId.protect, ViewerToolId.unlock]);
    },
  );
}
