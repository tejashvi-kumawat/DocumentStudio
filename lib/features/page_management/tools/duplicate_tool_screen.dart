import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-006 — duplicate selected pages in place, then export.
class DuplicateToolScreen extends StatelessWidget {
  const DuplicateToolScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: 'duplicate',
      initialFile: initialFile,
      initialPassword: initialPassword,
    );
  }
}
