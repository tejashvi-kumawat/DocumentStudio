import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-003 — extract selected pages to a new PDF.
class ExtractToolScreen extends StatelessWidget {
  const ExtractToolScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: 'extract',
      initialFile: initialFile,
      initialPassword: initialPassword,
    );
  }
}
