import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/image_viewer/image_viewer_route.dart';
import 'package:document_studio/features/image_tools/image_tools_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OcrEngineBlockedPanel extends StatelessWidget {
  const OcrEngineBlockedPanel({
    super.key,
    this.reason,
    this.searchablePdf = false,
  });

  final String? reason;
  final bool searchablePdf;

  @override
  Widget build(BuildContext context) {
    return OcrEngineStatusPanel(
      portBlocked: true,
      searchablePdf: searchablePdf,
      blockedReason: reason,
    );
  }
}

/// Inline warning card for a missing OCR binary / language (with re-check).
class OcrEngineStatusPanel extends StatelessWidget {
  const OcrEngineStatusPanel({
    super.key,
    required this.portBlocked,
    this.searchablePdf = false,
    this.blockedReason,
    this.onRecheck,
  });

  final bool portBlocked;
  final bool searchablePdf;
  final String? blockedReason;
  final VoidCallback? onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final raw = blockedReason ??
        (searchablePdf
            ? BlockedSearchablePdfPort.blockedReason
            : BlockedOcrPort.blockedReason);
    final lower = raw.toLowerCase();
    final message = raw.length > 160 ||
            lower.contains('qpdf') ||
            lower.contains('[b]') ||
            lower.contains('engines/')
        ? (searchablePdf
            ? 'Searchable PDF isn’t ready on this device yet.'
            : 'Text recognition isn’t ready on this device yet.')
        : raw;
    return Container(
      padding: const EdgeInsets.all(DsSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: DsSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  searchablePdf
                      ? 'Searchable PDF isn’t ready'
                      : 'OCR isn’t ready',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: DsSpacing.xs),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: DsSpacing.xs),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    invalidateOcrEngineEnvironment();
                    onRecheck?.call();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Check again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quality presets mapped to render DPI.
const kOcrQualityPresets = <({int dpi, String label, String hint})>[
  (dpi: 200, label: 'Fast', hint: '200 dpi · large, clean print'),
  (dpi: 300, label: 'Balanced', hint: '300 dpi · recommended for most scans'),
  (dpi: 400, label: 'Best', hint: '400 dpi · small or dense text'),
];

/// Language chips (installed traineddata only), quality, and preprocessing.
///
/// [searchablePdf] hides deskew (it would misalign the text layer) and shows
/// the skip-existing-text switch instead.
class OcrOptionsPanel extends StatefulWidget {
  const OcrOptionsPanel({
    super.key,
    required this.options,
    required this.onChanged,
    this.busy = false,
    this.searchablePdf = false,
  });

  final OcrOptions options;
  final ValueChanged<OcrOptions> onChanged;
  final bool busy;
  final bool searchablePdf;

  @override
  State<OcrOptionsPanel> createState() => _OcrOptionsPanelState();
}

class _OcrOptionsPanelState extends State<OcrOptionsPanel> {
  late Future<OcrEngineEnvironment> _env;

  OcrCancelToken? _osdDownload;
  double? _osdProgress;
  String? _osdError;

  @override
  void initState() {
    super.initState();
    _env = loadOcrEngineEnvironment();
    ocrPreferredLanguage = widget.options.language;
  }

  @override
  void didUpdateWidget(covariant OcrOptionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.language != widget.options.language) {
      ocrPreferredLanguage = widget.options.language;
    }
  }

