/// App marketing version (semver without build number).
///
/// Keep in sync with the `version:` line in `pubspec.yaml` (the part before `+`).
/// Release builds may override with `--dart-define=APP_VERSION=x.y.z`.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.3',
);

const String kAppName = 'Document Studio';
const String kGithubOwner = 'tejashvi-kumawat';
const String kGithubRepo = 'DocumentStudio';
const String kWingetId = 'DocumentStudio.DocumentStudio';
const String kBrewCask = 'document-studio';
const String kFlatpakId = 'com.documentstudio.document_studio';
