import 'dart:io';

import 'package:document_studio/app/first_launch_splash.dart';
import 'package:document_studio/core/desktop/desktop_engine_status.dart';
import 'package:document_studio/features/setup/desktop_engine_setup_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDesktopEngineSetupPrefKey = 'desktop_engine_setup_prompt_v1';

const kDesktopEngineSetupBundled = 'bundled';
const kDesktopEngineSetupSkipped = 'skipped';
const kDesktopEngineSetupCompleted = 'completed';

/// After the splash, offer a GUI to download missing engines (Windows portable / partial installs).
Future<void> offerDesktopEngineSetup({
  required BuildContext? Function() navigatorContext,
  Duration waitBeforePrompt = const Duration(milliseconds: 1480),
}) async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  if (kIsWeb) return;
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(kDesktopEngineSetupPrefKey);
  if (saved != null && saved.isNotEmpty) return;

  final status = await DesktopEngineStatus.probe();
  if (status.allRecommendedReady) {
    await prefs.setString(
      kDesktopEngineSetupPrefKey,
      kDesktopEngineSetupBundled,
    );
    return;
  }
  // Linux .deb users usually have everything; only prompt when core PDF tools missing.
  if (Platform.isLinux && status.corePdfToolsReady) {
    await prefs.setString(
      kDesktopEngineSetupPrefKey,
      kDesktopEngineSetupSkipped,
    );
    return;
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

  await showDesktopEngineSetupDialog(ctx);
  if (!ctx.mounted) return;
  final after = await DesktopEngineStatus.probe();
  await prefs.setString(
    kDesktopEngineSetupPrefKey,
    after.allRecommendedReady
        ? kDesktopEngineSetupCompleted
        : kDesktopEngineSetupSkipped,
  );
}

/// Same delay as PDF default prompt — after cold-start splash.
Duration desktopEngineSetupWaitAfterSplash() =>
    FirstLaunchSplashTiming.displayUntilFade +
    FirstLaunchSplashTiming.fadeOut +
    const Duration(milliseconds: 80);
