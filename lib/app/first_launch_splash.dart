import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:document_studio/app/cli_launch_args.dart';
import 'dart:async';

import 'package:document_studio/design_system/brand/ds_brand_assets.dart';
import 'package:document_studio/design_system/brand/ds_built_by.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:flutter/material.dart';

/// Timing for the cold-start brand splash (entrance + hold before fade).
abstract final class FirstLaunchSplashTiming {
  /// Logo fade / scale / settle.
  static const logoIntro = Duration(milliseconds: 420);

  /// Delay before the brand underline starts drawing.
  static const underlineDelay = Duration(milliseconds: 280);

  /// Underline width draw.
  static const underline = Duration(milliseconds: 260);

  /// When the full-window splash begins fading out (~0.9 s on screen).
  static const displayUntilFade = Duration(milliseconds: 700);

  /// Splash dismiss fade.
  static const fadeOut = Duration(milliseconds: 160);

  /// Home content fade + 8px rise after splash starts dismissing.
  static const contentReveal = DsMotion.contentReveal;
}

/// Full-window cold-start splash over [child]. Shown once per process.
///
/// Sequence: logo → red underline → splash fades while [child] fades in and
/// rises 8px (250ms easeOutCubic). No spinner, no bounce loop.
class FirstLaunchSplashHost extends StatefulWidget {
  const FirstLaunchSplashHost({
    required this.child,
    super.key,
  });

  final Widget child;

  /// Process-level gate: after the splash has been scheduled once, never again.
  static bool _seenThisProcess = false;

  @visibleForTesting
  static bool get debugSeenThisProcess => _seenThisProcess;

  @visibleForTesting
  static void debugResetSeenFlag() {
    _seenThisProcess = false;
  }

  @override
  State<FirstLaunchSplashHost> createState() => _FirstLaunchSplashHostState();
}

class _FirstLaunchSplashHostState extends State<FirstLaunchSplashHost>
    with TickerProviderStateMixin {
  static const double _logoHeight = 80;
  static const double _lockupWidth = 280;

  late final bool _playSplash;
  late final AnimationController _logoController;
  late final AnimationController _underlineController;
  late final AnimationController _fadeOutController;
  late final AnimationController _contentController;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoLift;
  late final Animation<double> _underlineWidth;
  late final Animation<double> _splashOpacity;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _contentLift;

  bool _overlayVisible = false;

  /// The first frame paints only the splash; the app tree (Home, sidebar,
  /// providers) mounts behind it one frame later so the window shows at once.
  bool _childMounted = true;
  Timer? _underlineTimer;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    // Off in Settings, or a file was opened from the desktop: go straight in.
    _playSplash = !FirstLaunchSplashHost._seenThisProcess &&
        AppPrefs.showSplash &&
        !CliLaunchArgs.fromProcess().hasWork;
    if (_playSplash) {
      FirstLaunchSplashHost._seenThisProcess = true;
      _overlayVisible = true;
      _childMounted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _childMounted = true);
      });
    }

    _logoController = AnimationController(
      vsync: this,
      duration: FirstLaunchSplashTiming.logoIntro,
    );
    _underlineController = AnimationController(
      vsync: this,
      duration: FirstLaunchSplashTiming.underline,
    );
    _fadeOutController = AnimationController(
      vsync: this,
      duration: FirstLaunchSplashTiming.fadeOut,
    );
    _contentController = AnimationController(
      vsync: this,
      duration: FirstLaunchSplashTiming.contentReveal,
      value: _playSplash ? 0 : 1,
    );

    final logoCurve = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    );
    _logoOpacity = logoCurve;
    _logoScale = Tween<double>(begin: 0.94, end: 1.0).animate(logoCurve);
    _logoLift = Tween<double>(begin: 12, end: 0).animate(logoCurve);

    _underlineWidth = CurvedAnimation(
      parent: _underlineController,
      curve: Curves.easeOutCubic,
    );

    _splashOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _fadeOutController,
        curve: Curves.easeOutCubic,
      ),
    );

    final contentCurve = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOutCubic,
    );
    _contentOpacity = contentCurve;
    _contentLift = Tween<double>(
      begin: DsMotion.revealRisePx,
      end: 0,
    ).animate(contentCurve);

    if (_playSplash) {
      _logoController.forward();
      _underlineTimer = Timer(FirstLaunchSplashTiming.underlineDelay, () {
        if (!mounted) return;
        _underlineController.forward();
      });
      _fadeOutController.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _overlayVisible = false);
        }
      });
      _fadeTimer = Timer(FirstLaunchSplashTiming.displayUntilFade, () {
        if (!mounted) return;
        _fadeOutController.forward();
        _contentController.forward();
      });
    }
  }

  @override
  void dispose() {
    _underlineTimer?.cancel();
    _fadeTimer?.cancel();
    _logoController.dispose();
    _underlineController.dispose();
    _fadeOutController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Widget _buildRevealedChild() {
    return AnimatedBuilder(
      animation: _contentController,
      builder: (context, child) {
        return Opacity(
          opacity: _contentOpacity.value,
          child: Transform.translate(
            offset: Offset(0, _contentLift.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_playSplash) {
      return widget.child;
    }

    if (!_overlayVisible) {
      return _buildRevealedChild();
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (_childMounted) _buildRevealedChild(),
        FadeTransition(
          opacity: _splashOpacity,
          child: AbsorbPointer(
            child: Material(
              color: DsColors.groupedBackgroundLight,
              child: Center(
                child: KeyedSubtree(
                  key: const Key('first_launch_splash'),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _logoController,
                      _underlineController,
                    ]),
                    builder: (context, _) {
                      return SizedBox(
                        width: _lockupWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.translate(
                              offset: Offset(0, _logoLift.value),
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: Opacity(
                                  opacity: _logoOpacity.value,
                                  child: Image.asset(
                                    DsBrandAssets
                                        .documentStudioLogoTransparent,
                                    height: _logoHeight,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      return Image.asset(
                                        DsBrandAssets.documentStudioLogo,
                                        height: _logoHeight,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                        errorBuilder: (context, error, stackTrace) {
                                          return SizedBox(
                                            height: _logoHeight,
                                            child: const Icon(
                                              Icons.description_outlined,
                                              size: 48,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: _lockupWidth *
                                    0.72 *
                                    _underlineWidth.value,
                                height: 2.5,
                                child: const ColoredBox(
                                  color: DsColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Opacity(
                              opacity: _underlineWidth.value,
                              child: const DsBuiltBy(
                                fontSize: 12.5,
                                link: false,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
