/// App marketing version (semver without build number).
///
/// Keep in sync with the `version:` line in `pubspec.yaml` (the part before `+`).
/// Release builds may override with `--dart-define=APP_VERSION=x.y.z`.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.1.0',
);

const String kAppName = 'Document Studio';
const String kGithubOwner = 'tejashvi-kumawat';
const String kGithubRepo = 'DocumentStudio';
const String kWingetId = 'DocumentStudio.DocumentStudio';
const String kBrewCask = 'document-studio';
const String kFlatpakId = 'com.documentstudio.document_studio';

const String kAuthorName = 'Tejashvi Kumawat';
const String kAuthorGithubUrl = 'https://github.com/tejashvi-kumawat';
const String kRepoUrl = 'https://github.com/$kGithubOwner/$kGithubRepo';
const String kIssuesUrl = '$kRepoUrl/issues';
const String kReleasesUrl = '$kRepoUrl/releases';
const String kContributeUrl = '$kRepoUrl/blob/main/CONTRIBUTING.md';
