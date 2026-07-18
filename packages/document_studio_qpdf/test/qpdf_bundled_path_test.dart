import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  tearDown(resetQpdfCliCapabilityCacheForTests);

  test('bundled engines/qpdf is listed before a PATH fallback', () async {
    const exe = '/opt/document-studio/document_studio';
    final bundled = p.normalize('/opt/document-studio/engines/qpdf');
    final paths = qpdfBundledCandidatePaths(executablePath: exe);
    expect(paths.first, bundled);
    expect(
      paths,
      contains(p.normalize('/opt/Resources/engines/qpdf')),
    );

    final resolved = await resolvedQpdfExecutable(
      executablePath: exe,
      fileExists: (path) => path == bundled,
    );
    expect(resolved, bundled);
  });

  test('extra search roots are checked before the bare PATH name', () async {
    debugQpdfExtraSearchRoots = ['/home/me/support/engines'];
    final resolved = await resolvedQpdfExecutable(
      executablePath: '/tmp/app/document_studio',
      fileExists: (path) =>
          path == p.normalize('/home/me/support/engines/qpdf'),
    );
    expect(resolved, p.normalize('/home/me/support/engines/qpdf'));
  });
}
