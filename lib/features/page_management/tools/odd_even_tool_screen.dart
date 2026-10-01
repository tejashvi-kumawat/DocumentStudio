import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_workspace_tool_screen.dart';
import 'package:flutter/material.dart';

/// DS-ORG-010 — export odd- or even-numbered pages (1-based positions) to a new PDF.
class OddEvenToolScreen extends StatelessWidget {
  const OddEvenToolScreen({
    super.key,
    required this.odd,
    this.initialFile,
    this.initialPassword,
  });

  final bool odd;
  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  Widget build(BuildContext context) {
    return PageWorkspaceToolScreen(
      toolId: odd ? 'odd-pages' : 'even-pages',
      initialFile: initialFile,
      initialPassword: initialPassword,
    );
  }
}
