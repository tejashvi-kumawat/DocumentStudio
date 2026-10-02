import 'dart:convert';
import 'dart:io';

import 'package:document_studio/app/app_version.dart';
import 'package:path/path.dart' as p;

/// Handles non-GUI maintenance flags before Flutter boots.
///
/// Returns `true` when the process should exit (version / help / update).
Future<bool> tryHandleMaintenanceArgs(List<String> args) async {
  if (args.isEmpty) return false;
  final normalized = args.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
  if (normalized.isEmpty) return false;

  if (_has(normalized, const ['--version', '-V', 'version'])) {
    stdout.writeln('$kAppName $kAppVersion');
    return true;
  }

  if (_has(normalized, const ['--help', '-h', 'help'])) {
    _printHelp();
    return true;
  }

  final checkOnly = _has(normalized, const ['--check-update', 'check-update']);
  final doUpdate = _has(normalized, const ['--update', 'update']);
  if (!checkOnly && !doUpdate) return false;

  await _runUpdate(checkOnly: checkOnly);
  return true;
}

bool _has(List<String> args, List<String> needles) {
  for (final a in args) {
    if (needles.contains(a)) return true;
  }
  return false;
}

void _printHelp() {
  stdout.writeln('''
$kAppName $kAppVersion

Usage:
  document_studio [file ...]
  document_studio --tool <name> [file ...]
  document_studio --version
  document_studio --check-update
  document_studio --update

Updates:
  --check-update   Compare installed version to the latest GitHub Release
  --update         Upgrade in place (package manager if present, else GitHub asset)

Package-manager shortcuts (same effect when listed):
  Windows:  winget upgrade --id $kWingetId
  macOS:    brew upgrade --cask $kBrewCask
  Linux:    sudo apt install ./document-studio_<ver>_amd64.deb
            flatpak update $kFlatpakId
''');
}

