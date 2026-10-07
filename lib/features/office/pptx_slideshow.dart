import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/features/office/office_chrome.dart';
import 'package:document_studio/features/office/pptx_animation.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:document_studio/features/office/pptx_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens the slideshow at [start] (hidden slides are skipped).
Future<void> showPptxSlideshow(
  BuildContext context,
  PptxDocument doc, {
  int start = 0,
  bool presenter = false,
}) async {
  await Future.wait([PptxImages.preload(doc)]);
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) =>
          PptxSlideshow(doc: doc, start: start, presenter: presenter),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

Duration transitionDuration(PptxSlide s) => switch (s.transitionSpeed) {
  'fast' => const Duration(milliseconds: 450),
  'slow' => const Duration(milliseconds: 1100),
  _ => const Duration(milliseconds: 750),
};

/// The incoming slide's animation for [type] (PowerPoint transition names).
Widget transitionFor(
  String? type,
  String? dir,
  Animation<double> a,
  Widget child,
) {
  final c = CurvedAnimation(parent: a, curve: Curves.easeInOutCubic);
  Offset from() => switch (dir) {
    'r' => const Offset(-1, 0),
    'u' => const Offset(0, 1),
    'd' => const Offset(0, -1),
    _ => const Offset(1, 0), // from the right (dir l = moving left)
  };
  switch (type) {
    case null || 'none' || 'cut':
      return child;
    case 'push' || 'cover' || 'pull':
      return SlideTransition(
        position: Tween(begin: from(), end: Offset.zero).animate(c),
        child: child,
      );
    case 'wipe':
      return AnimatedBuilder(
        animation: c,
        builder: (_, w) => ClipRect(
          child: Align(
            alignment: dir == 'r'
                ? Alignment.centerLeft
                : (dir == 'u'
                      ? Alignment.bottomCenter
                      : (dir == 'd'
                            ? Alignment.topCenter
                            : Alignment.centerRight)),
            widthFactor: dir == 'u' || dir == 'd' ? 1 : c.value,
            heightFactor: dir == 'u' || dir == 'd' ? c.value : 1,
            child: w,
          ),
        ),
        child: child,
      );
    case 'split':
      return AnimatedBuilder(
        animation: c,
        builder: (_, w) => ClipRect(
          child: Align(
            alignment: Alignment.center,
            widthFactor: c.value,
            child: w,
          ),
        ),
        child: child,
      );
    case 'zoom':
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
          scale: Tween(begin: 0.6, end: 1.0).animate(c),
          child: child,
        ),
      );
    case 'circle':
      return AnimatedBuilder(
        animation: c,
        builder: (_, w) => ClipPath(clipper: _CircleReveal(c.value), child: w),
        child: child,
      );
    default:
      return FadeTransition(opacity: c, child: child);
  }
}

class _CircleReveal extends CustomClipper<Path> {
  _CircleReveal(this.t);
  final double t;

  @override
  Path getClip(Size size) {
    final r =
        math.sqrt(size.width * size.width + size.height * size.height) / 2 * t;
    return Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: r));
  }

  @override
  bool shouldReclip(_CircleReveal old) => old.t != t;
}

/// One slide that animates in with its own transition when [index] changes.
class PptxTransitionView extends StatelessWidget {
  const PptxTransitionView({
    super.key,
    required this.doc,
    required this.index,
    required this.width,
    this.decorate,
  });
  final PptxDocument doc;
  final int index;
  final double width;
  final Widget Function(PptxShape shape, Rect rect, Widget child)? decorate;

  @override
  Widget build(BuildContext context) {
    final slide = doc.slides[index];
    return AnimatedSwitcher(
      duration: slide.transition == null || slide.transition == 'cut'
          ? Duration.zero
          : transitionDuration(slide),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      transitionBuilder: (child, a) {
        final incoming = child.key == ValueKey(slide.path);
        if (!incoming) {
          // The outgoing slide stays put under the incoming one (fades for push).
          return slide.transition == 'push'
              ? FadeTransition(opacity: a, child: child)
              : child;
        }
        return transitionFor(slide.transition, slide.transitionDir, a, child);
      },
      child: KeyedSubtree(
        key: ValueKey(slide.path),
        child: PptxSlideView(
          doc: doc,
          slide: slide,
          width: width,
          decorate: decorate,
        ),
      ),
    );
  }
}

class PptxSlideshow extends StatefulWidget {
  const PptxSlideshow({
    super.key,
    required this.doc,
    required this.start,
    this.presenter = false,
  });
  final PptxDocument doc;
  final int start;
  final bool presenter;

  @override
  State<PptxSlideshow> createState() => _PptxSlideshowState();
}

