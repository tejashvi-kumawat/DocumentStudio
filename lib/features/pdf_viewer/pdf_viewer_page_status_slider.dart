import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Maps a 0-based slider index to a 1-based page number.
int pageNumberFromSliderIndex(int index, int pageCount) {
  if (pageCount < 1) return 1;
  return (index + 1).clamp(1, pageCount);
}

/// Maps the current 1-based page to a 0-based slider value.
double sliderIndexForPageNumber(int pageNumber, int pageCount) {
  if (pageCount <= 1) return 0;
  return (pageNumber.clamp(1, pageCount) - 1).toDouble();
}

/// Status-bar page slider (`DS-READ-009-B`).
class PdfViewerPageStatusSlider extends StatefulWidget {
  const PdfViewerPageStatusSlider({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  State<PdfViewerPageStatusSlider> createState() =>
      _PdfViewerPageStatusSliderState();
}

class _PdfViewerPageStatusSliderState extends State<PdfViewerPageStatusSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!widget.controller.isReady) {
          return const SizedBox.shrink();
        }
        final total = widget.controller.pageCount;
        if (total <= 1) {
          return const SizedBox.shrink();
        }
        final page = widget.controller.pageNumber ?? 1;
        final maxIndex = (total - 1).toDouble();
        final value = (_dragValue ?? sliderIndexForPageNumber(page, total))
            .clamp(0.0, maxIndex);

        return Semantics(
          slider: true,
          label: 'Page $page of $total',
          child: Slider(
            value: value,
            min: 0,
            max: maxIndex,
            divisions: total - 1,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              setState(() => _dragValue = null);
              unawaited(
                widget.controller.goToPage(
                  pageNumber: pageNumberFromSliderIndex(v.round(), total),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
