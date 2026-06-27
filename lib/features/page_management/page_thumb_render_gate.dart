import 'dart:async';

/// How many thumbnail renders may run at once.
///
/// Device budgets below 2 still get 2 so the first screen is not stuck behind
/// a single slot. Nothing in the grid is allowed past 3.
int clampThumbnailConcurrency(int deviceConcurrency) {
  if (deviceConcurrency < 2) return 2;
  if (deviceConcurrency > 3) return 3;
  return deviceConcurrency;
}

/// A slot from [PageThumbRenderGate].
///
/// Await [ready] before rendering. Call [release] when the render finishes,
/// including when it was cancelled. [cancel] drops a permit that is still
/// waiting so a later visible page can take the slot.
class PageThumbPermit {
  PageThumbPermit._(this._gate, this.priority, this.seq);

  final PageThumbRenderGate _gate;
  int priority;
  final int seq;
  final Completer<void> _ready = Completer<void>();
  bool _cancelled = false;
  bool _holding = false;
  bool _released = false;

  Future<void> get ready => _ready.future;

  bool get isCancelled => _cancelled;

  /// True once this permit owns a slot.
  bool get isHolding => _holding;

  void cancel() {
    if (_cancelled || _released) return;
    _cancelled = true;
    _gate._drop(this);
  }

  void release() {
    if (_released || !_holding) return;
    _released = true;
    _holding = false;
    _gate._onRelease();
  }
}

/// At most [concurrency] thumbnail renders at once.
///
/// Higher [priority] runs first. Equal priority is FIFO so the first visible
/// pages are not stuck behind pages queued later (a LIFO queue paints
/// off-screen pages first).
class PageThumbRenderGate {
  PageThumbRenderGate({this.concurrency = 2}) : assert(concurrency >= 1);

  final int concurrency;

  int _running = 0;
  int _seq = 0;
  final List<PageThumbPermit> _waiting = <PageThumbPermit>[];

  int get running => _running;

  int get waiting => _waiting.length;

  PageThumbPermit acquire({required int priority}) {
    final permit = PageThumbPermit._(this, priority, _seq++);
    if (_running < concurrency && _waiting.isEmpty) {
      _running++;
      permit._holding = true;
      permit._ready.complete();
      return permit;
    }
    _waiting.add(permit);
    return permit;
  }

  void reprioritize(PageThumbPermit permit, int priority) {
    if (priority > permit.priority) permit.priority = priority;
  }

  void _drop(PageThumbPermit permit) {
    final index = _waiting.indexOf(permit);
    if (index >= 0) _waiting.removeAt(index);
    if (!permit._ready.isCompleted) permit._ready.complete();
  }

  void _onRelease() {
    while (_waiting.isNotEmpty) {
      final next = _bestWaiting();
      _waiting.remove(next);
      if (next._cancelled) {
        if (!next._ready.isCompleted) next._ready.complete();
        continue;
      }
      next._holding = true;
      if (!next._ready.isCompleted) next._ready.complete();
      return;
    }
    _running--;
    if (_running < 0) _running = 0;
  }

  PageThumbPermit _bestWaiting() {
    var best = 0;
    for (var i = 1; i < _waiting.length; i++) {
      final candidate = _waiting[i];
      final current = _waiting[best];
      final higher = candidate.priority > current.priority;
      final earlierTie = candidate.priority == current.priority &&
          candidate.seq < current.seq;
      if (higher || earlierTie) best = i;
    }
    return _waiting[best];
  }
}
