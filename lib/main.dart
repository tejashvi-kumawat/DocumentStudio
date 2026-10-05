import 'dart:io';

import 'package:document_studio/app/bootstrap.dart';
import 'package:document_studio/app/cli_launch_args.dart';
import 'package:document_studio/app/cli_maintenance.dart';
import 'package:document_studio/app/crash_guard.dart';

Future<void> main(List<String> args) async {
  // Flutter desktop usually puts argv in Platform.executableArguments;
  // prefer explicit main args when the embedder passes them.
  final argv = args.isNotEmpty ? args : Platform.executableArguments;
  if (await tryHandleMaintenanceArgs(argv)) {
    return;
  }
  // On Windows the shell's "Open with" path arrives only in main's args.
  CliLaunchArgs.entryArguments = argv;
  CrashGuard.run(() async {
    CrashGuard.install();
    await bootstrap();
    CrashGuard.watchMemoryPressure(releaseMemory);
  });
}
