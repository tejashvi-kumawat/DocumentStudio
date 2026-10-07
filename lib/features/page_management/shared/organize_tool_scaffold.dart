import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';
import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared chrome for individual organize tools.
class OrganizeToolScaffold extends StatelessWidget {
  const OrganizeToolScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.body,
    this.busy = false,
    this.statusMessage,
    this.progress,
    this.onCancel,
  });

  final String title;
  final String? subtitle;

  /// The tool's icon in the header; looked up from the tool catalog by
  /// [title] when not given.
  final IconData? icon;
  final List<Widget> actions;
  final Widget body;
  final bool busy;
  final String? statusMessage;
  final double? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final compact = dsUseCompactToolLayout(context);
    final controlH = DsSpacing.controlHeightComfortable;

    // Android / phone: primary actions as a full-width bottom bar (~48dp), not
    // squeezed into the app bar. Desktop keeps toolbar actions.
    final bottomActions = compact && actions.isNotEmpty
        ? Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DsSpacing.pagePaddingCompact,
                  DsSpacing.sm,
                  DsSpacing.pagePaddingCompact,
                  DsSpacing.sm,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        minimumSize: Size(double.infinity, controlH),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: DsSpacing.sm),
                        SizedBox(
                          height: controlH,
                          width: double.infinity,
                          child: actions[i],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          )
        : null;

    final toolIcon = icon ?? _catalogIcon(title);
    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              DsToolHeader(
                title: title,
                subtitle: subtitle,
                icon: toolIcon,
                compact: compact,
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => context.pop(),
                ),
                actions: bottomActions == null ? actions : const [],
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: bottomActions == null,
                  child: body,
                ),
              ),
              ?bottomActions,
            ],
          ),
        ),
        if (busy)
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (progress != null)
                        SizedBox(
                          width: 220,
                          child: LinearProgressIndicator(value: progress),
                        )
                      else
                        const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(statusMessage ?? 'Working…'),
                      if (onCancel != null) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: onCancel,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Icon of the catalog tool this title belongs to: its exact label, else
/// the tool whose name is the longest one the title contains ("Reverse page
/// order" → Reverse).
IconData _catalogIcon(String title) {
  final t = title.toLowerCase();
  for (final tool in OrganizeToolCatalog.tools) {
    if (tool.label.toLowerCase() == t) return tool.icon;
  }
  OrganizeToolDefinition? best;
  for (final tool in OrganizeToolCatalog.tools) {
    final key = tool.id.replaceAll('_', ' ');
    if (t.contains(key) && (best == null || key.length > best.id.length))
      best = tool;
  }
  return best?.icon ?? Icons.tune;
}

/// Tracks active export job for cancel button.
mixin OrganizeJobHost<T extends StatefulWidget> on State<T> {
  JobHandle<dynamic>? activeJob;

  void bindJob(JobHandle<dynamic> job) => setState(() => activeJob = job);

  void clearJob() => setState(() => activeJob = null);
}
