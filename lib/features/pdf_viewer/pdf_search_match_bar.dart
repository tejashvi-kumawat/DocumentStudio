import 'dart:async';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/pdf_search_flow.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_text_layer_hints.dart';
import 'package:flutter/material.dart';

/// In-viewer find bar — query field, match index, prev/next, close (DS-READ-007).
class PdfSearchMatchBar extends StatefulWidget {
  const PdfSearchMatchBar({
    super.key,
    required this.matchCount,
    required this.currentIndex,
    required this.isSearching,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    required this.onSearch,
    this.onShowResults,
    this.onRunOcr,
    this.matchCase = false,
    this.wholeWord = false,
    this.onOptionsChanged,
    this.initialQuery = '',
    this.autofocus = true,
    this.focusNode,
    this.ocrIndexing = false,
    this.fromOcrIndex = false,
  });

  final int matchCount;
  final int? currentIndex;
  final bool isSearching;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final ValueChanged<String> onSearch;

  /// Opens the whole-document results list (left panel).
  final VoidCallback? onShowResults;

  /// Offered when nothing was found: OCR never runs unless asked.
  final VoidCallback? onRunOcr;

  /// Find options. [onOptionsChanged] gets (matchCase, wholeWord).
  final bool matchCase;
  final bool wholeWord;
  final void Function(bool matchCase, bool wholeWord)? onOptionsChanged;
  final String initialQuery;
  final bool autofocus;

  /// When set (e.g. Ctrl+F), parent can [FocusNode.requestFocus] without remounting.
  final FocusNode? focusNode;
  final bool ocrIndexing;
  final bool fromOcrIndex;

  @override
  State<PdfSearchMatchBar> createState() => _PdfSearchMatchBarState();
}

class _PdfSearchMatchBarState extends State<PdfSearchMatchBar> {
  late final TextEditingController _queryController;
  FocusNode? _ownedFocusNode;
  Timer? _debounceTimer;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _queryController.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  String get statusLabel => pdfViewerFindStatusLabel(
    query: _queryController.text,
    matchCount: widget.matchCount,
    isSearching: widget.isSearching,
    currentIndex: widget.currentIndex,
    ocrIndexing: widget.ocrIndexing,
    fromOcrIndex: widget.fromOcrIndex,
  );

  void _submitQuery({bool immediate = false}) {
    final text = _queryController.text;
    if (immediate) {
      _debounceTimer?.cancel();
      widget.onSearch(text);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(kPdfSearchQueryDebounce, () {
      if (!mounted) return;
      widget.onSearch(_queryController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;
    final hasMatches = widget.matchCount > 0;

    return RepaintBoundary(
      child: Material(
        elevation: 0,
        color: isDark
            ? DsColors.surfaceContainerDark
            : DsColors.surfaceContainerLight,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('pdf_viewer_find_field'),
                  controller: _queryController,
                  focusNode: _focusNode,
                  style: theme.textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Find in document',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitQuery(immediate: true),
                  onChanged: (_) => _submitQuery(),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDark
                        ? DsColors.textSecondaryDark
                        : DsColors.textSecondaryLight,
                  ),
                ),
              ),
              if (widget.onOptionsChanged != null) ...[
                _OptionToggle(
                  label: 'Aa',
                  tooltip: 'Match case',
                  on: widget.matchCase,
                  onTap: () => widget.onOptionsChanged!(
                    !widget.matchCase,
                    widget.wholeWord,
                  ),
                ),
                _OptionToggle(
                  label: 'W',
                  tooltip: 'Whole words only',
                  on: widget.wholeWord,
                  onTap: () => widget.onOptionsChanged!(
                    widget.matchCase,
                    !widget.wholeWord,
                  ),
                ),
              ],
              IconButton(
                tooltip: 'Previous match',
                visualDensity: VisualDensity.compact,
                onPressed: hasMatches ? widget.onPrevious : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Next match',
                visualDensity: VisualDensity.compact,
                onPressed: hasMatches ? widget.onNext : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              if (widget.onRunOcr != null &&
                  !hasMatches &&
                  !widget.isSearching &&
                  _queryController.text.trim().length >= 2)
                TextButton.icon(
                  onPressed: widget.onRunOcr,
                  icon: const Icon(Icons.document_scanner_outlined, size: 16),
                  label: const Text('Scan with OCR'),
                ),
              if (widget.onShowResults != null)
                IconButton(
                  tooltip: 'Show all results',
                  onPressed: widget.matchCount > 0
                      ? widget.onShowResults
                      : null,
                  icon: const Icon(Icons.format_list_bulleted),
                ),
              TextButton(onPressed: widget.onClose, child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.tooltip,
    required this.on,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 26,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? DsColors.primary.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: on ? DsColors.primary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: on ? DsColors.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}
