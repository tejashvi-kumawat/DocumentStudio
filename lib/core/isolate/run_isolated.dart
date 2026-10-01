import 'dart:isolate';

/// Runs [fn] with [arg] on a background isolate.
///
/// Must stay top-level: a closure created inside an instance method shares its
/// context with sibling closures there, so it can capture `this` (widgets,
/// controllers, focus nodes) and fail with "object is unsendable". [fn] must
/// be a top-level or static function.
Future<R> runIsolated<A, R>(R Function(A arg) fn, A arg, {String? debugName}) =>
    Isolate.run(() => fn(arg), debugName: debugName);
