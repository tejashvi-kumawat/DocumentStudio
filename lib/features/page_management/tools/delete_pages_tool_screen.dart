import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-004 — remove selected pages and save the remaining PDF.
class DeletePagesToolScreen extends StatelessWidget {
  const DeletePagesToolScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: 'delete',
      initialFile: initialFile,
      initialPassword: initialPassword,
    );
  }
}
