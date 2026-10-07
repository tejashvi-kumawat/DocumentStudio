import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:flutter/material.dart';

/// Where a captured scan is inserted into the open document.
enum ScanInsertAnchor { afterCurrent, start, end, afterNumber }

class ScanInsertChoice {
  const ScanInsertChoice({required this.anchor, this.afterPageNumber});

  final ScanInsertAnchor anchor;
  final int? afterPageNumber;
}

/// Page list for inserting [insertFile] into the open document.
///
/// [ScanInsertAnchor.start] places the new pages before page 1. The other
/// anchors insert after a 1-based page.
List<OrganizePageRef> pagesForScanInsert({
  required LocalFileRef document,
  required int totalPages,
  required int currentPage1,
  required LocalFileRef insertFile,
  required int insertPageCount,
  required ScanInsertAnchor anchor,
  int? afterPageNumber,
}) {
  if (anchor == ScanInsertAnchor.start) {
    return [
      for (var p = 1; p <= insertPageCount; p++)
        OrganizePageRef.fromFilePage(insertFile, p),
      ...buildDocumentPageList(document, totalPages),
    ];
  }
  final after = switch (anchor) {
    ScanInsertAnchor.end => totalPages,
    ScanInsertAnchor.afterCurrent => currentPage1.clamp(1, totalPages),
    ScanInsertAnchor.afterNumber => (afterPageNumber ?? currentPage1).clamp(
      1,
      totalPages,
    ),
    ScanInsertAnchor.start => 0,
  };
  return pagesForInsertAfterPage(
    file: document,
    totalPages: totalPages,
    afterPage1Based: after,
    insertFile: insertFile,
    insertPageCount: insertPageCount,
  );
}

String scanInsertSuccessMessage({
  required ScanInsertChoice choice,
  required int currentPage1,
  required int pageCount,
  required int insertedCount,
}) {
  final noun = insertedCount == 1 ? 'the scan' : '$insertedCount scan pages';
  switch (choice.anchor) {
    case ScanInsertAnchor.start:
      return 'Inserted $noun at the start.';
    case ScanInsertAnchor.end:
      return 'Inserted $noun at the end.';
    case ScanInsertAnchor.afterCurrent:
      final page = pageCount < 1
          ? currentPage1
          : currentPage1.clamp(1, pageCount);
      return 'Inserted $noun after page $page.';
    case ScanInsertAnchor.afterNumber:
      final raw = choice.afterPageNumber ?? currentPage1;
      final page = pageCount < 1 ? raw : raw.clamp(1, pageCount);
      return 'Inserted $noun after page $page.';
  }
}

/// Asks where the shot goes. Cancel returns null and must not change the PDF.
Future<ScanInsertChoice?> showScanInsertPlaceDialog({
  required BuildContext context,
  required int pageCount,
  required int currentPage1,
  String? previewPath,
  int imageCount = 1,
}) {
  return showDialog<ScanInsertChoice>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => ScanInsertPlaceDialog(
      pageCount: pageCount,
      currentPage1: currentPage1,
      previewPath: previewPath,
      imageCount: imageCount,
    ),
  );
}

class ScanInsertPlaceDialog extends StatefulWidget {
  const ScanInsertPlaceDialog({
    super.key,
    required this.pageCount,
    required this.currentPage1,
    this.previewPath,
    this.imageCount = 1,
  });

  final int pageCount;
  final int currentPage1;
  final String? previewPath;
  final int imageCount;

  @override
  State<ScanInsertPlaceDialog> createState() => _ScanInsertPlaceDialogState();
}

class _ScanInsertPlaceDialogState extends State<ScanInsertPlaceDialog> {
  ScanInsertAnchor _anchor = ScanInsertAnchor.afterCurrent;
  late final TextEditingController _pageField;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.pageCount < 1
        ? widget.currentPage1
        : widget.currentPage1.clamp(1, widget.pageCount);
    _pageField = TextEditingController(text: '$current');
  }

  @override
  void dispose() {
    _pageField.dispose();
    super.dispose();
  }

  void _confirm() {
    int? afterPage;
    if (_anchor == ScanInsertAnchor.afterNumber) {
      final parsed = int.tryParse(_pageField.text.trim());
      if (parsed == null || parsed < 1 || parsed > widget.pageCount) {
        setState(() {
          _error = 'Enter a page from 1 to ${widget.pageCount}.';
        });
        return;
      }
      afterPage = parsed;
    }
    Navigator.pop(
      context,
      ScanInsertChoice(anchor: _anchor, afterPageNumber: afterPage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.pageCount < 1
        ? widget.currentPage1
        : widget.currentPage1.clamp(1, widget.pageCount);
    final preview = widget.previewPath;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      key: const Key('insert_scan_place_dialog'),
      title: const Text('Where should this scan go?'),
      content: SizedBox(
        width: screenWidth > 440 ? 360 : screenWidth - 96,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nothing is added until you insert. Cancel leaves the PDF unchanged.',
                style: theme.textTheme.bodySmall,
              ),
              if (preview != null && preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ColoredBox(
                    color: const Color(0xFFF4F4F4),
                    child: SizedBox(
                      height: 140,
                      child: Image.file(
                        File(preview),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                if (widget.imageCount > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${widget.imageCount} images',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              RadioGroup<ScanInsertAnchor>(
                groupValue: _anchor,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _anchor = value;
                    _error = null;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<ScanInsertAnchor>(
                      key: const Key('insert_scan_place_after_current'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('After current page (page $current)'),
                      value: ScanInsertAnchor.afterCurrent,
                    ),
                    RadioListTile<ScanInsertAnchor>(
                      key: const Key('insert_scan_place_start'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('At the start'),
                      value: ScanInsertAnchor.start,
                    ),
                    RadioListTile<ScanInsertAnchor>(
                      key: const Key('insert_scan_place_end'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('At the end'),
                      value: ScanInsertAnchor.end,
                    ),
                    RadioListTile<ScanInsertAnchor>(
                      key: const Key('insert_scan_place_after_number'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('After a page number'),
                      value: ScanInsertAnchor.afterNumber,
                    ),
                  ],
                ),
              ),
              if (_anchor == ScanInsertAnchor.afterNumber)
                TextField(
                  key: const Key('insert_scan_place_page_field'),
                  controller: _pageField,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Page number',
                    helperText: '1 – ${widget.pageCount}',
                    errorText: _error,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _confirm(),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('insert_scan_place_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('insert_scan_place_confirm'),
          onPressed: _confirm,
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
