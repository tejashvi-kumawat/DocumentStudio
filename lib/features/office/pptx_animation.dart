import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:xml/xml.dart';

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';

/// Entrance, emphasis or exit effect.
enum PptxAnimClass { entr, emph, exit }

/// When an effect starts.
enum PptxAnimTrigger { onClick, withPrevious, afterPrevious }

/// One object animation (PowerPoint `p:timing`, the effects people use).
class PptxAnim {
  PptxAnim({
    required this.shape,
    required this.cls,
    required this.effect,
    this.dir = 'b',
    this.durMs = 500,
    this.delayMs = 0,
    this.trigger = PptxAnimTrigger.onClick,
  });

  PptxShape shape;
  PptxAnimClass cls;

  /// appear fade fly wipe zoom (entrance/exit), grow spin pulse (emphasis).
  String effect;

  /// Fly / wipe direction: b (from bottom) t l r.
  String dir;
  int durMs, delayMs;
  PptxAnimTrigger trigger;

  String get label => switch (cls) {
    PptxAnimClass.entr =>
      effect == 'appear' ? 'Appear' : '${_names[effect] ?? effect} in',
    PptxAnimClass.exit =>
      effect == 'appear' ? 'Disappear' : '${_names[effect] ?? effect} out',
    PptxAnimClass.emph => _names[effect] ?? effect,
  };

  static const _names = {
    'fade': 'Fade',
    'fly': 'Fly',
    'wipe': 'Wipe',
    'zoom': 'Zoom',
    'grow': 'Grow',
    'spin': 'Spin',
    'pulse': 'Pulse',
  };
}

/// Effects offered in the Motion panel: (class, effect, label).
const kPptxEffects = [
  (PptxAnimClass.entr, 'appear', 'Appear'),
  (PptxAnimClass.entr, 'fade', 'Fade in'),
  (PptxAnimClass.entr, 'fly', 'Fly in'),
  (PptxAnimClass.entr, 'wipe', 'Wipe in'),
  (PptxAnimClass.entr, 'zoom', 'Zoom in'),
  (PptxAnimClass.emph, 'pulse', 'Pulse'),
  (PptxAnimClass.emph, 'grow', 'Grow'),
  (PptxAnimClass.emph, 'spin', 'Spin'),
  (PptxAnimClass.exit, 'fade', 'Fade out'),
  (PptxAnimClass.exit, 'fly', 'Fly out'),
  (PptxAnimClass.exit, 'wipe', 'Wipe out'),
  (PptxAnimClass.exit, 'zoom', 'Zoom out'),
  (PptxAnimClass.exit, 'appear', 'Disappear'),
];

// PowerPoint preset ids.
const _presetOf = {
  'appear': 1,
  'fly': 2,
  'fade': 10,
  'wipe': 22,
  'zoom': 53,
  'grow': 6,
  'spin': 8,
  'pulse': 26,
};
const _effectOf = {
  1: 'appear',
  2: 'fly',
  10: 'fade',
  22: 'wipe',
  53: 'zoom',
  23: 'zoom',
  6: 'grow',
  8: 'spin',
  26: 'pulse',
};
// Fly/wipe subtype ↔ direction.
const _subOf = {'t': 1, 'r': 2, 'b': 4, 'l': 8};
const _dirOf = {1: 't', 2: 'r', 4: 'b', 8: 'l'};