  @override
  void dispose() {
    _osdDownload?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() => _env = loadOcrEngineEnvironment(refresh: true));
  }

  void _toggleLanguage(String code, bool selected) {
    final codes = List<String>.of(widget.options.languageCodes);
    if (selected) {
      if (!codes.contains(code)) codes.add(code);
    } else {
      if (codes.length <= 1) return;
      codes.remove(code);
    }
    widget.onChanged(widget.options.copyWith(language: codes.join('+')));
  }

  Future<void> _addLanguages(List<String> installed) async {
    final added = await showOcrLanguageDownloadDialog(
      context,
      installed: installed,
    );
    if (!mounted || added.isEmpty) return;
    _refresh();
    final codes = List<String>.of(widget.options.languageCodes);
    for (final c in added) {
      if (!codes.contains(c)) codes.add(c);
    }
    widget.onChanged(widget.options.copyWith(language: codes.join('+')));
  }

  Future<void> _downloadOsd() async {
    final token = OcrCancelToken();
    setState(() {
      _osdDownload = token;
      _osdProgress = null;
      _osdError = null;
    });
    try {
      await downloadOcrLanguageData(
        'osd',
        cancelToken: token,
        onProgress: (f) {
          if (mounted) setState(() => _osdProgress = f);
        },
      );
      if (mounted) _refresh();
    } on OcrCancelledException {
      // User cancelled.
    } catch (e) {
      if (mounted) setState(() => _osdError = '$e');
    } finally {
      if (mounted && identical(_osdDownload, token)) {
        setState(() => _osdDownload = null);
      }
    }
  }

  Widget _osdNotice(ThemeData theme, TextStyle? hintStyle) {
    final downloading = _osdDownload != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: hintStyle?.color,
              ),
              const SizedBox(width: DsSpacing.xs),
              Expanded(
                child: Text(
                  _osdError ??
                      'Orientation data isn’t installed, so sideways or '
                          'upside-down pages won’t be turned.',
                  style: _osdError == null
                      ? hintStyle
                      : hintStyle?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : downloading
                        ? () => _osdDownload?.cancel()
                        : _downloadOsd,
                child: Text(
                  downloading
                      ? 'Cancel'
                      : 'Download (${kOcrLanguageDownloadMb['osd']} MB)',
                ),
              ),
            ],
          ),
          if (downloading)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: _osdProgress, minHeight: 3),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final o = widget.options;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: secondary,
    );
    final preset = kOcrQualityPresets.firstWhere(
      (p) => p.dpi == o.dpi,
      orElse: () => kOcrQualityPresets[1],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Document language', style: labelStyle),
            const Spacer(),
            IconButton(
              tooltip: 'Rescan installed languages',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: widget.busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        FutureBuilder<OcrEngineEnvironment>(
          future: _env,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: DsSpacing.sm),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            final env = snap.data!;
            final installed = env.installedLanguages;
            final selected = o.languageCodes;
            final codes = <String>{...installed, ...selected}.toList();
            return AnimatedSize(
              duration: DsMotion.switchDuration,
              curve: DsMotion.switchCurve,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: DsSpacing.xs,
                    runSpacing: DsSpacing.xs,
                    children: [
                      for (final code in codes)
                        FilterChip(
                          label: Text(ocrLanguageLabel(code)),
                          tooltip: installed.contains(code)
                              ? code
                              : '$code.traineddata is not installed',
                          selected: selected.contains(code),
                          showCheckmark: true,
                          avatar: installed.contains(code)
                              ? null
                              : Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: theme.colorScheme.error,
                                ),
                          onSelected: widget.busy
                              ? null
                              : (v) => _toggleLanguage(code, v),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Add languages'),
                        tooltip: 'Download OCR language data',
                        onPressed: widget.busy
                            ? null
                            : () => _addLanguages(installed),
                      ),
                    ],
                  ),
                  const SizedBox(height: DsSpacing.xs),
                  Text(
                    selected.length > 1
                        ? 'Recognizing ${selected.map(ocrLanguageLabel).join(' + ')}. '
                            'Select only the languages in the document for best speed.'
                        : 'Select every language that appears in the document.',
                    style: hintStyle,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: DsSpacing.md),
        Text('Recognition quality', style: labelStyle),
        const SizedBox(height: DsSpacing.xs),
        if (dsUseCompactToolLayout(context))
          Wrap(
            spacing: DsSpacing.sm,
            runSpacing: DsSpacing.sm,
            children: [
              for (final p in kOcrQualityPresets)
                ChoiceChip(
                  label: Text(p.label),
                  selected: preset.dpi == p.dpi,
                  showCheckmark: false,
                  onSelected: widget.busy
                      ? null
                      : (_) => widget.onChanged(o.copyWith(dpi: p.dpi)),
                ),
            ],
          )
        else
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final p in kOcrQualityPresets)
                ButtonSegment(value: p.dpi, label: Text(p.label)),
            ],
            selected: {preset.dpi},
            onSelectionChanged: widget.busy
                ? null
                : (s) => widget.onChanged(o.copyWith(dpi: s.first)),
          ),
        const SizedBox(height: DsSpacing.xs),
        Text(preset.hint, style: hintStyle),
        const SizedBox(height: DsSpacing.sm),
        if (widget.searchablePdf)
          _OcrSwitch(
            title: 'Skip pages that already have text',
            subtitle: 'Only scanned pages are recognized; digital pages stay '
                'untouched and processing is faster.',
            value: o.skipPagesWithText,
            onChanged: widget.busy
                ? null
                : (v) => widget.onChanged(o.copyWith(skipPagesWithText: v)),
          )
        else
          _OcrSwitch(
            title: 'Straighten skewed image',
            subtitle: 'Detects a tilted photo or scan and rotates it first.',
            value: o.deskew,
            onChanged: widget.busy
                ? null
                : (v) => widget.onChanged(o.copyWith(deskew: v)),
          ),
        _OcrSwitch(
          title: widget.searchablePdf
              ? 'Auto-rotate pages'
              : 'Detect text orientation',
          subtitle: widget.searchablePdf
              ? 'Sideways or upside-down scans are recognized and turned '
                  'upright.'
              : 'Reads sideways or upside-down text correctly.',
          value: o.autoRotate,
          onChanged: widget.busy
              ? null
              : (v) => widget.onChanged(o.copyWith(autoRotate: v)),
        ),
        FutureBuilder<OcrEngineEnvironment>(
          future: _env,
          builder: (context, snap) {
            final show = o.autoRotate &&
                snap.hasData &&
                snap.data!.hasTesseract &&
                (!snap.data!.hasOsd || _osdDownload != null);
            return AnimatedSize(
              duration: DsMotion.switchDuration,
              curve: DsMotion.switchCurve,
              alignment: Alignment.topCenter,
              child: show
                  ? _osdNotice(theme, hintStyle)
                  : const SizedBox(width: double.infinity),
            );
          },
        ),
        _OcrSwitch(
          title: 'Enhance faded scans',
          subtitle: 'Boosts contrast of gray or low-ink pages before '
              'recognition. The saved page image is not changed.',
          value: o.denoise,
          onChanged: widget.busy
              ? null
              : (v) => widget.onChanged(o.copyWith(denoise: v)),
        ),
      ],
    );
  }
}

