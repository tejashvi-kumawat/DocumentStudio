import 'dart:async';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/page_thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cached page thumbnail.
///
/// A finished PNG replaces the placeholder in the same turn it arrives. A
/// failed or timed-out render shows Retry. Decode size is the cell's logical
/// width times the device pixel ratio. [active] false (scrolled out of the
/// prefetch window) cancels the job and never leaves a spinner up.
class OrganizeCachedPageThumbnail extends ConsumerStatefulWidget {
  const OrganizeCachedPageThumbnail({
    super.key,
    required this.file,
    required this.pageNumber1Based,
    this.password,
    this.rotationDegrees = 0,
    this.fit = BoxFit.contain,
    this.loadingSize = 20,
    this.targetLogicalWidth,
    this.priority = 0,
    this.active = true,
  });

  final LocalFileRef file;
  final int pageNumber1Based;
  final String? password;
  final int rotationDegrees;
  final BoxFit fit;
  final double loadingSize;

  /// Logical width of the tile; multiplied by device pixel ratio for decode.
  /// When null, [LayoutBuilder] measures the parent once it has a real width.
  final double? targetLogicalWidth;

  /// Higher values run before other thumbnail renders (visible cells first).
  final int priority;

  /// When false, do not render and do not show a spinner.
  final bool active;

  @override
  ConsumerState<OrganizeCachedPageThumbnail> createState() =>
      _OrganizeCachedPageThumbnailState();
}

