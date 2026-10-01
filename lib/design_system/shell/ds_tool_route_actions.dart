import 'package:document_studio/app/shell/shell_navigation_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Secondary **Cancel** on tool forms — pops stack or returns to viewer handoff.
void handleDsToolFormCancel(BuildContext context, WidgetRef ref) {
  if (context.canPop()) {
    ref.read(shellNavigationContextProvider.notifier).clearToolReturn();
    context.pop();
    return;
  }
  final ret = ref.read(shellNavigationContextProvider).toolReturnViewer;
  if (ret != null) {
    ref.read(shellNavigationContextProvider.notifier).clearToolReturn();
    context.go('/viewer', extra: ret);
    return;
  }
  context.go('/');
}
