import 'dart:async';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Acrobat-style page indicator: an inline editable **n** box plus **/ N**.
///
/// Click selects the number, Enter jumps, Esc restores. [onGoToPage] stays as
/// the fallback (dialog) when there is no controller to drive directly.
class PdfViewerAcrobatPageField extends StatefulWidget {
  const PdfViewerAcrobatPageField({
    super.key,
    this.controller,
    required this.onGoToPage,
    this.fieldHeight = 26,
  });

  final PdfViewerController? controller;
  final VoidCallback onGoToPage;
  final double fieldHeight;

  @override
  State<PdfViewerAcrobatPageField> createState() =>
      _PdfViewerAcrobatPageFieldState();
}

class _PdfViewerAcrobatPageFieldState extends State<PdfViewerAcrobatPageField> {
  final TextEditingController _text = TextEditingController(text: '1');
  final FocusNode _focus = FocusNode(debugLabel: 'acrobat-page-field');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller?.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant PdfViewerAcrobatPageField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_sync);
      widget.controller?.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_sync);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  int get _page {
    final c = widget.controller;
    return c != null && c.isReady ? (c.pageNumber ?? 1) : 1;
  }

  int get _total {
    final c = widget.controller;
    return c != null && c.isReady ? c.pageCount : 1;
  }

  void _sync() {
    if (!mounted) return;
    // The controller can notify during layout; never rebuild mid-frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
      return;
    }
    if (!_focus.hasFocus && _text.text != '$_page') {
      _text.text = '$_page';
    }
    setState(() {});
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    } else {
      _text.text = '$_page';
    }
  }

  void _submit() {
    final c = widget.controller;
    final n = int.tryParse(_text.text.trim());
    if (c != null && c.isReady && n != null) {
      c.textSelectionDelegate.clearTextSelection();
      unawaited(c.goToPage(pageNumber: n.clamp(1, c.pageCount)));
    }
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;
    final c = widget.controller;
    final enabled = c != null && c.isReady;
    final style = theme.textTheme.labelMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: 'Page $_page of $_total',
      enabled: enabled,
      child: Tooltip(
        message: 'Go to page (Ctrl+Shift+N)',
        child: Container(
          key: const Key('pdf_viewer_acrobat_page_field'),
          height: widget.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 8.0 + 8 * '$_total'.length,
                child: Focus(
                  onKeyEvent: (node, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.escape) {
                      _focus.unfocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    enabled: enabled,
                    textAlign: TextAlign.end,
                    style: style,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration.collapsed(hintText: ''),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              Text(' / $_total', style: style),
            ],
          ),
        ),
      ),
    );
  }
}