Future<void> _runUpdate({required bool checkOnly}) async {
  stdout.writeln('Installed: $kAppName $kAppVersion');

  final latest = await _fetchLatestRelease();
  if (latest == null) {
    stderr.writeln(
      'Could not reach GitHub Releases '
      '($kGithubOwner/$kGithubRepo). Check network and try again.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('Latest:    $kAppName ${latest.version}');
  final cmp = _compareSemver(kAppVersion, latest.version);
  if (cmp >= 0) {
    stdout.writeln('Already up to date.');
    return;
  }

  if (checkOnly) {
    stdout.writeln('Update available: ${latest.version}');
    stdout.writeln('Run: document_studio --update');
    exitCode = 2; // non-zero so scripts can detect "needs update"
    return;
  }

  // Prefer channel the user already installed from.
  if (Platform.isWindows && await _tryWingetUpgrade()) return;
  if (Platform.isMacOS && await _tryBrewUpgrade()) return;
  if (Platform.isLinux && await _tryLinuxPackageUpgrade(latest.version)) return;

  await _updateFromGitHubAsset(latest);
}

Future<_ReleaseInfo?> _fetchLatestRelease() async {
  final uri = Uri.parse(
    'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest',
  );
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.set(HttpHeaders.userAgentHeader, 'DocumentStudio-Updater/$kAppVersion');
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('GitHub API HTTP ${res.statusCode}');
      return null;
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (version.isEmpty) return null;
    final assets = <_Asset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final a in rawAssets) {
        if (a is! Map<String, dynamic>) continue;
        final name = a['name'] as String? ?? '';
        final url = a['browser_download_url'] as String? ?? '';
        if (name.isEmpty || url.isEmpty) continue;
        assets.add(_Asset(name: name, url: url));
      }
    }
    return _ReleaseInfo(version: version, assets: assets);
  } catch (e) {
    stderr.writeln('Release lookup failed: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _tryWingetUpgrade() async {
  if (!await _commandExists('winget')) return false;
  stdout.writeln('Updating via winget (in place)…');
  final r = await Process.run(
    'winget',
    [
      'upgrade',
      '--id',
      kWingetId,
      '--accept-package-agreements',
      '--accept-source-agreements',
      '--disable-interactivity',
    ],
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode == 0) {
    stdout.writeln('winget upgrade finished.');
    return true;
  }
  //  -1978335189 often means "no applicable upgrade" / not installed via winget
  stdout.writeln('winget upgrade not used (exit ${r.exitCode}); trying GitHub asset…');
  return false;
}

Future<bool> _tryBrewUpgrade() async {
  if (!await _commandExists('brew')) return false;
  // Only use brew if the cask is actually installed.
  final list = await Process.run(
    'brew',
    ['list', '--cask', kBrewCask],
    runInShell: true,
  );
  if (list.exitCode != 0) return false;

  stdout.writeln('Updating via Homebrew cask (in place)…');
  final r = await Process.run(
    'brew',
    ['upgrade', '--cask', kBrewCask],
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode == 0) {
    stdout.writeln('brew upgrade finished.');
    return true;
  }
  stdout.writeln('brew upgrade failed (exit ${r.exitCode}); trying GitHub asset…');
  return false;
}

Future<bool> _tryLinuxPackageUpgrade(String version) async {
  if (await _commandExists('flatpak')) {
    final info = await Process.run(
      'flatpak',
      ['info', kFlatpakId],
      runInShell: true,
    );
    if (info.exitCode == 0) {
      stdout.writeln('Updating via Flatpak (in place)…');
      final r = await Process.run(
        'flatpak',
        ['update', '-y', kFlatpakId],
        runInShell: true,
      );
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      if (r.exitCode == 0) {
        stdout.writeln('flatpak update finished.');
        return true;
      }
    }
  }
  // apt only if package is installed from a repo (not a one-shot .deb path).
  if (await _commandExists('apt-get')) {
    final policy = await Process.run(
      'dpkg-query',
      ['-W', '-f=\${Status}', 'document-studio'],
      runInShell: true,
    );
    final status = (policy.stdout as String? ?? '');
    if (status.contains('install ok installed')) {
      stdout.writeln(
        'Debian package detected. Download the new .deb and install in place with:',
      );
      stdout.writeln(
        '  wget https://github.com/$kGithubOwner/$kGithubRepo/releases/download/v$version/document-studio_${version}_amd64.deb',
      );
      stdout.writeln('  sudo apt install ./document-studio_${version}_amd64.deb');
      // Continue to automatic .deb download below.
    }
  }
  return false;
}

Future<void> _updateFromGitHubAsset(_ReleaseInfo latest) async {
  final asset = _pickAsset(latest.assets);
  if (asset == null) {
    stderr.writeln(
      'No matching release asset for this platform in v${latest.version}.',
    );
    stderr.writeln(
      'See https://github.com/$kGithubOwner/$kGithubRepo/releases/tag/v${latest.version}',
    );
    exitCode = 1;
    return;
  }

  final tmpDir = await Directory.systemTemp.createTemp('ds-update-');
  final dest = File(p.join(tmpDir.path, asset.name));
  stdout.writeln('Downloading ${asset.name}…');
  try {
    await _download(Uri.parse(asset.url), dest);
  } catch (e) {
    stderr.writeln('Download failed: $e');
    exitCode = 1;
    return;
  }

  if (Platform.isWindows) {
    await _installWindowsSetup(dest);
    return;
  }
  if (Platform.isMacOS) {
    await _installMacosDmg(dest, tmpDir);
    return;
  }
  if (Platform.isLinux) {
    await _installLinuxDeb(dest);
    return;
  }
  stderr.writeln('Unsupported platform for in-place update.');
  exitCode = 1;
}

_Asset? _pickAsset(List<_Asset> assets) {
  bool match(_Asset a) {
    final n = a.name.toLowerCase();
    if (Platform.isWindows) {
      return n.endsWith('-setup.exe') || n.endsWith('setup.exe');
    }
    if (Platform.isMacOS) {
      return n.endsWith('-macos.dmg');
    }
    if (Platform.isLinux) {
      return n.contains('document-studio_') && n.endsWith('_amd64.deb');
    }
    return false;
  }

  for (final a in assets) {
    if (match(a)) return a;
  }
  return null;
}

Future<void> _download(Uri url, File dest) async {
  final client = HttpClient();
  try {
    var current = url;
    for (var hop = 0; hop < 8; hop++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'DocumentStudio-Updater/$kAppVersion');
      final res = await req.close();
      if (res.isRedirect) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null || loc.isEmpty) {
          throw StateError('Redirect without Location');
        }
        current = current.resolve(loc);
        continue;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw StateError('HTTP ${res.statusCode} for $current');
      }
      final sink = dest.openWrite();
      await res.pipe(sink);
      return;
    }
    throw StateError('Too many redirects');
  } finally {
    client.close(force: true);
  }
}

