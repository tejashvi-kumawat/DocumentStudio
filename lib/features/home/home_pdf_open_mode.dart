/// How the user chose to open a PDF from Home (viewer, workspace, tools).
enum HomePdfOpenMode {
  read,
  editPages,
  compress,
  protect;

  String get label => switch (this) {
        HomePdfOpenMode.read => 'Read',
        HomePdfOpenMode.editPages => 'Edit pages',
        HomePdfOpenMode.compress => 'Compress',
        HomePdfOpenMode.protect => 'Encrypt',
      };

  String get subtitle => switch (this) {
        HomePdfOpenMode.read => 'View, search, and annotate',
        HomePdfOpenMode.editPages => 'Organize in workspace',
        HomePdfOpenMode.compress => 'Reduce file size',
        HomePdfOpenMode.protect => 'Password and permissions',
      };

  static HomePdfOpenMode? fromStorage(String? value) {
    if (value == null) return null;
    return HomePdfOpenMode.values.cast<HomePdfOpenMode?>().firstWhere(
          (m) => m?.name == value,
          orElse: () => null,
        );
  }
}