class _OcrSwitch extends StatelessWidget {
  const _OcrSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DsAdaptiveSwitchTile(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Lets the user download traineddata for more languages. Resolves to the
/// codes that finished downloading.
Future<List<String>> showOcrLanguageDownloadDialog(
  BuildContext context, {
  required List<String> installed,
}) async {
  final added = await showDialog<List<String>>(
    context: context,
    builder: (_) => _OcrLanguageDownloadDialog(installed: installed),
  );
  return added ?? const [];
}

class _OcrLanguageDownloadDialog extends StatefulWidget {
  const _OcrLanguageDownloadDialog({required this.installed});

  final List<String> installed;

  @override
  State<_OcrLanguageDownloadDialog> createState() =>
      _OcrLanguageDownloadDialogState();
}

class _OcrLanguageDownloadDialogState
    extends State<_OcrLanguageDownloadDialog> {
  final _query = TextEditingController();
  final _downloads = <String, OcrCancelToken>{};
  final _progress = <String, double?>{};
  final _errors = <String, String>{};
  final _added = <String>[];

  @override
  void dispose() {
    for (final t in _downloads.values) {
      t.cancel();
    }
    _query.dispose();
    super.dispose();
  }

  Future<void> _download(String code) async {
    final token = OcrCancelToken();
    setState(() {
      _downloads[code] = token;
      _progress[code] = null;
      _errors.remove(code);
    });
    try {
      await downloadOcrLanguageData(
        code,
        cancelToken: token,
        onProgress: (f) {
          if (mounted) setState(() => _progress[code] = f);
        },
      );
      if (mounted) setState(() => _added.add(code));
    } on OcrCancelledException {
      // User cancelled.
    } catch (e) {
      if (mounted) setState(() => _errors[code] = '$e');
    } finally {
      if (mounted) setState(() => _downloads.remove(code));
    }
  }

  void _close() => Navigator.of(context).pop(List<String>.of(_added));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final q = _query.text.trim().toLowerCase();
    final codes = kOcrLanguageLabels.keys
        .where(
          (c) =>
              q.isEmpty ||
              c.contains(q) ||
              ocrLanguageLabel(c).toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => ocrLanguageLabel(a).compareTo(ocrLanguageLabel(b)));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: const Text('Add OCR languages'),
        content: SizedBox(
          width: 420,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search languages',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: DsSpacing.xs),
              Text(
                'Language data comes from tesseract-ocr/tessdata_fast and is '
                'saved to ${ocrUserTessdataDir()}.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
              const SizedBox(height: DsSpacing.xs),
              Expanded(
                child: ListView.builder(
                  itemCount: codes.length,
                  itemBuilder: (context, i) {
                    final code = codes[i];
                    final done = widget.installed.contains(code) ||
                        _added.contains(code);
                    final token = _downloads[code];
                    final error = _errors[code];
                    final size = kOcrLanguageDownloadMb[code];
                    Widget trailing;
                    if (done) {
                      trailing = const Icon(
                        Icons.check_circle,
                        color: Color(0xFF1E8E3E),
                        size: 20,
                      );
                    } else if (token != null) {
                      trailing = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _progress[code],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cancel',
                            iconSize: 18,
                            onPressed: token.cancel,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      );
                    } else {
                      trailing = IconButton(
                        tooltip: 'Download',
                        iconSize: 20,
                        onPressed: () => _download(code),
                        icon: const Icon(Icons.download_outlined),
                      );
                    }
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(ocrLanguageLabel(code)),
                      subtitle: Text(
                        error ??
                            (done
                                ? 'Installed'
                                : '$code · about ${size ?? 2} MB'),
                        style: error == null
                            ? null
                            : TextStyle(color: theme.colorScheme.error),
                      ),
                      trailing: AnimatedSwitcher(
                        duration: DsMotion.switchDuration,
                        child: KeyedSubtree(
                          key: ValueKey(
                            done ? 'd' : (token != null ? 'p' : 'i'),
                          ),
                          child: trailing,
                        ),
                      ),
                      onTap: done || token != null
                          ? null
                          : () => _download(code),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: _close,
            child: Text(_added.isEmpty ? 'Close' : 'Done'),
          ),
        ],
      ),
    );
  }
}

/// Animated determinate progress with page counter, ETA, and Cancel.
class OcrProgressCard extends StatefulWidget {
  const OcrProgressCard({
    super.key,
    required this.fraction,
    required this.message,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    this.onCancel,
    this.cancelling = false,
  });

