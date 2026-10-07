import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-005 — reorder pages via drag-and-drop or move controls, then export.
class ReorderToolScreen extends StatelessWidget {
  const ReorderToolScreen({super.key, this.initialFile, this.initialPassword});

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: 'reorder',
      initialFile: initialFile,
      initialPassword: initialPassword,
    );
  }
}
