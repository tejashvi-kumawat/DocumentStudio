import 'dart:math' as math;

import 'package:document_studio/domain/pdf_stamp/helvetica_bold_metrics.dart';

/// Resolved geometry for a rubber-stamp label box (e.g. APPROVED).
///
/// Shared by the live preview painter and the PDF writer so the burned stamp
/// matches the preview: same box, font size, centered label, stroke and fill.
class StampLabelLayout {
  const StampLabelLayout({
    required this.leftNorm,
    required this.topNorm,
    required this.widthNorm,
    required this.heightNorm,
    required this.widthPt,
    required this.heightPt,
    required this.text,
    required this.fontSizePt,
    required this.textWidthPt,
  });

  static const double fillOpacity = 0.18;
  static const double strokeWidthPt = 1.5;
  static const double minWidthPt = 24;
  static const double minHeightPt = 12;

  /// Box in normalized visual page space (top-left origin).
  final double leftNorm;
  final double topNorm;
  final double widthNorm;
  final double heightNorm;

  final double widthPt;
  final double heightPt;
  final String text;
  final double fontSizePt;
  final double textWidthPt;

  double get centerXNorm => leftNorm + widthNorm / 2;
  double get centerYNorm => topNorm + heightNorm / 2;

  /// Baseline offset below the box center (points, y down).
  double get baselineBelowCenterPt =>
      fontSizePt * HelveticaBoldMetrics.baselineBelowCenterEm;
}

StampLabelLayout layoutStampLabel({
  required double leftNorm,
  required double topNorm,
  required double rightNorm,
  required double bottomNorm,
  required double pageWidthPt,
  required double pageHeightPt,
  required String label,
}) {
  final pw = math.max(pageWidthPt, 1.0);
  final ph = math.max(pageHeightPt, 1.0);
  final l = math.min(leftNorm, rightNorm).clamp(0.0, 1.0);
  final t = math.min(topNorm, bottomNorm).clamp(0.0, 1.0);
  var wN = (rightNorm - leftNorm).abs();
  var hN = (bottomNorm - topNorm).abs();
  wN = math.max(wN, StampLabelLayout.minWidthPt / pw).clamp(0.0, 1.0 - l);
  hN = math.max(hN, StampLabelLayout.minHeightPt / ph).clamp(0.0, 1.0 - t);
  final wPt = wN * pw;
  final hPt = hN * ph;

  var text = HelveticaBoldMetrics.sanitize(label).trim();
  if (text.isEmpty) text = 'APPROVED';
  final em = math.max(HelveticaBoldMetrics.widthEm(text), 0.01);
  final pad = math.min(6.0, wPt * 0.08);
  final byHeight = hPt * 0.5;
  final byWidth = (wPt - 2 * pad) / em;
  final fontSize = math.max(4.0, math.min(byHeight, byWidth));

  return StampLabelLayout(
    leftNorm: l,
    topNorm: t,
    widthNorm: wN,
    heightNorm: hN,
    widthPt: wPt,
    heightPt: hPt,
    text: text,
    fontSizePt: fontSize,
    textWidthPt: em * fontSize,
  );
}
