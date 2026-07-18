import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/desktop/qpdf_engine_fetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official zip is the GitHub release for Linux and Windows only', () {
    expect(
      QpdfEngineFetch.officialZipUrl(operatingSystem: 'linux', arch: 'x86_64'),
      'https://github.com/qpdf/qpdf/releases/download/v12.2.0/'
      'qpdf-12.2.0-bin-linux-x86_64.zip',
    );
    expect(
      QpdfEngineFetch.officialZipUrl(operatingSystem: 'windows', arch: 'x86_64'),
      'https://github.com/qpdf/qpdf/releases/download/v12.4.2/'
      'qpdf-12.4.2-mingw64.zip',
    );
    expect(
      QpdfEngineFetch.officialZipUrl(operatingSystem: 'android', arch: 'arm64'),
      isNull,
    );
    expect(
      QpdfEngineFetch.officialZipUrl(operatingSystem: 'macos', arch: 'arm64'),
      isNull,
    );
  });

  test('fetchOnce does not download when qpdf is already resolved', () async {
    var downloaded = false;
    final fetch = QpdfEngineFetch(
      resolver: DesktopEngineResolver(
        executablePath: '/tmp/app/document_studio',
        fileExists: (_) => false,
        pathLookup: (name) async => name == 'qpdf' ? '/usr/bin/qpdf' : null,
      ),
      downloadZip: (_, _) async {
        downloaded = true;
      },
    );

    expect(await fetch.fetchOnce(), '/usr/bin/qpdf');
    expect(downloaded, isFalse);
  });
}
