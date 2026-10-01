/// Output page index labels for [OrganizeExportPreviewDialog] (DS-ORG-014).
List<String> buildOrganizeExportPreviewLabels(int pageCount) {
  return List.generate(pageCount, (i) => '${i + 1}');
}

enum OrganizeExportPreviewOrderMode { all, truncated }

/// Chip list + optional summary for long exports in the preview dialog.
class OrganizeExportPreviewOrderModel {
  const OrganizeExportPreviewOrderModel({
    required this.mode,
    required this.chipLabels,
    this.summaryText,
  });

  final OrganizeExportPreviewOrderMode mode;
  final List<String> chipLabels;
  final String? summaryText;
}

const organizeExportPreviewCompactMax = 24;
const organizeExportPreviewTruncatedHead = 10;
const organizeExportPreviewTruncatedTail = 6;

OrganizeExportPreviewOrderModel modelOrganizeExportPreviewOrder(
  List<String> labels, {
  int compactMax = organizeExportPreviewCompactMax,
  int headCount = organizeExportPreviewTruncatedHead,
  int tailCount = organizeExportPreviewTruncatedTail,
}) {
  if (labels.length <= compactMax) {
    return OrganizeExportPreviewOrderModel(
      mode: OrganizeExportPreviewOrderMode.all,
      chipLabels: labels,
    );
  }
  final head = labels.take(headCount).toList();
  final tail = labels.skip(labels.length - tailCount).toList();
  return OrganizeExportPreviewOrderModel(
    mode: OrganizeExportPreviewOrderMode.truncated,
    chipLabels: [...head, ...tail],
    summaryText: 'Pages 1–${labels.length} (${labels.length} total)',
  );
}
