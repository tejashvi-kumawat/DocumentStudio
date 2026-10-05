import 'package:document_studio/core/update/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares versions numerically', () {
    expect(compareVersions('1.0.4', '1.0.3'), greaterThan(0));
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.0.3', '1.0.3'), 0);
    expect(compareVersions('1.0.3+4', '1.0.3'), 0);
    expect(compareVersions('2.0', '1.99.99'), greaterThan(0));
    expect(compareVersions('1.0.2', '1.0.3'), lessThan(0));
  });
}