/// Reads the slide's animations (effects we don't know play as Fade).
List<PptxAnim> readPptxAnimations(XmlDocument slide, List<PptxShape> shapes) {
  final byId = <String, PptxShape>{};
  for (final s in shapes) {
    final id = s.node
        ?.findAllElements('cNvPr', namespaceUri: _p)
        .firstOrNull
        ?.getAttribute('id');
    if (id != null) byId[id] = s;
  }
  final timing = slide.rootElement.getElement('timing', namespaceUri: _p);
  if (timing == null) return [];
  final out = <PptxAnim>[];
  for (final ctn in timing.findAllElements('cTn', namespaceUri: _p)) {
    final cls = ctn.getAttribute('presetClass');
    if (cls == null || !const {'entr', 'emph', 'exit'}.contains(cls)) continue;
    final spid = ctn
        .findAllElements('spTgt', namespaceUri: _p)
        .firstOrNull
        ?.getAttribute('spid');
    final shape = byId[spid];
    if (shape == null) continue;
    final preset = int.tryParse(ctn.getAttribute('presetID') ?? '') ?? 10;
    final sub = int.tryParse(ctn.getAttribute('presetSubtype') ?? '') ?? 4;
    final effect = _effectOf[preset] ?? (cls == 'emph' ? 'pulse' : 'fade');
    var dur = 500;
    for (final inner in ctn.findAllElements('cTn', namespaceUri: _p)) {
      final d = int.tryParse(inner.getAttribute('dur') ?? '');
      if (d != null && d > 1) {
        dur = d;
        break;
      }
    }
    final delay =
        int.tryParse(
          ctn
                  .getElement('stCondLst', namespaceUri: _p)
                  ?.getElement('cond', namespaceUri: _p)
                  ?.getAttribute('delay') ??
              '',
        ) ??
        0;
    out.add(
      PptxAnim(
        shape: shape,
        cls: PptxAnimClass.values.byName(cls),
        effect: effect,
        dir: _dirOf[sub] ?? 'b',
        durMs: dur,
        delayMs: delay,
        trigger: switch (ctn.getAttribute('nodeType')) {
          'withEffect' => PptxAnimTrigger.withPrevious,
          'afterEffect' => PptxAnimTrigger.afterPrevious,
          _ => PptxAnimTrigger.onClick,
        },
      ),
    );
  }
  return out;
}

