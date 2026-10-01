import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

final _log = Logger('DsWindow');

/// Desktop window chrome capabilities for the current platform.
///
/// The Linux runner hides the GTK title bar and exports
/// `DOCUMENT_STUDIO_CUSTOM_FRAME=1` (and `DOCUMENT_STUDIO_TRANSPARENT=1` when
/// the compositor supports an RGBA window) so Dart never draws a second set
/// of window controls on top of a native title bar.
abstract final class DsWindow {
  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool _initialized = false;

  /// True when the app draws its own title bar (tabs + drag area).
  static bool get usesCustomFrame {
    if (!_initialized) return false;
    if (Platform.isLinux) {
      return Platform.environment['DOCUMENT_STUDIO_CUSTOM_FRAME'] == '1';
    }
    return Platform.isMacOS || Platform.isWindows;
  }

  /// Min / max / close drawn in Flutter (macOS keeps native traffic lights).
  static bool get drawsCaptionButtons =>
      usesCustomFrame && (Platform.isLinux || Platform.isWindows);

  /// Linux draws rounded window corners itself (transparent GTK window).
  static bool get clipsWindowCorners =>
      usesCustomFrame &&
      Platform.isLinux &&
      Platform.environment['DOCUMENT_STUDIO_TRANSPARENT'] == '1';

  /// Horizontal space reserved for macOS traffic lights.
  static const double macTrafficLightInset = 78;

  static const Size minimumSize = Size(560, 420);

  /// Call before [runApp]. Failures fall back to the native title bar.
  static Future<void> initialize() async {
    if (!isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      if (Platform.isLinux) {
        // The GTK window is created at 1280x720
        // (linux/runner/my_application.cc) and then mapped at its real size.
        // window_manager's waitUntilReadyToShow unmaximizes on every startup,
        // including hot restart, which restores that 1280x720 default while
        // the embedder already has a frame of the live window. The OpenGL
        // compositor then times out waiting for the old size. Minimum size
        // does not change the current size.
        await windowManager.setMinimumSize(minimumSize);
        _initialized = true;
        return;
      }
      final hideNativeTitleBar = Platform.isMacOS || Platform.isWindows;
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          minimumSize: minimumSize,
          titleBarStyle: hideNativeTitleBar ? TitleBarStyle.hidden : null,
          windowButtonVisibility: Platform.isMacOS ? true : null,
        ),
      );
      _initialized = true;
    } catch (e, st) {
      _log.warning('Window manager unavailable; using native frame', e, st);
    }
  }

  static Future<void> toggleMaximize() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      return;
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

@immutable
class DsWindowState {
  const DsWindowState({
    this.maximized = false,
    this.fullScreen = false,
    this.focused = true,
  });

  final bool maximized;
  final bool fullScreen;
  final bool focused;

  /// Window fills the screen edge-to-edge (no rounded corners / shadow).
  bool get edgeToEdge => maximized || fullScreen;

  DsWindowState copyWith({bool? maximized, bool? fullScreen, bool? focused}) {
    return DsWindowState(
      maximized: maximized ?? this.maximized,
      fullScreen: fullScreen ?? this.fullScreen,
      focused: focused ?? this.focused,
    );
  }
}

final dsWindowStateProvider =
    NotifierProvider<DsWindowStateNotifier, DsWindowState>(
  DsWindowStateNotifier.new,
);

class DsWindowStateNotifier extends Notifier<DsWindowState>
    with WindowListener {
  @override
  DsWindowState build() {
    if (!DsWindow.usesCustomFrame) return const DsWindowState();
    windowManager.addListener(this);
    ref.onDispose(() => windowManager.removeListener(this));
    Future.microtask(_refresh);
    return const DsWindowState();
  }

  Future<void> _refresh() async {
    try {
      final maximized = await windowManager.isMaximized();
      final fullScreen = await windowManager.isFullScreen();
      state = state.copyWith(maximized: maximized, fullScreen: fullScreen);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() => state = state.copyWith(maximized: true);

  @override
  void onWindowUnmaximize() => state = state.copyWith(maximized: false);

  @override
  void onWindowEnterFullScreen() => state = state.copyWith(fullScreen: true);

  @override
  void onWindowLeaveFullScreen() => state = state.copyWith(fullScreen: false);

  @override
  void onWindowFocus() => state = state.copyWith(focused: true);

  @override
  void onWindowBlur() => state = state.copyWith(focused: false);

  @override
  void onWindowResized() => _refresh();
}
