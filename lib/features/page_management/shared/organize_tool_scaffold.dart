import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared chrome for individual organize tools.
class OrganizeToolScaffold extends StatelessWidget {
  const OrganizeToolScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.body,
    this.busy = false,
    this.statusMessage,
    this.progress,
    this.onCancel,
  });

  final String title;
  final String? subtitle;
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

    return Stack(
      children: [
        Scaffold(
          appBar: DsToolbar(
            dense: compact,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: title,
            subtitle: subtitle,
            actions: bottomActions == null ? actions : const [],
          ),
          body: SafeArea(
            top: false,
            bottom: bottomActions == null,
            child: body,
          ),
          bottomNavigationBar: bottomActions,
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
                        TextButton(onPressed: onCancel, child: const Text('Cancel')),
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

/// Tracks active export job for cancel button.
mixin OrganizeJobHost<T extends StatefulWidget> on State<T> {
  JobHandle<dynamic>? activeJob;

  void bindJob(JobHandle<dynamic> job) => setState(() => activeJob = job);

  void clearJob() => setState(() => activeJob = null);
}
