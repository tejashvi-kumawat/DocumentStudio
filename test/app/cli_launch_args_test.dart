import 'package:document_studio/app/cli_launch_args.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses file path and --tool', () {
    final a = CliLaunchArgs.parse([
      '--tool',
      'compress',
      r'C:\tmp\missing-will-be-skipped.pdf',
    ]);
    expect(a.tool, 'compress');
    expect(a.viewerTool, ViewerToolId.compress);
    expect(a.files, isEmpty);
  });

  test('maps encrypt/decrypt aliases', () {
    expect(
      CliLaunchArgs.parse(['--tool', 'encrypt']).viewerTool,
      ViewerToolId.protect,
    );
    expect(
      CliLaunchArgs.parse(['--tool=decrypt']).viewerTool,
      ViewerToolId.unlock,
    );
  });

  test('detects image extensions', () {
    expect(CliLaunchArgs.isImagePath(r'C:\a.PNG'), isTrue);
    expect(CliLaunchArgs.isPdfPath(r'C:\a.pdf'), isTrue);
    expect(CliLaunchArgs.isImagePath(r'C:\a.pdf'), isFalse);
  });
}
