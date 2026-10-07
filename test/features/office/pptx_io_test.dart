import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/features/office/pptx_animation.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:document_studio/features/office/pptx_text.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = File('test/fixtures/deck.pptx').readAsBytesSync();

  test('reads slides, placeholders, pictures and text styles', () {
    final d = PptxDocument.read(bytes);
    expect(d.slides, hasLength(2));
    final title = d.slides[0].shapes.firstWhere((s) => s.label == 'Title');
    expect(title.plainText, 'Hello Deck');
    expect(title.w, greaterThan(0)); // position inherited from the layout
    final s2 = d.slides[1];
    expect(s2.shapes.where((s) => s.kind == PptxShapeKind.picture), hasLength(1));
    final red = s2.shapes.firstWhere((s) => s.plainText == 'Red bold');
    expect(red.paras.first.runs.first.bold, isTrue);
    expect(red.paras.first.runs.first.color, 'D32F2F');
    expect(red.paras.first.runs.first.sizePt, 20);
    final body = s2.shapes.firstWhere((s) => s.plainText.contains('First point'));
    expect(body.paras[1].level, 1);
  });

  test('edits survive save: text, move, delete, add, duplicate, delete slide', () {
    final d = PptxDocument.read(bytes);
    final title = d.slides[0].shapes.firstWhere((s) => s.label == 'Title');
    title.paras = [PptxPara([PptxRun('Edited title', bold: true)])];
    title.dirtyText = true;
    title.x += 100000;
    title.dirtyGeometry = true;
    final pic = d.slides[1].shapes.firstWhere((s) => s.kind == PptxShapeKind.picture);
    d.removeShape(d.slides[1], pic);
    d.addTextBox(d.slides[1], text: 'New box');
    d.addPicture(d.slides[0], Uint8List.fromList(File('test/fixtures/deck.pptx').readAsBytesSync().sublist(0, 0) + [137, 80, 78, 71]), 'png', 1.5);
    final dup = d.duplicateSlide(d.slides[0]);
    expect(d.slides, hasLength(3));
    d.deleteSlide(d.slides[2]); // the original second slide
    final out = d.save();

    final back = PptxDocument.read(out);
    expect(back.slides, hasLength(2));
    final t = back.slides[0].shapes.firstWhere((s) => s.label == 'Title');
    expect(t.plainText, 'Edited title');
    expect(t.paras.first.runs.first.bold, isTrue);
    expect(back.slides[0].shapes.where((s) => s.kind == PptxShapeKind.picture), hasLength(1));
    expect(back.slides[1].path, dup.path);
    final p = Platform.environment['DS_PPTX_OUT'];
    if (p != null) File(p).writeAsBytesSync(out);
  });

  test('deck features survive save: shapes, tables, transitions, notes, theme, size, layouts', () {
    final d = PptxDocument.read(bytes);
    final s0 = d.slides[0];
    final star = d.addShape(s0, 'star5');
    star.paras = [PptxPara([PptxRun('Star text')], align: 'ctr')];
    star.rotation = 30;
    d.addShape(s0, 'arrow');
    final tbl = d.addTable(s0, 2, 3);
    tbl.cells![0][0] = 'Head';
    s0
      ..transition = 'push'
      ..transitionDir = 'u'
      ..transitionSpeed = 'fast'
      ..advanceAfterMs = 3000
      ..dirtyTransition = true
      ..hidden = true
      ..dirtyHidden = true
      ..notes = 'Say hello\nthen smile'
      ..notesDirty = true
      ..ownBackground = true
      ..background = '112233'
      ..dirtyBackground = true;
    d.slides[1]
      ..notes = 'Second notes'
      ..notesDirty = true;
    d.applyTheme(kPptxDesigns.firstWhere((t) => t.name == 'Facet'));
    final layout = d.layouts.firstWhere((l) => l.type == 'obj');
    final added = d.addSlide(layout);
    final title = added.shapes.firstWhere((x) => x.isTitle);
    title
      ..paras = [PptxPara([PptxRun('From layout')])]
      ..dirtyText = true;
    d.reorder(s0, star, 'back');
    final out = d.save();

    final back = PptxDocument.read(out);
    expect(back.slides, hasLength(3));
    final b0 = back.slides[0];
    final bstar = b0.shapes.firstWhere((x) => x.geom == 'star5');
    expect(bstar.plainText, 'Star text');
    expect(bstar.rotation, closeTo(30, 0.01));
    expect(b0.shapes.indexOf(bstar), lessThan(b0.shapes.indexWhere((x) => x.geom == 'line')));
    final barrow = b0.shapes.firstWhere((x) => x.geom == 'line');
    expect(barrow.arrowEnd, isTrue);
    final btbl = b0.shapes.firstWhere((x) => x.kind == PptxShapeKind.table);
    expect(btbl.cells, hasLength(2));
    expect(btbl.cells![0], ['Head', '', '']);
    expect(b0.transition, 'push');
    expect(b0.transitionDir, 'u');
    expect(b0.transitionSpeed, 'fast');
    expect(b0.advanceAfterMs, 3000);
    expect(b0.hidden, isTrue);
    expect(b0.notes, 'Say hello\nthen smile');
    expect(b0.background, '112233');
    expect(back.slides[1].notes, 'Second notes');
    expect(back.theme.colors['accent1'], '90C226');
    expect(back.theme.minor, 'Trebuchet MS');
    expect(back.slides[2].shapes.firstWhere((x) => x.isTitle).plainText, 'From layout');

    // Slide size: everything scales to the new width.
    final w0 = back.slides[0].shapes.firstWhere((x) => x.geom == 'star5').w;
    final oldW = back.width;
    back.setSlideSize(oldW * 1.5, back.height);
    final again = PptxDocument.read(back.save());
    expect(again.width, closeTo(oldW * 1.5, 1));
    expect(again.slides[0].shapes.firstWhere((x) => x.geom == 'star5').w, closeTo(w0 * 1.5, 2));
  });

  test('notes are created in a deck without a notes master', () async {
    final blank = File('assets/office/blank.pptx').readAsBytesSync();
    final d = PptxDocument.read(blank);
    d.slides[0]
      ..notes = 'Brand new notes'
      ..notesDirty = true;
    final back = PptxDocument.read(d.save());
    expect(back.slides[0].notes, 'Brand new notes');
  });

  test('copy, paste and undo snapshots', () {
    final d = PptxDocument.read(bytes);
    final s0 = d.slides[0];
    final title = s0.shapes.firstWhere((x) => x.label == 'Title');
    final n0 = s0.shapes.length;
    final snap = d.snapshot(only: s0);
    final clip = d.copyShape(s0, title)!;
    final pasted = d.pasteShape(d.slides[0], clip)!;
    expect(d.slides[0].shapes, hasLength(n0 + 1));
    expect(pasted.plainText, title.plainText);
    d.restore(snap);
    expect(d.slides[0].shapes, hasLength(n0));
  });

  test('animations round-trip through p:timing and build steps', () {
    final d = PptxDocument.read(bytes);
    final s0 = d.slides[1];
    final a = s0.shapes.first, b = s0.shapes.last;
    s0.animations = [
      PptxAnim(shape: a, cls: PptxAnimClass.entr, effect: 'fly', dir: 'l', durMs: 700),
      PptxAnim(shape: b, cls: PptxAnimClass.entr, effect: 'fade', trigger: PptxAnimTrigger.withPrevious),
      PptxAnim(shape: b, cls: PptxAnimClass.emph, effect: 'spin', trigger: PptxAnimTrigger.afterPrevious, delayMs: 200),
      PptxAnim(shape: a, cls: PptxAnimClass.exit, effect: 'zoom'),
    ];
    s0.dirtyAnimations = true;
    final back = PptxDocument.read(d.save());
    final anims = back.slides[1].animations;
    expect(anims.map((x) => '${x.cls.name}:${x.effect}:${x.trigger.name}'), [
      'entr:fly:onClick',
      'entr:fade:withPrevious',
      'emph:spin:afterPrevious',
      'exit:zoom:onClick',
    ]);
    expect(anims.first.dir, 'l');
    expect(anims.first.durMs, 700);
    expect(anims[2].delayMs, 200);
    final steps = pptxAnimSteps(anims);
    expect(steps, hasLength(2));
    expect(steps.first.map((e) => e.$2), [0, 0, 700 + 200]);
  });

  test('slide text ↔ editor delta keeps runs, theme colours and inheritance', () {
    final d = PptxDocument.read(bytes);
    final body = d.slides[1].shapes.firstWhere((s) => s.paras.length > 1);
    final delta = pptxToDelta(d, body);
    final back = deltaToPptx(d, body, delta);
    expect(back.map((p) => p.text), body.paras.map((p) => p.text));
    expect(back.map((p) => p.level), body.paras.map((p) => p.level));
    expect(back.map((p) => p.bullet), body.paras.map((p) => p.bullet));
    for (var i = 0; i < back.length; i++) {
      for (var j = 0; j < back[i].runs.length; j++) {
        final a = back[i].runs[j], b = body.paras[i].runs.where((r) => r.text.isNotEmpty).toList()[j];
        expect(a.sizePt, b.sizePt, reason: 'size stays inherited or explicit');
        expect(a.color, b.color);
        expect(a.bold, b.bold);
      }
    }
    // An edit: new text and bold on the first line.
    final edited = Delta()
      ..insert('Changed', {'bold': true, 'pr': '0:0'})
      ..insert('\n', {'pp': '0', 'list': 'bullet'});
    final paras = deltaToPptx(d, body, edited);
    expect(paras.single.text, 'Changed');
    expect(paras.single.runs.single.bold, isTrue);
    expect(paras.single.bullet, isTrue);
  });

  test('slide ids survive reordering; inserted pictures never reuse a relationship id', () {
    final d = PptxDocument.read(bytes);
    final ids = [for (final s in d.slides) s.sldId];
    d.moveSlide(1, 0);
    final png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    d.addPicture(d.slides[0], png, 'png', 1);
    final saved = PptxDocument.read(d.save());
    expect([for (final s in saved.slides) s.sldId], ids.reversed.toList());
    // Reopen a saved deck and add another picture to the same slide.
    saved.addPicture(saved.slides[0], png, 'png', 1);
    final again = PptxDocument.read(saved.save());
    final media = again.slides[0].shapes.where((s) => s.kind == PptxShapeKind.picture).map((s) => s.media).toList();
    expect(media.where((m) => m != null && m.contains('ds_image')).toSet(), hasLength(2), reason: 'each picture keeps its own file');
  });
}
