import 'dart:async';

import 'package:document_studio/features/document_workspace/workspace_page_grid.dart';
import 'package:document_studio/features/page_management/page_thumb_render_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thumbnail concurrency stays between 2 and 3', () {
    expect(clampThumbnailConcurrency(1), 2);
    expect(clampThumbnailConcurrency(2), 2);
    expect(clampThumbnailConcurrency(3), 3);
    expect(clampThumbnailConcurrency(8), 3);
  });

  test('at most N renders run, and a cancelled waiter never takes a slot', () async {
    final gate = PageThumbRenderGate(concurrency: 2);
    final first = gate.acquire(priority: 10);
    final second = gate.acquire(priority: 10);
    final skipped = gate.acquire(priority: 1);
    final next = gate.acquire(priority: 5);
    await first.ready;
    await second.ready;
    expect(gate.running, 2);

    var skippedReady = false;
    unawaited(skipped.ready.then((_) => skippedReady = true));
    skipped.cancel();
    await skipped.ready;
    expect(skipped.isCancelled, isTrue);
    expect(skipped.isHolding, isFalse);

    first.release();
    await next.ready;
    await Future<void>.delayed(Duration.zero);
    expect(next.isHolding, isTrue);
    expect(skippedReady, isTrue);
    expect(gate.running, 2);
  });

  test('higher priority runs before an earlier lower-priority waiter', () async {
    final gate = PageThumbRenderGate(concurrency: 1);
    final hold = gate.acquire(priority: 1);
    await hold.ready;
    final low = gate.acquire(priority: 1);
    final high = gate.acquire(priority: 100);

    var lowReady = false;
    unawaited(low.ready.then((_) => lowReady = true));
    hold.release();
    await high.ready;
    await Future<void>.delayed(Duration.zero);
    expect(high.isHolding, isTrue);
    expect(lowReady, isFalse);
    expect(gate.running, 1);

    high.release();
    await low.ready;
    expect(low.isHolding, isTrue);
  });

  test('equal priority is FIFO so the first page is not stuck behind later ones', () async {
    final gate = PageThumbRenderGate(concurrency: 1);
    final hold = gate.acquire(priority: 5);
    await hold.ready;
    final earlier = gate.acquire(priority: 1);
    final later = gate.acquire(priority: 1);

    var laterReady = false;
    unawaited(later.ready.then((_) => laterReady = true));
    hold.release();
    await earlier.ready;
    await Future<void>.delayed(Duration.zero);
    expect(earlier.isHolding, isTrue);
    expect(laterReady, isFalse);
  });

  test('workspace columns follow the width breaks', () {
    expect(workspacePageColumnCount(479), 2);
    expect(workspacePageColumnCount(480), 3);
    expect(workspacePageColumnCount(719), 3);
    expect(workspacePageColumnCount(720), 4);
    expect(workspacePageColumnCount(899), 4);
    expect(workspacePageColumnCount(900), 5);
    expect(workspacePageColumnCount(1099), 5);
    expect(workspacePageColumnCount(1100), 6);
  });

  test('opening a long PDF only arms the visible window', () {
    const pages = 431;
    const columns = 4;
    const rowStride = 220.0;
    final window = workspaceThumbWindow(
      indexCount: pages,
      columns: columns,
      viewportHeight: 800,
      scrollOffset: 0,
      rowStride: rowStride,
    );
    expect(window.start, 0);
    expect(window.end, lessThan(40));
    expect(window.end, lessThan(pages));

    final scrolled = workspaceThumbWindow(
      indexCount: pages,
      columns: columns,
      viewportHeight: 800,
      scrollOffset: rowStride * 40,
      rowStride: rowStride,
    );
    expect(scrolled.start, greaterThan(100));
    expect(scrolled.end - scrolled.start, lessThan(40));
    expect(scrolled.end, lessThan(pages));
  });
}
