import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-006 — replace selected pages from another PDF, then export.
class ReplaceToolScreen extends StatelessWidget {
  const ReplaceToolScreen({super.key, this.initialFile});

  final LocalFileRef? initialFile;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(toolId: 'replace', initialFile: initialFile);
  }
}
