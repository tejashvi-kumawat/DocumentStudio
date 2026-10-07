import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_route_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Legacy `/viewer` route: register tab and land on shell Home branch.
class ViewerShellEntry extends ConsumerStatefulWidget {
  const ViewerShellEntry({super.key, this.args, this.file, this.password});

  final ViewerRouteArgs? args;
  final LocalFileRef? file;
  final String? password;

  @override
  ConsumerState<ViewerShellEntry> createState() => _ViewerShellEntryState();
}

class _ViewerShellEntryState extends ConsumerState<ViewerShellEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final file = widget.args?.file ?? widget.file;
      if (file == null) {
        context.go('/');
        return;
      }
      final password = widget.args?.password ?? widget.password;
      await openPdfInDocumentTabs(ref, file, password: password);
      if (!mounted) return;
      goToShellHomeBranch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
