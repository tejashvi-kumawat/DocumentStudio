import 'dart:async';

import 'package:document_studio/app/first_launch_splash.dart';
import 'package:document_studio/app/keyboard/app_shortcuts.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/app/router/app_router.dart';
import 'package:document_studio/core/desktop/offer_desktop_engine_setup.dart';
import 'package:document_studio/core/desktop/pdf_default_app_prompt.dart';
import 'package:document_studio/core/logging/app_log.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_theme.dart';
import 'package:document_studio/features/command_palette/ds_command_palette.dart';
import 'package:document_studio/app/shell/ds_shell_actions.dart';
import 'package:document_studio/app/shell/ds_window_title_bar.dart';
import 'package:document_studio/features/pdf_viewer/viewer_shortcut_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DocumentStudioApp extends ConsumerStatefulWidget {
  const DocumentStudioApp({super.key});

  @override
  ConsumerState<DocumentStudioApp> createState() => _DocumentStudioAppState();
}

class _DocumentStudioAppState extends ConsumerState<DocumentStudioApp> {
  @override
  void initState() {
    super.initState();
    configureAppLogging();
    // Edge-to-edge so viewPadding reports status / nav insets; content clears
    // them via MediaQuery.padding merge + SafeArea (not under the clock).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    Future.microtask(() => ref.read(themeModeProvider.notifier).load());
    final afterSplash = desktopEngineSetupWaitAfterSplash();
    unawaited(
      offerLinuxPdfDefaultPrompt(
        navigatorContext: () => rootNavigatorKey.currentContext,
        waitBeforePrompt: afterSplash,
      ),
    );
    unawaited(
      offerDesktopEngineSetup(
        navigatorContext: () => rootNavigatorKey.currentContext,
        waitBeforePrompt: afterSplash + const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    final viewerShortcuts = ref.watch(viewerShortcutActionsProvider);

    return AppShortcuts(
      onOpen: () {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final viewerOpen = viewerShortcuts.onOpen;
        if (viewerOpen != null) {
          viewerOpen();
          return;
        }
        // Root navigator context has no GoRouterState; use the chrome flow.
        dsOpenPdfFromChrome(
          ref: ref,
          router: router,
          navigatorContext: () => rootNavigatorKey.currentContext,
        );
      },
      onPrint: viewerShortcuts.onPrint,
      onFind: viewerShortcuts.onFind,
      onUndo: viewerShortcuts.onUndo,
      onRedo: viewerShortcuts.onRedo,
      onSave: viewerShortcuts.onSave,
      onCommandPalette: () {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        showDocumentStudioCommandPalette(ctx);
      },
      child: MaterialApp.router(
        title: 'Document Studio',
        debugShowCheckedModeBanner: false,
        theme: DsTheme.light(),
        darkTheme: DsTheme.dark(),
        themeMode: themeMode,
        scrollBehavior: const DsScrollBehavior(),
        routerConfig: router,
        builder: (context, child) {
          // Android edge-to-edge often zeros MediaQuery.padding while
          // viewPadding still holds the status / gesture insets. Merge so
          // SafeArea, AppBar, and NavigationBar clear those areas on every
          // route. Also consult FlutterView.padding when MediaQuery lags.
          // Desktop Linux viewPadding is 0 — no fake top gap.
          final mq = MediaQuery.of(context);
          final vp = mq.viewPadding;
          final view = View.maybeOf(context);
          final fromView = view == null
              ? EdgeInsets.zero
              : EdgeInsets.fromViewPadding(view.padding, view.devicePixelRatio);
          double maxInset(double a, double b, double c) =>
              a > b ? (a > c ? a : c) : (b > c ? b : c);
          final merged = mq.copyWith(
            padding: EdgeInsets.only(
              left: maxInset(mq.padding.left, vp.left, fromView.left),
              top: maxInset(mq.padding.top, vp.top, fromView.top),
              right: maxInset(mq.padding.right, vp.right, fromView.right),
              bottom: maxInset(mq.padding.bottom, vp.bottom, fromView.bottom),
            ),
          );
          return MediaQuery(
            data: merged,
            child: DsWindowFrame(
              router: router,
              navigatorContext: () => rootNavigatorKey.currentContext,
              child: FirstLaunchSplashHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}
