import 'dart:io';

import 'package:document_studio/app/bootstrap.dart';
import 'package:document_studio/app/cli_maintenance.dart';

Future<void> main(List<String> args) async {
  // Flutter desktop usually puts argv in Platform.executableArguments;
  // prefer explicit main args when the embedder passes them.
  final argv = args.isNotEmpty ? args : Platform.executableArguments;
  if (await tryHandleMaintenanceArgs(argv)) {
    return;
  }
  await bootstrap();
}