Future<void> _installWindowsSetup(File setup) async {
  stdout.writeln('Installing in place (silent Setup.exe)…');
  stdout.writeln('The app will close so files can be replaced.');
  // Detach so this process can exit and Inno CloseApplications can finish.
  await Process.start(
    setup.path,
    const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ],
    mode: ProcessStartMode.detached,
  );
  stdout.writeln('Updater launched. Exiting so the install can finish.');
  exit(0);
}

Future<void> _installMacosDmg(File dmg, Directory tmpDir) async {
  final mountPoint = p.join(tmpDir.path, 'mnt');
  await Directory(mountPoint).create(recursive: true);
  stdout.writeln('Mounting DMG…');
  final attach = await Process.run(
    'hdiutil',
    ['attach', dmg.path, '-nobrowse', '-quiet', '-mountpoint', mountPoint],
  );
  if (attach.exitCode != 0) {
    stderr.write(attach.stderr);
    stderr.writeln('hdiutil attach failed.');
    exitCode = 1;
    return;
  }

  try {
    final apps = Directory(mountPoint)
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.toLowerCase().endsWith('.app'))
        .toList();
    if (apps.isEmpty) {
      stderr.writeln('No .app found inside DMG.');
      exitCode = 1;
      return;
    }
    final src = apps.first;
    final destName = p.basename(src.path);
    final dest = Directory('/Applications/$destName');
    stdout.writeln('Replacing $dest …');
    if (dest.existsSync()) {
      await dest.delete(recursive: true);
    }
    final copy = await Process.run('cp', ['-R', src.path, dest.path]);
    if (copy.exitCode != 0) {
      stderr.write(copy.stderr);
      stderr.writeln('Copy to /Applications failed (try with admin rights).');
      exitCode = 1;
      return;
    }
    stdout.writeln('Updated in place: ${dest.path}');
  } finally {
    await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
  }
}

Future<void> _installLinuxDeb(File deb) async {
  stdout.writeln('Installing .deb in place…');
  // Prefer apt so dependencies resolve; falls back to dpkg.
  if (await _commandExists('apt-get')) {
    final r = await Process.run(
      'sudo',
      ['apt-get', 'install', '-y', './${p.basename(deb.path)}'],
      workingDirectory: deb.parent.path,
      runInShell: false,
    );
    stdout.write(r.stdout);
    stderr.write(r.stderr);
    if (r.exitCode == 0) {
      stdout.writeln('apt install finished (in place).');
      return;
    }
  }
  final r = await Process.run(
    'sudo',
    ['dpkg', '-i', deb.path],
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) {
    exitCode = r.exitCode;
    stderr.writeln('dpkg install failed.');
    return;
  }
  stdout.writeln('dpkg install finished (in place).');
}

Future<bool> _commandExists(String name) async {
  final r = await Process.run(
    Platform.isWindows ? 'where' : 'which',
    [name],
    runInShell: true,
  );
  return r.exitCode == 0;
}

/// Returns negative if [a] < [b], 0 if equal, positive if [a] > [b].
int _compareSemver(String a, String b) {
  List<int> parts(String v) {
    final core = v.split(RegExp(r'[-+]')).first;
    return core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

class _ReleaseInfo {
  _ReleaseInfo({required this.version, required this.assets});
  final String version;
  final List<_Asset> assets;
}

class _Asset {
  _Asset({required this.name, required this.url});
  final String name;
  final String url;
}
