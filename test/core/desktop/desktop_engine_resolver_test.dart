import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final previousRoots = List<String>.of(debugDesktopEngineExtraRoots);

  tearDown(() {
    debugDesktopEngineExtraRoots = List<String>.of(previousRoots);
  });

  test('engines/qpdf is chosen before PATH', () async {
    const exe = '/opt/document-studio/document_studio';
    final bundled = p.normalize('/opt/document-studio/engines/qpdf');
    final resolver = DesktopEngineResolver(
      executablePath: exe,
      fileExists: (path) => path == bundled,
      pathLookup: (_) async => fail('PATH must not be used when engines/qpdf exists'),
    );

    expect(resolver.candidatePaths('qpdf').first, bundled);
    expect(await resolver.resolveQpdf(), bundled);
  });

  test('macOS Resources/engines is a candidate beside the MacOS binary', () {
    const exe =
        '/Applications/Document Studio.app/Contents/MacOS/document_studio';
    final resolver = DesktopEngineResolver(
      executablePath: exe,
      fileExists: (_) => false,
    );
    expect(
      resolver.candidatePaths('qpdf'),
      contains(
        p.normalize(
          '/Applications/Document Studio.app/Contents/Resources/engines/qpdf',
        ),
      ),
    );
    expect(
      resolver.candidatePaths('qpdf'),
      contains(
        p.normalize(
          '/Applications/Document Studio.app/Contents/MacOS/engines/qpdf',
        ),
      ),
    );
  });

  test('app-support engines are searched before PATH', () async {
    const extra = '/home/me/.local/share/document_studio/engines';
    debugDesktopEngineExtraRoots = [extra];
    final bundled = p.normalize('$extra/qpdf');
    final resolver = DesktopEngineResolver(
      executablePath: '/tmp/app/document_studio',
      fileExists: (path) => path == bundled,
      pathLookup: (_) async => '/usr/bin/qpdf',
    );

    expect(await resolver.resolveQpdf(), bundled);
  });
}
