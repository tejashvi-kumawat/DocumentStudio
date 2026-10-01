import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GTK / Flatpak desktop id for Document Studio.
const kDocumentStudioDesktopId = 'com.documentstudio.document_studio';

const kPdfMimeType = 'application/pdf';

/// Persisted for this install. Any value means the prompt is finished.
const kPdfDefaultPromptPrefKey = 'linux_pdf_default_handler_prompt_v1';

const kPdfDefaultChoiceNotNow = 'not_now';
const kPdfDefaultChoiceAlways = 'always';
const kPdfDefaultChoiceAlreadyDefault = 'already_default';

/// What startup should do after reading the saved choice and, at most once,
/// the current default handler.
enum PdfDefaultPromptAction {
  /// Saved choice exists, this is not Linux, or the handler could not be read.
  /// Do not run `xdg-mime` and do not show a dialog.
  skip,

  /// We are already the default. Remember that and do not ask.
  rememberAlreadyDefault,

  /// Not the default, and the user has not answered yet.
  showDialog,
}

/// Desktop file passed to `xdg-mime`. Flatpak exports `<FLATPAK_ID>.desktop`.
String pdfHandlerDesktopFile({String? flatpakId}) {
  final id = flatpakId?.trim();
  final resolved = (id != null && id.isNotEmpty)
      ? id
      : kDocumentStudioDesktopId;
  return '$resolved.desktop';
}

/// Exact argv for `xdg-mime` when the user chooses Always.
List<String> xdgMimeSetDefaultArgs(String desktopFile) => [
  'default',
  desktopFile,
  kPdfMimeType,
];

/// Exact command Always runs.
String xdgMimeSetDefaultCommand(String desktopFile) =>
    'xdg-mime default $desktopFile $kPdfMimeType';

bool isOurPdfDefaultHandler(String? currentDefault, String desktopFile) {
  if (currentDefault == null) return false;
  final current = currentDefault.trim();
  if (current.isEmpty) return false;
  return current == desktopFile || current.endsWith('/$desktopFile');
}

/// [savedChoice] set → [PdfDefaultPromptAction.skip] and [queryDefault] is
/// not called. [queryDefault] returns null when `xdg-mime query` failed.
Future<PdfDefaultPromptAction> decidePdfDefaultPrompt({
  required bool isLinux,
  required String? savedChoice,
  required String desktopFile,
  required Future<String?> Function() queryDefault,
}) async {
  if (!isLinux) return PdfDefaultPromptAction.skip;
  if (savedChoice != null && savedChoice.isNotEmpty) {
    return PdfDefaultPromptAction.skip;
  }
  final current = await queryDefault();
  if (current == null) return PdfDefaultPromptAction.skip;
  if (isOurPdfDefaultHandler(current, desktopFile)) {
    return PdfDefaultPromptAction.rememberAlreadyDefault;
  }
  return PdfDefaultPromptAction.showDialog;
}

/// Records Always (after [setDefault]) or Not now (without changing the default).
Future<void> applyPdfDefaultChoice({
  required bool always,
  required Future<void> Function() setDefault,
  required Future<void> Function(String choice) save,
}) async {
  if (always) {
    try {
      await setDefault();
    } catch (_) {
      // The choice is still stored so a failed set does not ask again.
    }
    await save(kPdfDefaultChoiceAlways);
    return;
  }
  await save(kPdfDefaultChoiceNotNow);
}

/// Asks once per install, after the cold-start splash, when this process is
/// not already the PDF default handler.
Future<void> offerLinuxPdfDefaultPrompt({
  required BuildContext? Function() navigatorContext,
  Duration waitBeforePrompt = const Duration(milliseconds: 1480),
}) async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  if (kIsWeb || !Platform.isLinux) return;

  final prefs = await SharedPreferences.getInstance();
  final desktopFile = pdfHandlerDesktopFile(
    flatpakId: Platform.environment['FLATPAK_ID'],
  );
  final action = await decidePdfDefaultPrompt(
    isLinux: true,
    savedChoice: prefs.getString(kPdfDefaultPromptPrefKey),
    desktopFile: desktopFile,
    queryDefault: () => _queryPdfDefaultDesktop(),
  );
  switch (action) {
    case PdfDefaultPromptAction.skip:
      return;
    case PdfDefaultPromptAction.rememberAlreadyDefault:
      await prefs.setString(
        kPdfDefaultPromptPrefKey,
        kPdfDefaultChoiceAlreadyDefault,
      );
      return;
    case PdfDefaultPromptAction.showDialog:
      break;
  }

  if (waitBeforePrompt > Duration.zero) {
    await Future<void>.delayed(waitBeforePrompt);
  }
  var ctx = navigatorContext();
  if (ctx == null || !ctx.mounted) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ctx = navigatorContext();
  }
  if (ctx == null || !ctx.mounted) return;

  final bool? always;
  try {
    always = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Open PDF files with Document Studio?'),
          content: const Text(
            'Document Studio can open PDF files from the file manager. '
            'You can change this later in system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Always'),
            ),
          ],
        );
      },
    );
  } catch (_) {
    return;
  }
  // Not now, or any other dismiss: leave the current default alone and
  // do not ask again this install.
  if (always != true) {
    await prefs.setString(kPdfDefaultPromptPrefKey, kPdfDefaultChoiceNotNow);
    return;
  }

  await applyPdfDefaultChoice(
    always: true,
    setDefault: () => _setPdfDefaultDesktop(desktopFile),
    save: (choice) => prefs.setString(kPdfDefaultPromptPrefKey, choice),
  );
}

/// `xdg-mime query default application/pdf`. Null when the tool fails.
Future<String?> _queryPdfDefaultDesktop() async {
  try {
    final result = await Process.run('xdg-mime', [
      'query',
      'default',
      kPdfMimeType,
    ]);
    if (result.exitCode != 0) return null;
    final out = result.stdout;
    return out is String ? out : '$out';
  } on ProcessException {
    return null;
  }
}

Future<void> _setPdfDefaultDesktop(String desktopFile) {
  return Process.run('xdg-mime', xdgMimeSetDefaultArgs(desktopFile));
}