/// `p:timing` for [anims] (shape ids resolved from their XML), or null.
String? pptxTimingXml(List<PptxAnim> anims, String Function(PptxShape) idOf) {
  if (anims.isEmpty) return null;
  var id = 3;
  final groups = <List<PptxAnim>>[];
  for (final a in anims) {
    if (a.trigger == PptxAnimTrigger.onClick || groups.isEmpty) {
      groups.add([a]);
    } else {
      groups.last.add(a);
    }
  }
  String tgt(PptxAnim a) =>
      '<p:tgtEl><p:spTgt spid="${idOf(a.shape)}"/></p:tgtEl>';
  String set(PptxAnim a, String vis, int delay) =>
      '<p:set><p:cBhvr><p:cTn id="${id++}" dur="1" fill="hold"><p:stCondLst><p:cond delay="$delay"/></p:stCondLst></p:cTn>${tgt(a)}'
      '<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val="$vis"/></p:to></p:set>';
  String anim(PptxAnim a, String attr, String from, String to) =>
      '<p:anim calcmode="lin" valueType="num"><p:cBhvr additive="base"><p:cTn id="${id++}" dur="${a.durMs}" fill="hold"/>${tgt(a)}'
      '<p:attrNameLst><p:attrName>$attr</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst>'
      '<p:tav tm="0"><p:val><p:strVal val="$from"/></p:val></p:tav><p:tav tm="100000"><p:val><p:strVal val="$to"/></p:val></p:tav></p:tavLst></p:anim>';
  String effect(PptxAnim a, String inOut, String filter) =>
      '<p:animEffect transition="$inOut" filter="$filter"><p:cBhvr><p:cTn id="${id++}" dur="${a.durMs}"/>${tgt(a)}</p:cBhvr></p:animEffect>';
  String behaviours(PptxAnim a) {
    final enter = a.cls == PptxAnimClass.entr;
    final io = enter ? 'in' : 'out';
    final wipeDir =
        const {'t': 'up', 'b': 'down', 'l': 'left', 'r': 'right'}[a.dir] ??
        'down';
    final flyX = switch (a.dir) {
      'l' => '0-#ppt_w/2',
      'r' => '1+#ppt_w/2',
      _ => '#ppt_x',
    };
    final flyY = switch (a.dir) {
      't' => '0-#ppt_h/2',
      'b' => '1+#ppt_h/2',
      _ => '#ppt_y',
    };
    switch (a.cls) {
      case PptxAnimClass.emph:
        return switch (a.effect) {
          'spin' =>
            '<p:animRot by="21600000"><p:cBhvr><p:cTn id="${id++}" dur="${a.durMs}" fill="hold"/>${tgt(a)}<p:attrNameLst><p:attrName>r</p:attrName></p:attrNameLst></p:cBhvr></p:animRot>',
          'grow' =>
            '<p:animScale><p:cBhvr><p:cTn id="${id++}" dur="${a.durMs}" fill="hold"/>${tgt(a)}</p:cBhvr><p:by x="150000" y="150000"/></p:animScale>',
          _ =>
            '<p:animScale><p:cBhvr><p:cTn id="${id++}" dur="${a.durMs ~/ 2}" autoRev="1" fill="hold"/>${tgt(a)}</p:cBhvr><p:by x="110000" y="110000"/></p:animScale>',
        };
      case PptxAnimClass.entr || PptxAnimClass.exit:
        final body = switch (a.effect) {
          'appear' => '',
          'fly' =>
            enter
                ? anim(a, 'ppt_x', flyX, '#ppt_x') +
                      anim(a, 'ppt_y', flyY, '#ppt_y')
                : anim(a, 'ppt_x', '#ppt_x', flyX) +
                      anim(a, 'ppt_y', '#ppt_y', flyY),
          'wipe' => effect(a, io, 'wipe($wipeDir)'),
          'zoom' =>
            enter
                ? anim(a, 'ppt_w', '0', '#ppt_w') +
                      anim(a, 'ppt_h', '0', '#ppt_h') +
                      effect(a, io, 'fade')
                : anim(a, 'ppt_w', '#ppt_w', '0') +
                      anim(a, 'ppt_h', '#ppt_h', '0') +
                      effect(a, io, 'fade'),
          _ => effect(a, io, 'fade'),
        };
        return enter
            ? set(a, 'visible', 0) + body
            : body + set(a, 'hidden', a.effect == 'appear' ? 0 : a.durMs - 1);
    }
  }

  final b = StringBuffer(
    '<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst>'
    '<p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>',
  );
  for (final g in groups) {
    b.write(
      '<p:par><p:cTn id="${id++}" fill="hold"><p:stCondLst><p:cond delay="${g.first.trigger == PptxAnimTrigger.onClick ? 'indefinite' : '0'}"/></p:stCondLst><p:childTnLst>',
    );
    // "After previous" effects start a new timed sub-group.
    var t = 0, groupEnd = 0;
    final subs = <(int, List<PptxAnim>)>[];
    for (final a in g) {
      if (a.trigger == PptxAnimTrigger.afterPrevious) {
        t = groupEnd;
        subs.add((t, [a]));
      } else if (subs.isEmpty) {
        subs.add((t, [a]));
      } else {
        subs.last.$2.add(a);
      }
      groupEnd = groupEnd > t + a.delayMs + a.durMs
          ? groupEnd
          : t + a.delayMs + a.durMs;
    }
    for (final (start, list) in subs) {
      b.write(
        '<p:par><p:cTn id="${id++}" fill="hold"><p:stCondLst><p:cond delay="$start"/></p:stCondLst><p:childTnLst>',
      );
      for (final a in list) {
        final node = switch (a.trigger) {
          PptxAnimTrigger.onClick => 'clickEffect',
          PptxAnimTrigger.withPrevious => 'withEffect',
          PptxAnimTrigger.afterPrevious => 'afterEffect',
        };
        final sub = a.effect == 'fly' || a.effect == 'wipe'
            ? (_subOf[a.dir] ?? 4)
            : 0;
        b.write(
          '<p:par><p:cTn id="${id++}" presetID="${_presetOf[a.effect] ?? 10}" presetClass="${a.cls.name}" presetSubtype="$sub" fill="hold" nodeType="$node">'
          '<p:stCondLst><p:cond delay="${a.delayMs}"/></p:stCondLst><p:childTnLst>${behaviours(a)}</p:childTnLst></p:cTn></p:par>',
        );
      }
      b.write('</p:childTnLst></p:cTn></p:par>');
    }
    b.write('</p:childTnLst></p:cTn></p:par>');
  }
  b.write(
    '</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>'
    '<p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>'
    '</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>',
  );
  return b.toString();
}

/// Build steps for the slideshow: each click plays one step; effects in a
/// step start at their offset (ms).
List<List<(PptxAnim, int)>> pptxAnimSteps(List<PptxAnim> anims) {
  final steps = <List<(PptxAnim, int)>>[];
  var end = 0, start = 0;
  for (final a in anims) {
    if (a.trigger == PptxAnimTrigger.onClick || steps.isEmpty) {
      steps.add([]);
      start = 0;
      end = 0;
    }
    if (a.trigger == PptxAnimTrigger.afterPrevious) start = end;
    final at = start + a.delayMs;
    steps.last.add((a, at));
    if (at + a.durMs > end) end = at + a.durMs;
  }
  return steps;
}

