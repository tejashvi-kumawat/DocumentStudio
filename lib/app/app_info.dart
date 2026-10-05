import 'package:document_studio/app/app_version.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The version of the running build, read from the platform package info
/// (it follows `version:` in pubspec.yaml / the release build), so About never
/// shows a stale number. Falls back to [kAppVersion] if unavailable.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version.trim();
    if (v.isNotEmpty) return v;
  } catch (_) {}
  return kAppVersion;
});

/// "1.0.4 (12)" style label including the build number when known.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final b = info.buildNumber.trim();
    if (info.version.isNotEmpty) {
      return b.isEmpty || b == '0' ? info.version : '${info.version} ($b)';
    }
  } catch (_) {}
  return kAppVersion;
});
