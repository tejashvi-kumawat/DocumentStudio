import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';

/// Acrobat-style permission bundles for [ProtectScreen] (DS-SEC-002).
enum ProtectPermissionPreset {
  viewOnly,
  printOnly,
  printAndCopy,
  fullAccess,
  custom,
}

extension ProtectPermissionPresetLabels on ProtectPermissionPreset {
  String get label => switch (this) {
        ProtectPermissionPreset.viewOnly => 'View only',
        ProtectPermissionPreset.printOnly => 'Print only',
        ProtectPermissionPreset.printAndCopy => 'Print & copy',
        ProtectPermissionPreset.fullAccess => 'Full access',
        ProtectPermissionPreset.custom => 'Custom',
      };

  String get subtitle => switch (this) {
        ProtectPermissionPreset.viewOnly =>
          'No printing, copying, editing, or comments.',
        ProtectPermissionPreset.printOnly =>
          'Printing allowed; copying and editing blocked.',
        ProtectPermissionPreset.printAndCopy =>
          'Print and copy text; no editing or comments.',
        ProtectPermissionPreset.fullAccess =>
          'All permissions enabled on the encrypted copy.',
        ProtectPermissionPreset.custom =>
          'Individual toggles below apply.',
      };
}

PdfEncryptPermissions permissionsForPreset(ProtectPermissionPreset preset) {
  return switch (preset) {
    ProtectPermissionPreset.viewOnly => const PdfEncryptPermissions(
        allowPrinting: false,
        allowModify: false,
        allowExtract: false,
        allowAnnotate: false,
      ),
    ProtectPermissionPreset.printOnly => const PdfEncryptPermissions(
        allowPrinting: true,
        allowModify: false,
        allowExtract: false,
        allowAnnotate: false,
      ),
    ProtectPermissionPreset.printAndCopy => const PdfEncryptPermissions(
        allowPrinting: true,
        allowModify: false,
        allowExtract: true,
        allowAnnotate: false,
      ),
    ProtectPermissionPreset.fullAccess => const PdfEncryptPermissions(
        allowPrinting: true,
        allowModify: true,
        allowExtract: true,
        allowAnnotate: true,
      ),
    ProtectPermissionPreset.custom => const PdfEncryptPermissions(),
  };
}

ProtectPermissionPreset presetMatching({
  required bool allowPrinting,
  required bool allowCopy,
  required bool allowModify,
  required bool allowAnnotate,
}) {
  for (final preset in ProtectPermissionPreset.values) {
    if (preset == ProtectPermissionPreset.custom) continue;
    final p = permissionsForPreset(preset);
    if (p.allowPrinting == allowPrinting &&
        p.allowExtract == allowCopy &&
        p.allowModify == allowModify &&
        p.allowAnnotate == allowAnnotate) {
      return preset;
    }
  }
  return ProtectPermissionPreset.custom;
}
