import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight timing log for load / render / save paths.
///
/// Prints `[perf] <label>: <ms> ms` in debug and profile builds and emits a
/// matching timeline event so the spans show up in DevTools (`--profile`).
class PerfLog {
  PerfLog._();

  static bool enabled = !kReleaseMode;

  static final Stopwatch _sinceStart = Stopwatch()..start();

  /// Milliseconds since the app process started this isolate.
  static int get uptimeMs => _sinceStart.elapsedMilliseconds;

  static void mark(String label) {
    if (!enabled) return;
    debugPrint('[perf] $label @ ${_sinceStart.elapsedMilliseconds} ms');
  }

  static void log(String label, Duration elapsed) {
    if (!enabled) return;
    debugPrint('[perf] $label: ${elapsed.inMilliseconds} ms');
  }

  /// Times [task]; logs and records a timeline span named [label].
  static Future<T> time<T>(String label, Future<T> Function() task) async {
    if (!enabled) return task();
    final sw = Stopwatch()..start();
    final flow = developer.TimelineTask()..start(label);
    try {
      return await task();
    } finally {
      flow.finish();
      log(label, sw.elapsed);
    }
  }
}
