import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:flutter/material.dart';

/// Chrome header for an embedded viewer tool (close + title + document name).
///
/// Visual system: white surface, 13px labels, 8px rhythm, red primary, optional
/// pinned Apply, 200ms open fade/size.
class ViewerToolPanelChrome extends StatelessWidget {
  const ViewerToolPanelChrome({
    super.key,
    required this.title,
    required this.documentName,
    required this.onClose,
    required this.child,
    this.subtitle,
    this.applyLabel,
    this.onApply,
    this.applyEnabled = true,
    this.applyBusy = false,
  });

  final String title;
  final String documentName;
  final VoidCallback onClose;
  final Widget child;

  /// Shortcut hint or short guidance under the title.
  final String? subtitle;

  /// When set, pins a primary Apply button at the bottom of the rail.
  final String? applyLabel;
  final VoidCallback? onApply;
  final bool applyEnabled;
  final bool applyBusy;

  @visibleForTesting
  /// Acrobat options rail. Stays inside 320–400 so the document keeps the rest.
  static const panelWidth = viewerAcrobatOptionsWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? DsColors.borderDark : DsColors.borderLight;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * 12, 0),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final phone =
              maxW.isFinite && maxW > 0 && maxW < DsSpacing.breakpointCompact;
          final panelW = phone ? maxW : panelWidth;
          final surface = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              key: const Key('viewer_tool_panel'),
              color: surface,
              child: SizedBox(
                width: panelW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        DsSpacing.sm,
                        DsSpacing.xs,
                        DsSpacing.xs,
                        DsSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  documentName,
                                  key: const Key(
                                    'viewer_tool_panel_document_name',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Tooltip(
                            message: 'Back to document',
                            child: TextButton.icon(
                              key: const Key('viewer_tool_panel_close'),
                              onPressed: onClose,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: theme.colorScheme.onSurface,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Back'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(panelW, MediaQuery.sizeOf(context).height),
                        ),
                        child: child,
                      ),
                    ),
                    if (applyLabel != null && onApply != null)
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          DsSpacing.pagePaddingCompact,
                          DsSpacing.sm,
                          DsSpacing.pagePaddingCompact,
                          DsSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: surface,
                          border: Border(top: BorderSide(color: borderColor)),
                        ),
                        child: SizedBox(
                          height: phone
                              ? DsSpacing.controlHeightComfortable
                              : DsSpacing.controlHeightCompact,
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: applyEnabled && !applyBusy
                                ? onApply
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: DsColors.primary,
                              foregroundColor: DsColors.onPrimary,
                              disabledBackgroundColor: DsColors.primary
                                  .withValues(alpha: 0.35),
                            ),
                            child: Text(
                              applyBusy ? 'Working…' : applyLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
