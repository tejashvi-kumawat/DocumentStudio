import 'package:document_studio/core/desktop/pdf_default_app_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ours = 'com.documentstudio.document_studio.desktop';

  test('Always command uses the desktop id, or the flatpak id', () {
    expect(
      xdgMimeSetDefaultCommand(pdfHandlerDesktopFile()),
      'xdg-mime default com.documentstudio.document_studio.desktop application/pdf',
    );
    expect(xdgMimeSetDefaultArgs(pdfHandlerDesktopFile()), [
      'default',
      'com.documentstudio.document_studio.desktop',
      'application/pdf',
    ]);
    expect(
      xdgMimeSetDefaultCommand(
        pdfHandlerDesktopFile(flatpakId: 'com.example.DocumentStudio'),
      ),
      'xdg-mime default com.example.DocumentStudio.desktop application/pdf',
    );
  });

  test('saved choice skips the query and the dialog', () async {
    var queried = false;
    final action = await decidePdfDefaultPrompt(
      isLinux: true,
      savedChoice: kPdfDefaultChoiceNotNow,
      desktopFile: ours,
      queryDefault: () async {
        queried = true;
        return 'org.gnome.Papers.desktop';
      },
    );
    expect(action, PdfDefaultPromptAction.skip);
    expect(queried, isFalse);

    final alwaysSaved = await decidePdfDefaultPrompt(
      isLinux: true,
      savedChoice: kPdfDefaultChoiceAlways,
      desktopFile: ours,
      queryDefault: () async {
        queried = true;
        return 'org.gnome.Papers.desktop';
      },
    );
    expect(alwaysSaved, PdfDefaultPromptAction.skip);
    expect(queried, isFalse);
  });

  test('already the default does not show the dialog', () async {
    final action = await decidePdfDefaultPrompt(
      isLinux: true,
      savedChoice: null,
      desktopFile: ours,
      queryDefault: () async => '$ours\n',
    );
    expect(action, PdfDefaultPromptAction.rememberAlreadyDefault);
    expect(isOurPdfDefaultHandler(' $ours\n', ours), isTrue);
  });

  test(
    'another default handler shows the dialog once there is no choice',
    () async {
      final action = await decidePdfDefaultPrompt(
        isLinux: true,
        savedChoice: null,
        desktopFile: ours,
        queryDefault: () async => 'org.gnome.Papers.desktop',
      );
      expect(action, PdfDefaultPromptAction.showDialog);
    },
  );

  test('Not now does not run xdg-mime default', () async {
    var setDefault = false;
    String? saved;
    await applyPdfDefaultChoice(
      always: false,
      setDefault: () async {
        setDefault = true;
      },
      save: (choice) async {
        saved = choice;
      },
    );
    expect(setDefault, isFalse);
    expect(saved, kPdfDefaultChoiceNotNow);
  });

  test('Always runs the setter once and stores the choice', () async {
    var sets = 0;
    String? saved;
    await applyPdfDefaultChoice(
      always: true,
      setDefault: () async {
        sets++;
      },
      save: (choice) async {
        saved = choice;
      },
    );
    expect(sets, 1);
    expect(saved, kPdfDefaultChoiceAlways);
  });

  test('non-Linux never asks', () async {
    var queried = false;
    final action = await decidePdfDefaultPrompt(
      isLinux: false,
      savedChoice: null,
      desktopFile: ours,
      queryDefault: () async {
        queried = true;
        return '';
      },
    );
    expect(action, PdfDefaultPromptAction.skip);
    expect(queried, isFalse);
  });
}
