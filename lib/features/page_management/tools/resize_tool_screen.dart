import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/page_box_qpdf_tool_shared.dart';
import 'package:flutter/material.dart';

class ResizeToolScreen extends StatelessWidget {
  const ResizeToolScreen({super.key, this.initialFile});

  final LocalFileRef? initialFile;

  @override
  Widget build(BuildContext context) {
    final file = initialFile;
    return PageBoxQpdfToolScreen(
      mode: PageBoxQpdfToolMode.resize,
      launch: file == null ? null : PageBoxQpdfToolLaunch(file: file),
    );
  }
}
