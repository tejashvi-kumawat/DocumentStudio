import 'package:document_studio/app/shell/shell_navigation_context.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps [shellNavigationContextProvider] aligned with open viewer tabs.
class ShellDocumentHandoffSync extends ConsumerWidget {
  const ShellDocumentHandoffSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(documentTabsControllerProvider);
    return _DocumentTabsHandoffListener(
      tabs: tabs,
      onTabsChanged: () {
        _scheduleShellHandoffSync(ref);
      },
      child: child,
    );
  }
}

void _scheduleShellHandoffSync(WidgetRef ref) {
  _ShellHandoffSyncScheduler.instance.schedule(ref);
}

class _ShellHandoffSyncScheduler {
  _ShellHandoffSyncScheduler._();
  static final instance = _ShellHandoffSyncScheduler._();

  bool _scheduled = false;
  WidgetRef? _pendingRef;

  void schedule(WidgetRef ref) {
    _pendingRef = ref;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final pending = _pendingRef;
      _pendingRef = null;
      if (pending == null) return;
      final tab = pending.read(documentTabsControllerProvider).activeTab;
      pending
          .read(shellNavigationContextProvider.notifier)
          .setActiveDocument(
            tab == null
                ? null
                : PdfDocumentRouteArgs(file: tab.file, password: tab.password),
          );
    });
  }
}

class _DocumentTabsHandoffListener extends StatefulWidget {
  const _DocumentTabsHandoffListener({
    required this.tabs,
    required this.onTabsChanged,
    required this.child,
  });

  final DocumentTabsController tabs;
  final VoidCallback onTabsChanged;
  final Widget child;

  @override
  State<_DocumentTabsHandoffListener> createState() =>
      _DocumentTabsHandoffListenerState();
}

class _DocumentTabsHandoffListenerState
    extends State<_DocumentTabsHandoffListener> {
  @override
  void initState() {
    super.initState();
    widget.tabs.addListener(widget.onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTabsChanged();
    });
  }

  @override
  void didUpdateWidget(covariant _DocumentTabsHandoffListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.tabs, widget.tabs)) return;
    oldWidget.tabs.removeListener(widget.onTabsChanged);
    widget.tabs.addListener(widget.onTabsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTabsChanged();
    });
  }

  @override
  void dispose() {
    widget.tabs.removeListener(widget.onTabsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