class _OrganizeCachedPageThumbnailState
    extends ConsumerState<OrganizeCachedPageThumbnail> {
  Uint8List? _bytes;
  String? _error;
  int _gen = 0;
  bool _pending = false;
  PageThumbJob? _job;
  void Function()? _jobListener;
  Timer? _slow;

  /// Width we last armed. Layout jitter under 64 device pixels does not
  /// start another paint (a scrollbar is wider than 8).
  double? _armedPx;

  static const _widthSlack = 64.0;

  String get _pageToken =>
      '${widget.file.path}#${widget.pageNumber1Based}#${widget.password ?? ''}';

  @override
  void dispose() {
    _gen++;
    _slow?.cancel();
    _detachJob(cancel: true);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrganizeCachedPageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.file.path != widget.file.path ||
        oldWidget.pageNumber1Based != widget.pageNumber1Based ||
        oldWidget.password != widget.password;
    if (identityChanged) {
      _cancelJob();
      _bytes = null;
      _error = null;
      _armedPx = null;
      return;
    }
    if (oldWidget.active && !widget.active) {
      _cancelJob();
    } else if (!oldWidget.active && widget.active) {
      _armedPx = null;
      _error = null;
    }
  }

  void _detachJob({required bool cancel}) {
    final job = _job;
    final listener = _jobListener;
    if (job != null && listener != null) job.removeListener(listener);
    _jobListener = null;
    if (cancel) job?.cancel();
    _job = null;
  }

  void _cancelJob() {
    _gen++;
    _pending = false;
    _slow?.cancel();
    _slow = null;
    _detachJob(cancel: true);
  }

  void _watch(PageThumbJob job, int gen) {
    _detachJob(cancel: false);
    _job = job;
    void listener() {
      if (!mounted || gen != _gen) return;
      if (job.isDecoding && _slow == null && _bytes == null && _error == null) {
        _slow = Timer(const Duration(seconds: 8), () {
          if (!mounted || gen != _gen || _bytes != null) return;
          if (!job.isDecoding) return;
          setState(() {
            _error ??= 'Could not render page ${widget.pageNumber1Based}';
          });
          _detachJob(cancel: true);
        });
      }
      setState(() {});
    }

    _jobListener = listener;
    job.addListener(listener);
    if (job.isDecoding) listener();
  }

  double? _widthPx(BoxConstraints constraints, double dpr) {
    final logical = widget.targetLogicalWidth ??
        (constraints.maxWidth.isFinite && constraints.maxWidth > 1
            ? constraints.maxWidth
            : null);
    if (logical == null || logical <= 1) return null;
    final snapped = ((logical * dpr) / 8).round() * 8;
    return snapped.clamp(64, 1600).toDouble();
  }

  void _schedule(double widthPx) {
    if (!widget.active) {
      if (_job != null) _cancelJob();
      return;
    }
    if (_bytes != null &&
        (_armedPx == null || (_armedPx! - widthPx).abs() < _widthSlack)) {
      _armedPx = widthPx;
      return;
    }
    final same = _armedPx != null && (_armedPx! - widthPx).abs() < _widthSlack;
    // Same width is in progress while a start is queued, a job exists, or
    // the cell already failed. A bailed schedule must be able to start again.
    if (same && (_pending || _job != null || _error != null)) return;
    _armedPx = widthPx;
    _error = null;
    _pending = true;
    final gen = ++_gen;
    _slow?.cancel();
    _slow = null;
    _detachJob(cancel: true);
    final priority = widget.priority;
    final token = _pageToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _gen || _pageToken != token || !widget.active) {
        if (mounted && gen == _gen) _pending = false;
        return;
      }
      _pending = false;
      _start(widthPx, gen, priority, token);
    });
  }

  void _start(double widthPx, int gen, int priority, String token) {
    final cache = ref.read(organizeThumbCacheProvider);
    final file = widget.file;
    final page = widget.pageNumber1Based;
    final password = widget.password;
    final peeked = cache.peek(file, page, password: password);
    if (!mounted || gen != _gen) return;
    if (peeked != null) {
      setState(() {
        _bytes = peeked;
        _error = null;
      });
      return;
    }
    final job = cache.begin(
      file,
      page,
      targetWidthPx: widthPx,
      password: password,
      priority: priority,
    );
    _watch(job, gen);
    unawaited(
      job.future.then((data) {
        if (!mounted || gen != _gen || _pageToken != token) return;
        _slow?.cancel();
        _slow = null;
        setState(() {
          if (data != null) {
            _bytes = data;
            _error = null;
          } else if (_bytes == null && !job.isCancelled) {
            _error = 'Could not render page $page';
          }
        });
      }),
    );
  }

  void _retry() {
    _cancelJob();
    _error = null;
    _bytes = null;
    _armedPx = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final widthPx = _widthPx(constraints, dpr);
        if (widthPx != null && widget.active && _bytes == null && _error == null) {
          final hit = ref.read(organizeThumbCacheProvider).peek(
                widget.file,
                widget.pageNumber1Based,
                password: widget.password,
              );
          if (hit != null) {
            _bytes = hit;
          }
        }
        if (widthPx != null) _schedule(widthPx);

        Widget img;
        if (_bytes != null) {
          img = Image.memory(
            _bytes!,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _RetryThumb(
              onRetry: _retry,
              color: theme.colorScheme.error,
            ),
          );
        } else if (_error != null) {
          img = _RetryThumb(
            onRetry: _retry,
            color: theme.colorScheme.error,
            message: _error,
          );
        } else if (widget.active && (_job?.isDecoding ?? false)) {
          img = Center(
            child: SizedBox(
              width: widget.loadingSize,
              height: widget.loadingSize,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        } else {
          img = const _QuietThumb();
        }
        if (widget.rotationDegrees != 0) {
          img = RotatedBox(
            quarterTurns: (widget.rotationDegrees ~/ 90) % 4,
            child: img,
          );
        }
        return img;
      },
    );
  }
}

class _QuietThumb extends StatelessWidget {
  const _QuietThumb();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.description_outlined,
        size: 22,
        color: Theme.of(context).hintColor,
      ),
    );
  }
}

class _RetryThumb extends StatelessWidget {
  const _RetryThumb({
    required this.onRetry,
    required this.color,
    this.message,
  });

  final VoidCallback onRetry;
  final Color color;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message ?? 'Could not render this page',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 18, color: color),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
