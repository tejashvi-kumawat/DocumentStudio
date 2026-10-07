import 'package:flutter/material.dart';

/// DS-READ-005-A — non-destructive view rotation (does not modify the PDF file).
enum PdfViewerViewRotation { degrees0, degrees90, degrees180, degrees270 }

extension PdfViewerViewRotationX on PdfViewerViewRotation {
  int get quarterTurns => switch (this) {
    PdfViewerViewRotation.degrees0 => 0,
    PdfViewerViewRotation.degrees90 => 1,
    PdfViewerViewRotation.degrees180 => 2,
    PdfViewerViewRotation.degrees270 => 3,
  };

  String get statusLabel => switch (this) {
    PdfViewerViewRotation.degrees0 => '0°',
    PdfViewerViewRotation.degrees90 => '90°',
    PdfViewerViewRotation.degrees180 => '180°',
    PdfViewerViewRotation.degrees270 => '270°',
  };

  PdfViewerViewRotation rotatedClockwise90() => switch (this) {
    PdfViewerViewRotation.degrees0 => PdfViewerViewRotation.degrees90,
    PdfViewerViewRotation.degrees90 => PdfViewerViewRotation.degrees180,
    PdfViewerViewRotation.degrees180 => PdfViewerViewRotation.degrees270,
    PdfViewerViewRotation.degrees270 => PdfViewerViewRotation.degrees0,
  };
}

/// Applies [rotation] around the viewer center without altering document bytes.
Widget wrapPdfViewerWithViewRotation({
  required PdfViewerViewRotation rotation,
  required Widget child,
}) {
  if (rotation == PdfViewerViewRotation.degrees0) {
    return child;
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final maxH = constraints.maxHeight;
      final swap = rotation.quarterTurns.isOdd;
      final slotW = swap ? maxH : maxW;
      final slotH = swap ? maxW : maxH;
      return Center(
        child: SizedBox(
          width: slotW,
          height: slotH,
          child: RotatedBox(
            quarterTurns: rotation.quarterTurns,
            child: SizedBox(width: maxW, height: maxH, child: child),
          ),
        ),
      );
    },
  );
}
