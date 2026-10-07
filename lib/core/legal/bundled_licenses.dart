import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of bundled fonts to Flutter's licence registry, so
/// Settings → Licenses lists them next to the Dart packages.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, notice, texts) in const [
      (
        ['Font library (Edit, Word, PowerPoint)'],
        'assets/fonts/library/NOTICE.txt',
        [
          'assets/fonts/library/OFL.txt',
          'assets/fonts/library/Apache-2.0.txt',
          'assets/fonts/library/UFL-1.0.txt',
        ],
      ),
      (
        ['Signature fonts'],
        'assets/fonts/signature/NOTICE.txt',
        ['assets/fonts/signature/OFL.txt'],
      ),
      (
        ['Liberation fonts'],
        'assets/fonts/text/LICENSE-Liberation.txt',
        <String>[],
      ),
      (['DejaVu fonts'], 'assets/fonts/text/LICENSE-DejaVu.txt', <String>[]),
    ]) {
      try {
        final parts = [
          await rootBundle.loadString(notice),
          for (final t in texts) await rootBundle.loadString(t),
        ];
        yield LicenseEntryWithLineBreaks(packages, parts.join('\n\n'));
      } catch (_) {
        // Not bundled in this build.
      }
    }
  });
}
