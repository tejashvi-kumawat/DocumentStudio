import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-006-B — insert blank pages at selection, then export.
class BlankPageToolScreen extends StatelessWidget {
  const BlankPageToolScreen({super.key, this.initialFile});

  final LocalFileRef? initialFile;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: 'blank-page',
      initialFile: initialFile,
    );
  }
}