  final double? fraction;
  final String message;
  final int pagesDone;
  final int pagesTotal;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  State<OcrProgressCard> createState() => _OcrProgressCardState();
}

class _OcrProgressCardState extends State<OcrProgressCard> {
  final Stopwatch _clock = Stopwatch()..start();

  String? _eta() {
    final done = widget.pagesDone;
    final total = widget.pagesTotal;
    if (done < 1 || total <= done) return null;
    final perPage = _clock.elapsed.inMilliseconds / done;
    final remaining = Duration(milliseconds: (perPage * (total - done)).round());
    if (remaining.inSeconds < 5) return 'A few seconds left';
    if (remaining.inMinutes < 1) return 'About ${remaining.inSeconds} s left';
    return 'About ${remaining.inMinutes + 1} min left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final eta = _eta();
    return Container(
      padding: const EdgeInsets.all(DsSpacing.md),
      decoration: BoxDecoration(
        color: DsColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DsColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: AnimatedSwitcher(
                  duration: DsMotion.switchDuration,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    widget.cancelling ? 'Cancelling…' : widget.message,
                    key: ValueKey(widget.cancelling ? '_c' : widget.message),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (widget.onCancel != null)
                TextButton(
                  onPressed: widget.cancelling ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          TweenAnimationBuilder<double>(
            tween: Tween(end: widget.fraction ?? 0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: widget.fraction == null ? null : value,
                minHeight: 6,
                backgroundColor: DsColors.primary.withValues(alpha: 0.12),
                color: DsColors.primary,
              ),
            ),
          ),
          const SizedBox(height: DsSpacing.xs),
          Row(
            children: [
              Text(
                widget.fraction == null
                    ? ''
                    : '${((widget.fraction ?? 0) * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
              const Spacer(),
              if (eta != null)
                Text(
                  eta,
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Success / info banner shown after an OCR job completes.
class OcrResultBanner extends StatelessWidget {
  const OcrResultBanner({
    super.key,
    required this.title,
    required this.details,
    this.icon = Icons.check_circle,
    this.color,
    this.actions = const [],
  });

  final String title;
  final String details;
  final IconData icon;
  final Color? color;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? const Color(0xFF1E8E3E);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.all(DsSpacing.md),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: DsSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DsSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                details,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: DsSpacing.sm),
              if (dsUseCompactToolLayout(context))
                Theme(
                  data: theme.copyWith(
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(
                          double.infinity,
                          DsSpacing.controlHeightComfortable,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          double.infinity,
                          DsSpacing.controlHeightComfortable,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: DsSpacing.sm),
                        actions[i],
                      ],
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Wrap(spacing: DsSpacing.xs, children: actions),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class OcrRelatedToolsPanel extends StatelessWidget {
  const OcrRelatedToolsPanel({
    super.key,
    this.busy = false,
    this.excludePath,
  });

  final bool busy;
  final String? excludePath;

  @override
  Widget build(BuildContext context) {
    void go(String path) {
      if (excludePath == path) return;
      context.push(path);
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Related tools',
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        Wrap(
          spacing: DsSpacing.xs,
          children: [
            if (excludePath != imageOcrRoutePath)
              TextButton.icon(
                onPressed: busy ? null : () => go(imageOcrRoutePath),
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text('Image OCR'),
              ),
            if (excludePath != searchablePdfRoutePath)
              TextButton.icon(
                onPressed: busy ? null : () => go(searchablePdfRoutePath),
                icon: const Icon(Icons.find_in_page_outlined, size: 18),
                label: const Text('Searchable PDF'),
              ),
            TextButton.icon(
              onPressed: busy ? null : () => context.push(imageViewerRoutePath),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Image viewer'),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => context.push(imageToolsRoutePath),
              icon: const Icon(Icons.photo_size_select_large_outlined, size: 18),
              label: const Text('Image tools'),
            ),
          ],
        ),
      ],
    );
  }
}