class _PptxSlideshowState extends State<PptxSlideshow>
    with SingleTickerProviderStateMixin {
  /// Animation build steps of the current slide; [_step] of them played.
  late List<List<(PptxAnim, int)>> _steps = pptxAnimSteps(
    doc.slides[_i].animations,
  );
  int _step = 0;
  late final _anim = AnimationController(vsync: this);

  void _enterSlide({bool built = false}) {
    _steps = pptxAnimSteps(doc.slides[_i].animations);
    _anim.stop();
    if (built) {
      _step = _steps.length;
      _anim.value = 1;
    } else {
      _step = 0;
      // A first step that does not wait for a click plays on entry.
      if (_steps.isNotEmpty &&
          _steps.first.first.$1.trigger != PptxAnimTrigger.onClick) {
        Future<void>.delayed(transitionDuration(doc.slides[_i]), () {
          if (mounted && _step == 0) _playStep();
        });
      }
    }
  }

  void _playStep() {
    final len = pptxStepLength(_steps[_step]);
    setState(() => _step++);
    _anim
      ..duration = Duration(milliseconds: math.max(1, len))
      ..forward(from: 0);
  }

  Widget _decorate(PptxShape shape, Rect rect, Widget child) {
    if (_steps.isEmpty) return child;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => pptxAnimate(
        steps: _steps,
        shape: shape,
        child: child,
        step: _step,
        tMs: _anim.value * (_anim.duration?.inMilliseconds ?? 0),
        slide: _slideSize,
        rect: rect,
      ),
    );
  }

  Size _slideSize = Size.zero;
  PptxDocument get doc => widget.doc;
  late int _i = _visible(widget.start, 1);
  bool _ended = false;
  Color? _blank; // black / white screen
  late bool _presenter = widget.presenter;
  final _watch = Stopwatch()..start();
  Timer? _tick;
  Timer? _advance;
  Timer? _hideBar;
  bool _showBar = false;
  String _typed = '';
  double _notesScale = 1;

  @override
  void initState() {
    super.initState();
    _enterSlide();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _presenter) setState(() {});
    });
    _scheduleAdvance();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _anim.dispose();
    _advance?.cancel();
    _hideBar?.cancel();
    super.dispose();
  }

  /// First visible slide from [i] going in direction [step].
  int _visible(int i, int step) {
    var k = i.clamp(0, doc.slides.length - 1);
    while (k >= 0 && k < doc.slides.length && doc.slides[k].hidden) {
      k += step;
    }
    return k.clamp(0, doc.slides.length - 1);
  }

  void _scheduleAdvance() {
    _advance?.cancel();
    final ms = doc.slides[_i].advanceAfterMs;
    if (ms != null && !_ended)
      _advance = Timer(
        Duration(milliseconds: ms) + transitionDuration(doc.slides[_i]),
        () => _go(1),
      );
  }

  void _go(int d) {
    if (_blank != null) {
      setState(() => _blank = null);
      return;
    }
    if (!_ended && d > 0 && _step < _steps.length) {
      _anim.value = 1;
      _playStep();
      return;
    }
    if (!_ended && d < 0 && _step > 0) {
      setState(() => _step--);
      _anim.value = 1;
      return;
    }
    if (_ended) {
      if (d < 0) {
        setState(() => _ended = false);
      } else {
        Navigator.of(context).pop();
      }
      return;
    }
    var n = _i + d;
    while (n >= 0 && n < doc.slides.length && doc.slides[n].hidden) {
      n += d;
    }
    if (n >= doc.slides.length) {
      setState(() => _ended = true);
      return;
    }
    if (n < 0) return;
    setState(() => _i = n);
    _enterSlide(built: d < 0);
    _scheduleAdvance();
  }

  void _goTo(int index) {
    setState(() {
      _ended = false;
      _i = index.clamp(0, doc.slides.length - 1);
    });
    _enterSlide();
    _scheduleAdvance();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _typed += ch;
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter && _typed.isNotEmpty) {
      _goTo(int.parse(_typed) - 1);
      _typed = '';
      return KeyEventResult.handled;
    }
    _typed = '';
    if (<LogicalKeyboardKey>{
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.keyN,
    }.contains(k)) {
      _go(1);
    } else if (<LogicalKeyboardKey>{
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.keyP,
    }.contains(k)) {
      _go(-1);
    } else if (k == LogicalKeyboardKey.home) {
      _goTo(_visible(0, 1));
    } else if (k == LogicalKeyboardKey.end) {
      _goTo(_visible(doc.slides.length - 1, -1));
    } else if (k == LogicalKeyboardKey.keyB || k == LogicalKeyboardKey.period) {
      setState(() => _blank = _blank == null ? Colors.black : null);
    } else if (k == LogicalKeyboardKey.keyW || k == LogicalKeyboardKey.comma) {
      setState(() => _blank = _blank == null ? Colors.white : null);
    } else if (k == LogicalKeyboardKey.keyS && !_presenter) {
      setState(() => _presenter = true);
    } else if (k == LogicalKeyboardKey.keyA && _presenter) {
      setState(() => _presenter = false);
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _pokeBar() {
    if (!_showBar) setState(() => _showBar = true);
    _hideBar?.cancel();
    _hideBar = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showBar = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _presenter ? _presenterView() : _audience(),
      ),
    );
  }

  Widget _stage(double w) {
    if (_ended) {
      return SizedBox(
        width: w,
        height: w / doc.aspect,
        child: const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'End of slideshow. Click to exit.',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ),
        ),
      );
    }
    _slideSize = Size(w, w / doc.aspect);
    return Stack(
      children: [
        PptxTransitionView(doc: doc, index: _i, width: w, decorate: _decorate),
        if (_blank != null) Positioned.fill(child: ColoredBox(color: _blank!)),
      ],
    );
  }

  Widget _audience() {
    return MouseRegion(
      onHover: (_) => _pokeBar(),
      cursor: _showBar ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: GestureDetector(
        onTap: () => _go(1),
        onSecondaryTap: () => _go(-1),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth / c.maxHeight > doc.aspect)
                ? c.maxHeight * doc.aspect
                : c.maxWidth;
            return Stack(
              children: [
                Center(child: _stage(w)),
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: AnimatedOpacity(
                    opacity: _showBar ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _controlBar(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _controlBar() => Material(
    color: const Color(0xCC202124),
    borderRadius: BorderRadius.circular(22),
    child: IconTheme(
      data: const IconThemeData(color: Colors.white, size: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _go(-1),
          ),
          Text(
            '${_i + 1} / ${doc.slides.length}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _go(1),
          ),
          IconButton(
            tooltip: 'Black screen (B)',
            icon: const Icon(Icons.dark_mode_outlined),
            onPressed: () => setState(() => _blank = Colors.black),
          ),
          IconButton(
            tooltip: 'Presenter view (S)',
            icon: const Icon(Icons.co_present_outlined),
            onPressed: () => setState(() => _presenter = true),
          ),
          IconButton(
            tooltip: 'Exit (Esc)',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );

  String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _presenterView() {
    final slide = doc.slides[_i];
    var next = _i + 1;
    while (next < doc.slides.length && doc.slides[next].hidden) {
      next++;
    }
    final now = TimeOfDay.now();
    const fg = Colors.white;
    return Container(
      color: const Color(0xFF202124),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _watch.isRunning ? 'Pause timer' : 'Resume timer',
                color: fg,
                icon: Icon(_watch.isRunning ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(
                  () => _watch.isRunning ? _watch.stop() : _watch.start(),
                ),
              ),
              Text(
                _clock(_watch.elapsed),
                style: const TextStyle(
                  color: fg,
                  fontSize: 22,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                tooltip: 'Reset timer',
                color: fg,
                icon: const Icon(Icons.replay),
                onPressed: () => setState(() => _watch.reset()),
              ),
              const Spacer(),
              Text(
                now.format(context),
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(width: 18),
              TextButton.icon(
                onPressed: () => setState(() => _presenter = false),
                icon: const Icon(Icons.fullscreen, color: fg),
                label: const Text(
                  'Audience view (A)',
                  style: TextStyle(color: fg),
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: fg),
                label: const Text('End show', style: TextStyle(color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = math.min(
                        c.maxWidth,
                        (c.maxHeight - 60) * doc.aspect,
                      );
                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () => _go(1),
                            child: _stage(w),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                color: fg,
                                icon: const Icon(Icons.chevron_left),
                                onPressed: () => _go(-1),
                              ),
                              Text(
                                'Slide ${_i + 1} of ${doc.slides.length}',
                                style: const TextStyle(color: fg),
                              ),
                              IconButton(
                                color: fg,
                                icon: const Icon(Icons.chevron_right),
                                onPressed: () => _go(1),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, c) {
                          if (next >= doc.slides.length) {
                            return Container(
                              width: c.maxWidth,
                              height: c.maxWidth / doc.aspect,
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: const Text(
                                'End of slideshow',
                                style: TextStyle(color: Colors.white54),
                              ),
                            );
                          }
                          return PptxSlideView(
                            doc: doc,
                            slide: doc.slides[next],
                            width: c.maxWidth,
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text(
                            'Speaker notes',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const Spacer(),
                          IconButton(
                            color: fg,
                            tooltip: 'Smaller',
                            icon: const Icon(Icons.text_decrease, size: 18),
                            onPressed: () => setState(
                              () => _notesScale = (_notesScale - 0.15).clamp(
                                0.6,
                                3,
                              ),
                            ),
                          ),
                          IconButton(
                            color: fg,
                            tooltip: 'Larger',
                            icon: const Icon(Icons.text_increase, size: 18),
                            onPressed: () => setState(
                              () => _notesScale = (_notesScale + 0.15).clamp(
                                0.6,
                                3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2E31),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              slide.notes.isEmpty
                                  ? 'No speaker notes for this slide.'
                                  : slide.notes,
                              style: TextStyle(
                                color: slide.notes.isEmpty
                                    ? Colors.white38
                                    : fg,
                                fontSize: 18 * _notesScale,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: doc.slides.length,
              itemBuilder: (context, k) => GestureDetector(
                onTap: () => _goTo(k),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: k == _i ? kSlidesAccent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Opacity(
                    opacity: doc.slides[k].hidden ? 0.35 : 1,
                    child: PptxSlideView(
                      doc: doc,
                      slide: doc.slides[k],
                      width: 60 * doc.aspect,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
