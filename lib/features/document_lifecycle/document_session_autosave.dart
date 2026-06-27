import 'dart:async';
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:flutter/material.dart';

/// Quiet period after the last edit before an autosave write.
const Duration kViewerAutosaveDebounce = Duration(seconds: 6);

typedef SessionCommitFn = Future<LocalFileRef?> Function({
  required BuildContext context,
  required FileStoragePort storage,
  required DocumentTabsController tabs,
  required DocumentSession session,
  required Uint8List bytes,
  required String successMessage,
  String? saveAsReason,
  String? suggestedName,
  bool quiet,
  bool silent,
});

/// Coalesces rapid in-place commits so the PDF viewer is not remounted on every
/// keystroke / stroke / preview rebuild.
class DocumentSessionAutosave {
  DocumentSessionAutosave();

  Timer? _timer;
  _PendingCommit? _pending;
  bool _flushing = false;
  SessionCommitFn? _commitFn;

  bool get hasPending => _pending != null;

  /// Wired once from [commitBytesToSession] to avoid circular imports.
  void bindCommit(SessionCommitFn fn) => _commitFn = fn;

  /// Schedules a write [kViewerAutosaveDebounce] after the last call.
  /// Each new schedule replaces prior pending bytes (latest wins).
  void schedule({
    required BuildContext context,
    required FileStoragePort storage,
    required DocumentTabsController tabs,
    required DocumentSession session,
    required Uint8List bytes,
    required String successMessage,
    String? saveAsReason,
    String? suggestedName,
    bool quiet = true,
    void Function(LocalFileRef? result)? onComplete,
  }) {
    _pending = _PendingCommit(
      context: context,
      storage: storage,
      tabs: tabs,
      session: session,
      bytes: bytes,
      successMessage: successMessage,
      saveAsReason: saveAsReason,
      suggestedName: suggestedName,
      quiet: quiet,
      onComplete: onComplete,
    );
    _timer?.cancel();
    _timer = Timer(kViewerAutosaveDebounce, () {
      unawaited(flush());
    });
  }

  /// Cancels a pending autosave without writing.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  /// Writes immediately if anything is pending (explicit Save / Apply).
  Future<LocalFileRef?> flush() async {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null || _flushing) return null;
    final commit = _commitFn;
    if (commit == null) return null;
    _flushing = true;
    try {
      if (!pending.context.mounted) return null;
      final result = await commit(
        context: pending.context,
        storage: pending.storage,
        tabs: pending.tabs,
        session: pending.session,
        bytes: pending.bytes,
        successMessage: pending.successMessage,
        saveAsReason: pending.saveAsReason,
        suggestedName: pending.suggestedName,
        quiet: pending.quiet,
        silent: true,
      );
      pending.onComplete?.call(result);
      return result;
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    cancel();
  }
}

class _PendingCommit {
  _PendingCommit({
    required this.context,
    required this.storage,
    required this.tabs,
    required this.session,
    required this.bytes,
    required this.successMessage,
    required this.saveAsReason,
    required this.suggestedName,
    required this.quiet,
    required this.onComplete,
  });

  final BuildContext context;
  final FileStoragePort storage;
  final DocumentTabsController tabs;
  final DocumentSession session;
  final Uint8List bytes;
  final String successMessage;
  final String? saveAsReason;
  final String? suggestedName;
  final bool quiet;
  final void Function(LocalFileRef? result)? onComplete;
}

/// Shared autosave queue for the active viewer session.
final documentSessionAutosave = DocumentSessionAutosave();
