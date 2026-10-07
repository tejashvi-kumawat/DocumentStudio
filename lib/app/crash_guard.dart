import 'dart:async';

import 'package:document_studio/core/logging/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Keeps an unexpected error from taking the app down.
///
/// Uncaught Dart errors (zone), Flutter framework errors and platform errors
/// are logged and swallowed; the UI stays alive. A repeating error is only
/// logged a few times so a broken frame cannot flood the log or the CPU.
abstract final class CrashGuard {
  static final Map<String, int> _seen = {};
  static const _maxRepeats = 3;

  static void report(Object error, StackTrace? stack, {String where = ''}) {
    final key = '${error.runtimeType}:${error.toString().split('\n').first}';
    final n = _seen.update(key, (v) => v + 1, ifAbsent: () => 1);
    if (n > _maxRepeats) return;
    appLog.severe(
      '${where.isEmpty ? '' : '$where: '}$error'
      '${kReleaseMode ? '' : '\n$stack'}',
    );
  }

  /// Installs the handlers. Call once, early.
  static void install() {
    FlutterError.onError = (details) {
      report(details.exception, details.stack, where: 'flutter');
      if (!kReleaseMode) FlutterError.dumpErrorToConsole(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, where: 'platform');
      return true; // handled: do not terminate
    };
    // A render error leaves a grey box instead of a red screen of text.
    ErrorWidget.builder = (details) =>
        kReleaseMode ? const SizedBox.shrink() : ErrorWidget(details.exception);
  }

  /// Memory pressure from the OS: drop decoded images so the app survives.
  static void watchMemoryPressure(VoidCallback onPressure) {
    WidgetsBinding.instance.addObserver(_Observer(onPressure));
  }

  /// Runs [body] so uncaught async errors are reported, not fatal.
  static void run(Future<void> Function() body) {
    runZonedGuarded(body, (e, s) => report(e, s, where: 'zone'));
  }
}

class _Observer with WidgetsBindingObserver {
  _Observer(this.onPressure);

  final VoidCallback onPressure;

  @override
  void didHaveMemoryPressure() => onPressure();
}

/// Frees what can be rebuilt: Flutter's decoded image cache.
void releaseMemory() {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  SchedulerBinding.instance.scheduleFrame();
}