/// Applies the slide's animations to one object at time [tMs] of build
/// step [step] (steps before it are finished, later ones not started).
/// Shared by the slideshow and the Motion panel's preview.
Widget pptxAnimate({
  required List<List<(PptxAnim, int)>> steps,
  required PptxShape shape,
  required Widget child,
  required int step,
  required double tMs,
  required Size slide,
  required Rect rect,
}) {
  var visible = true;
  var first = true;
  var opacity = 1.0, scale = 1.0, turns = 0.0;
  var offset = Offset.zero;
  double? clip; // wipe progress
  String clipDir = 'b';
  for (var k = 0; k < steps.length; k++) {
    for (final (a, at) in steps[k]) {
      if (!identical(a.shape, shape)) continue;
      if (first) {
        visible = a.cls != PptxAnimClass.entr;
        first = false;
      }
      final double p;
      if (k < step - 1 || (k == step - 1 && tMs >= at + a.durMs)) {
        p = 1;
      } else if (k == step - 1 && tMs >= at) {
        p = ((tMs - at) / a.durMs).clamp(0.0, 1.0);
      } else {
        continue;
      }
      final e = Curves.easeOutCubic.transform(p);
      Offset away() => switch (a.dir) {
        't' => Offset(0, -(rect.bottom)),
        'l' => Offset(-(rect.right), 0),
        'r' => Offset(slide.width - rect.left, 0),
        _ => Offset(0, slide.height - rect.top),
      };
      switch (a.cls) {
        case PptxAnimClass.entr:
          visible = true;
          opacity = 1;
          offset = Offset.zero;
          scale = 1;
          clip = null;
          switch (a.effect) {
            case 'fade':
              opacity = e;
            case 'fly':
              offset = away() * (1 - e);
            case 'wipe':
              clip = e;
              clipDir = a.dir;
            case 'zoom':
              scale = e;
              opacity = e;
          }
        case PptxAnimClass.exit:
          if (p >= 1) {
            visible = false;
            continue;
          }
          switch (a.effect) {
            case 'fade':
              opacity = 1 - e;
            case 'fly':
              offset = away() * e;
            case 'wipe':
              clip = 1 - e;
              clipDir = a.dir;
            case 'zoom':
              scale = 1 - e;
              opacity = 1 - e;
            default:
              break;
          }
        case PptxAnimClass.emph:
          switch (a.effect) {
            case 'grow':
              scale = 1 + 0.5 * e;
            case 'spin':
              turns = e;
            default:
              scale = 1 + 0.12 * math.sin(math.pi * p);
          }
      }
    }
  }
  if (!visible) return const SizedBox.shrink();
  Widget w = child;
  if (clip != null) {
    w = ClipRect(clipper: _WipeClip(clipDir, clip), child: w);
  }
  if (turns != 0) w = Transform.rotate(angle: turns * 2 * math.pi, child: w);
  if (scale != 1) w = Transform.scale(scale: scale, child: w);
  if (offset != Offset.zero) w = Transform.translate(offset: offset, child: w);
  if (opacity < 1) w = Opacity(opacity: opacity.clamp(0.0, 1.0), child: w);
  return w;
}

/// Total length of a build step (ms).
int pptxStepLength(List<(PptxAnim, int)> step) =>
    step.fold(0, (m, e) => math.max(m, e.$2 + e.$1.durMs));

/// Reveals [fraction] of the box from the side the wipe starts at.
class _WipeClip extends CustomClipper<Rect> {
  _WipeClip(this.dir, this.fraction);
  final String dir;
  final double fraction;

  @override
  Rect getClip(Size size) => switch (dir) {
    't' => Rect.fromLTRB(
      0,
      size.height * (1 - fraction),
      size.width,
      size.height,
    ),
    'l' => Rect.fromLTRB(
      size.width * (1 - fraction),
      0,
      size.width,
      size.height,
    ),
    'r' => Rect.fromLTRB(0, 0, size.width * fraction, size.height),
    _ => Rect.fromLTRB(0, 0, size.width, size.height * fraction),
  };

  @override
  bool shouldReclip(_WipeClip old) =>
      old.dir != dir || old.fraction != fraction;
}
