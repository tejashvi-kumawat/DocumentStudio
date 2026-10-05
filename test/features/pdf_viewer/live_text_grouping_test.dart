import 'dart:ui';

import 'package:document_studio/features/pdf_viewer/live_text_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = Size(600, 800);

RawTextFragment _f(String t, double x, double y, double w, [double h = 12]) =>
    RawTextFragment(
      text: t,
      rect: Rect.fromLTWH(x / 600, y / 800, w / 600, h / 800),
    );

void main() {
  test('fragments on one baseline become one line', () {
    final blocks = groupTextFragments([
      _f('Hello', 50, 100, 30),
      _f('world', 84, 100, 30),
    ], _page);
    expect(blocks, hasLength(1));
    expect(blocks.single.lines, hasLength(1));
    expect(blocks.single.text, 'Hello world');
  });

  test('tight consecutive lines form a paragraph', () {
    final blocks = groupTextFragments([
      _f('First line of a paragraph that runs long', 50, 100, 400),
      _f('second line continues it and is long too', 50, 114, 395),
      _f('end.', 50, 128, 20),
    ], _page);
    expect(blocks, hasLength(1));
    expect(blocks.single.lines, hasLength(3));
  });

  test('two columns stay separate blocks', () {
    final blocks = groupTextFragments([
      _f('Left column text goes here ok', 50, 100, 200),
      _f('Right column text goes here', 330, 100, 200),
      _f('Left second line is here too', 50, 114, 200),
      _f('Right second line is here', 330, 114, 200),
    ], _page);
    expect(blocks, hasLength(2));
  });

  test('bullets start new blocks', () {
    final blocks = groupTextFragments([
      _f('• First item in the list ok', 50, 100, 300),
      _f('• Second item in the list', 50, 114, 300),
    ], _page);
    expect(blocks, hasLength(2));
  });

  test('a heading and body of different size do not merge', () {
    final blocks = groupTextFragments([
      _f('Title', 50, 100, 120, 24),
      _f('Body text under the title line', 50, 130, 300),
    ], _page);
    expect(blocks, hasLength(2));
  });
}
