import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Scan to PDF: camera capture is not built in, so this page says so plainly
/// and routes to the flows that work today (photos → PDF → searchable PDF).
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    Widget step(int n, String title, String body, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(bottom: DsSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: DsColors.primary.withValues(alpha: 0.12),
              child: Text(
                '$n',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: DsColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: secondary),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DsToolPage(
      title: 'Scan to PDF',
      subtitle: 'Turn photos of paper documents into a PDF.',
      icon: Icons.document_scanner_outlined,
      iconColor: const Color(0xFF10B981),
      primaryLabel: 'Choose photos',
      primaryIcon: Icons.add_photo_alternate_outlined,
      onPrimary: () => context.push('$imagesToPdfRoutePath?format=scan'),
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DsToolResultCard(
            title: 'Camera capture is not built in yet',
            message: 'Take photos with your phone or scanner app, then combine '
                'them here. Everything stays on this device.',
            tone: DsResultTone.info,
          ),
          DsToolSection(
            title: 'How it works',
            child: Column(
              children: [
                step(
                  1,
                  'Add your photos',
                  'JPEG, PNG, WebP, TIFF or BMP — one photo per page.',
                  Icons.photo_library_outlined,
                ),
                step(
                  2,
                  'Order and size the pages',
                  'Drag pages into order and pick A4, Letter or fit-to-image.',
                  Icons.reorder_rounded,
                ),
                step(
                  3,
                  'Make the text searchable (optional)',
                  'Run OCR on the new PDF so you can select and search it.',
                  Icons.manage_search_rounded,
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Shortcuts',
            child: Wrap(
              spacing: DsSpacing.sm,
              runSpacing: DsSpacing.sm,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.collections_outlined, size: 16),
                  label: const Text('Images to PDF'),
                  onPressed: () => context.push(imagesToPdfRoutePath),
                ),
                ActionChip(
                  avatar: const Icon(Icons.manage_search_rounded, size: 16),
                  label: const Text('Searchable PDF (OCR)'),
                  onPressed: () => context.push(searchablePdfRoutePath),
                ),
                ActionChip(
                  avatar: const Icon(Icons.note_add_outlined, size: 16),
                  label: const Text('Create PDF from text'),
                  onPressed: () => context.push(createPdfRoutePath),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
