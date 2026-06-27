import 'dart:async';
import 'dart:isolate';

import 'package:document_studio/domain/compare/compare_engine.dart';
import 'package:document_studio/domain/compare/compare_models.dart';

/// Cooperative cancellation shared by extraction and analysis.
class CompareCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
    _listeners.clear();
  }

  /// Runs [listener] on cancel (immediately if already cancelled). Returns a
  /// callback that unregisters it.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) throw const CompareCancelled();
  }
}

typedef _Request = ({
  SendPort port,
  CompareDocData oldDoc,
  CompareDocData newDoc,
});

/// Runs [computeCompare] in a dedicated isolate. [onProgress] receives 0..1;
/// cancelling [token] kills the isolate immediately and completes with
/// [CompareCancelled].
Future<CompareResult> runCompareInIsolate(
  CompareDocData oldDoc,
  CompareDocData newDoc, {
  void Function(double progress)? onProgress,
  CompareCancelToken? token,
}) async {
  token?.throwIfCancelled();
  final port = ReceivePort();
  final done = Completer<CompareResult>();
  Isolate? isolate;

  void finish([Object? error]) {
    port.close();
    if (done.isCompleted) return;
    if (error != null) done.completeError(error);
  }

  final unregister = token?.onCancel(() {
    isolate?.kill(priority: Isolate.immediate);
    finish(const CompareCancelled());
  });

  port.listen((msg) {
    if (msg is double) {
      if (!done.isCompleted) onProgress?.call(msg);
    } else if (msg is CompareResult) {
      if (!done.isCompleted) done.complete(msg);
      port.close();
    } else if (msg is List && msg.length == 2) {
      finish(StateError('Compare failed: ${msg[0]}'));
    } else if (msg == null) {
      finish(StateError('Compare worker exited unexpectedly'));
    }
  });

  try {
    isolate = await Isolate.spawn<_Request>(
      _entry,
      (port: port.sendPort, oldDoc: oldDoc, newDoc: newDoc),
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
      debugName: 'compare-diff',
    );
    if (token?.isCancelled ?? false) {
      isolate.kill(priority: Isolate.immediate);
    }
  } catch (e) {
    finish(e);
  }
  try {
    return await done.future;
  } finally {
    unregister?.call();
  }
}

void _entry(_Request r) {
  final result = computeCompare(
    r.oldDoc,
    r.newDoc,
    onProgress: (p) => r.port.send(p),
  );
  Isolate.exit(r.port, result);
}
