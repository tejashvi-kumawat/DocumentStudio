import 'package:document_studio/core/legal/bundled_licenses.dart';
import 'package:document_studio/features/office/office_route.dart';
import 'package:document_studio/core/storage/local_file_storage.dart';
import 'package:document_studio/design_system/widgets/ds_file_browser.dart';
import 'package:document_studio/core/update/app_updater.dart';
import 'package:document_studio/core/settings/app_prefs.dart';

import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/cli_launch_args.dart';
import 'package:document_studio/app/document_studio_app.dart';
import 'package:document_studio/app/router/app_router.dart';
import 'package:document_studio/app/shell/window/ds_window.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/perf/perf_log.dart';
import 'package:document_studio/core/storage/storage_cache_manager.dart';
import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/image_tools/image_tools_route.dart';
import 'package:document_studio/features/image_viewer/image_viewer_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

Future<void> bootstrap() async {
  PerfLog.mark('startup.begin');
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  final storage = await StoragePaths.init();
  // Scratch dirs of tools and bundled engines land in the app's temp/ box.
  IOOverrides.global = StorageIOOverrides(storage.temp);
  // First-run downloads (e.g. Windows LibreOffice) live under app support.
  final supportEngines = p.join(storage.root.path, 'engines');
  Directory(supportEngines).createSync(recursive: true);
  if (!debugDesktopEngineExtraRoots.contains(supportEngines)) {
    debugDesktopEngineExtraRoots = [
      ...debugDesktopEngineExtraRoots,
      supportEngines,
    ];
  }
  if (!debugQpdfExtraSearchRoots.contains(supportEngines)) {
    debugQpdfExtraSearchRoots = [...debugQpdfExtraSearchRoots, supportEngines];
  }
  // pdfrx's own cache inside the box (also skips a platform-channel lookup).
  Pdfrx.cacheDirectoryPath ??= p.join(storage.pages.path, 'pdfrx');
  // Align qpdf package lookup with the shared desktop engine resolver
  // (bundled engines/ before PATH). Not awaited: the first qpdf job is never
  // before the first frame, and a PATH probe spawns `which`.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    unawaited(
      desktopEngineResolver.resolveQpdf().then((qpdf) {
        if (qpdf != null) debugQpdfExecutableOverride ??= qpdf;
      }, onError: (Object _) {}),
    );
  }
  await Future.wait([
    PerfLog.time('startup.prefs', AppPrefs.load),
    PerfLog.time('startup.pdfrxInitialize', pdfrxFlutterInitialize),
    PerfLog.time('startup.windowInitialize', DsWindow.initialize),
  ]);

  // Desktop: open files with Document Studio's own browser.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    LocalFileStorage.inAppPicker =
        ({List<String>? extensions, bool multiple = false}) async {
          final ctx = rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return null;
          return showDsFileBrowser(
            ctx,
            extensions: extensions,
            multiple: multiple,
          );
        };
  }
  final container = ProviderContainer();
  PerfLog.mark('startup.runApp');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DocumentStudioApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PerfLog.mark('startup.firstFrame');
    _openLaunchArgs(container);
    _devAutoOpen(container);
    // Housekeeping off the startup path.
    Timer(const Duration(seconds: 3), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        StorageCacheManager.setUserGb(
          prefs.getInt(StorageCacheManager.budgetPrefKey) ?? 0,
        );
      } catch (_) {}
      unawaited(StorageCacheManager.instance.startupMaintenance());
    });
    // Quiet update check; the title bar shows "Update" when one exists.
    if (AppPrefs.autoUpdateCheck && !kDebugMode && !kStoreBuild) {
      Timer(const Duration(seconds: 8), () {
        unawaited(AppUpdater.instance.check());
      });
    }
  });
}

/// Opens files / tools from shell ("Open with", context menus, double-click).
void _openLaunchArgs(ProviderContainer container) {
  if (kIsWeb) return;
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  // A second launch ("Open with", double-click) forwards its argv to this
  // process, and macOS hands over files the same way, so they open as tabs
  // here instead of in a second window.
  const MethodChannel('document_studio/open').setMethodCallHandler((
    call,
  ) async {
    if (call.method != 'open') return;
    final raw = (call.arguments as List?)?.cast<String>() ?? const <String>[];
    final forwarded = CliLaunchArgs.parse(raw);
    if (forwarded.hasWork) {
      _openLaunch(container, forwarded, delay: Duration.zero);
    }
  });
  if (Platform.isMacOS) {
    // Tell the macOS shell it can now deliver Finder-opened files.
    unawaited(
      const MethodChannel('document_studio/open')
          .invokeMethod<void>('ready')
          .catchError((_) {}),
    );
  }
  final launch = CliLaunchArgs.fromProcess();
  if (!launch.hasWork) return;
  _openLaunch(container, launch);
}

void _openLaunch(
  ProviderContainer container,
  CliLaunchArgs launch, {
  Duration delay = const Duration(milliseconds: 350),
}) {
  Future<void>.delayed(delay, () async {
    PerfLog.mark('launch.openArgs');
    final tabs = container.read(documentTabsControllerProvider);
    final router = container.read(appRouterProvider);
    final toolName = launch.tool?.toLowerCase();
    final openImagesTool = toolName == 'images' || toolName == 'image';
    ViewerToolId? panel = launch.viewerTool;
    var openedPdf = false;

    for (final file in launch.fileRefs) {
      if (isOfficePath(file.path)) {
        router.go(officeLocation(path: file.path));
        continue;
      }
      if (file.isPdf) {
        await tabs.openDocument(file, openToolPanel: panel);
        panel = null;
        openedPdf = true;
        continue;
      }
      if (CliLaunchArgs.isImagePath(file.path)) {
        if (openImagesTool) {
          router.go(imageToolsRoutePath, extra: file);
        } else {
          router.go(imageViewerRoutePath, extra: file);
        }
        return;
      }
    }

    if (openedPdf) {
      router.go('/');
    }
  });
}

/// Debug/profile only: `DS_DEV_OPEN_PDF=/path/a.pdf flutter run` opens a tab
/// on launch so load timings can be measured without clicking through.
void _devAutoOpen(ProviderContainer container) {
  if (kReleaseMode) return;
  // Prefer real CLI / Open-with args when present.
  if (CliLaunchArgs.fromProcess().files.isNotEmpty) return;
  final path = Platform.environment['DS_DEV_OPEN_PDF'];
  if (path == null || path.isEmpty || !File(path).existsSync()) return;
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    PerfLog.mark('dev.autoOpen');
    final tabs = container.read(documentTabsControllerProvider);
    tabs.openDocument(LocalFileRef(path: path, displayName: p.basename(path)));
    // DS_DEV_SIMULATE_SAVE=1: commit an in-place save 4 s later to measure
    // the seamless document swap (same content + trailing comment).
    if (Platform.environment['DS_DEV_SIMULATE_SAVE'] == '1') {
      Future<void>.delayed(const Duration(seconds: 4), () async {
        final session = tabs.activeSession;
        if (session == null) return;
        final bytes = await session.readCurrentBytes();
        PerfLog.mark('dev.simulatedSave');
        await session.commitBytes(
          Uint8List.fromList([...bytes, ...'\n%ds\n'.codeUnits]),
        );
        tabs.syncActiveTabFromSession();
      });
    }
  });
}
