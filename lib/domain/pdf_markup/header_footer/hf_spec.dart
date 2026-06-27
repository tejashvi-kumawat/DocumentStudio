import 'package:equatable/equatable.dart';

/// Standard-14 fonts available to header/footer zones (no embedding needed).
enum HfFont {
  helvetica('Helvetica', 'Helvetica', HfFontFamily.sans, false),
  helveticaBold('Helvetica Bold', 'Helvetica-Bold', HfFontFamily.sans, true),
  times('Times', 'Times-Roman', HfFontFamily.serif, false),
  timesBold('Times Bold', 'Times-Bold', HfFontFamily.serif, true),
  courier('Courier', 'Courier', HfFontFamily.mono, false),
  courierBold('Courier Bold', 'Courier-Bold', HfFontFamily.mono, true);

  const HfFont(this.label, this.pdfBaseFont, this.family, this.bold);

  final String label;
  final String pdfBaseFont;
  final HfFontFamily family;
  final bool bold;

  static HfFont byName(String? name) =>
      HfFont.values.firstWhere((f) => f.name == name, orElse: () => helvetica);
}

enum HfFontFamily { sans, serif, mono }

enum HfAlign { left, center, right }

/// The six Acrobat-style slots.
enum HfZone {
  headerLeft(true, HfAlign.left, 'Header left'),
  headerCenter(true, HfAlign.center, 'Header center'),
  headerRight(true, HfAlign.right, 'Header right'),
  footerLeft(false, HfAlign.left, 'Footer left'),
  footerCenter(false, HfAlign.center, 'Footer center'),
  footerRight(false, HfAlign.right, 'Footer right');

  const HfZone(this.isHeader, this.align, this.label);

  final bool isHeader;
  final HfAlign align;
  final String label;

  /// Left/right swapped (book-style facing pages).
  HfZone get mirrored => switch (this) {
        headerLeft => headerRight,
        headerRight => headerLeft,
        footerLeft => footerRight,
        footerRight => footerLeft,
        _ => this,
      };
}

enum HfNumberStyle {
  arabic('1, 2, 3'),
  romanLower('i, ii, iii'),
  romanUpper('I, II, III'),
  alphaLower('a, b, c'),
  alphaUpper('A, B, C');

  const HfNumberStyle(this.label);
  final String label;

  static HfNumberStyle byName(String? name) => HfNumberStyle.values
      .firstWhere((s) => s.name == name, orElse: () => arabic);
}

enum HfPageRange {
  all('All'),
  odd('Odd'),
  even('Even'),
  custom('Custom');

  const HfPageRange(this.label);
  final String label;

  static HfPageRange byName(String? name) =>
      HfPageRange.values.firstWhere((r) => r.name == name, orElse: () => all);
}

class HfZoneStyle extends Equatable {
  const HfZoneStyle({
    this.text = '',
    this.font = HfFont.helvetica,
    this.sizePt = 10,
    this.colorRgb = 0x333333,
  });

  /// Template text; may contain tokens and line breaks.
  final String text;
  final HfFont font;
  final double sizePt;

  /// 0xRRGGBB.
  final int colorRgb;

  bool get isEmpty => text.trim().isEmpty;

  HfZoneStyle copyWith({
    String? text,
    HfFont? font,
    double? sizePt,
    int? colorRgb,
  }) =>
      HfZoneStyle(
        text: text ?? this.text,
        font: font ?? this.font,
        sizePt: sizePt ?? this.sizePt,
        colorRgb: colorRgb ?? this.colorRgb,
      );

  Map<String, Object?> toJson() => {
        't': text,
        'f': font.name,
        's': sizePt,
        'c': colorRgb,
      };

  factory HfZoneStyle.fromJson(Map<String, Object?> j) => HfZoneStyle(
        text: j['t'] as String? ?? '',
        font: HfFont.byName(j['f'] as String?),
        sizePt: (j['s'] as num?)?.toDouble() ?? 10,
        colorRgb: (j['c'] as num?)?.toInt() ?? 0x333333,
      );

  @override
  List<Object?> get props => [text, font, sizePt, colorRgb];
}

class HfBates extends Equatable {
  const HfBates({
    this.prefix = '',
    this.suffix = '',
    this.start = 1,
    this.digits = 6,
  });

  final String prefix;
  final String suffix;
  final int start;
  final int digits;

  String format(int value) =>
      '$prefix${value.toString().padLeft(digits.clamp(1, 15), '0')}$suffix';

  HfBates copyWith({String? prefix, String? suffix, int? start, int? digits}) =>
      HfBates(
        prefix: prefix ?? this.prefix,
        suffix: suffix ?? this.suffix,
        start: start ?? this.start,
        digits: digits ?? this.digits,
      );

  Map<String, Object?> toJson() =>
      {'p': prefix, 'x': suffix, 's': start, 'd': digits};

  factory HfBates.fromJson(Map<String, Object?> j) => HfBates(
        prefix: j['p'] as String? ?? '',
        suffix: j['x'] as String? ?? '',
        start: (j['s'] as num?)?.toInt() ?? 1,
        digits: (j['d'] as num?)?.toInt() ?? 6,
      );

  @override
  List<Object?> get props => [prefix, suffix, start, digits];
}

/// Margins in points, measured from the page edge to the text block.
class HfMargins extends Equatable {
  const HfMargins({
    this.top = 36,
    this.bottom = 36,
    this.left = 54,
    this.right = 54,
  });

  final double top;
  final double bottom;
  final double left;
  final double right;

  HfMargins copyWith({double? top, double? bottom, double? left, double? right}) =>
      HfMargins(
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        left: left ?? this.left,
        right: right ?? this.right,
      );

  Map<String, Object?> toJson() =>
      {'t': top, 'b': bottom, 'l': left, 'r': right};

  factory HfMargins.fromJson(Map<String, Object?> j) => HfMargins(
        top: (j['t'] as num?)?.toDouble() ?? 36,
        bottom: (j['b'] as num?)?.toDouble() ?? 36,
        left: (j['l'] as num?)?.toDouble() ?? 54,
        right: (j['r'] as num?)?.toDouble() ?? 54,
      );

  @override
  List<Object?> get props => [top, bottom, left, right];
}

/// Decorative rule / band drawn with a header or footer block.
class HfDecoration extends Equatable {
  const HfDecoration({
    this.ruleEnabled = false,
    this.ruleRgb = 0x999999,
    this.ruleWidthPt = 0.75,
    this.bandRgb,
    this.bandOpacity = 1,
  });

  final bool ruleEnabled;
  final int ruleRgb;
  final double ruleWidthPt;

  /// Solid band from the page edge to past the text block (e.g. banners).
  final int? bandRgb;
  final double bandOpacity;

  HfDecoration copyWith({
    bool? ruleEnabled,
    int? ruleRgb,
    double? ruleWidthPt,
    int? bandRgb,
    bool clearBand = false,
    double? bandOpacity,
  }) =>
      HfDecoration(
        ruleEnabled: ruleEnabled ?? this.ruleEnabled,
        ruleRgb: ruleRgb ?? this.ruleRgb,
        ruleWidthPt: ruleWidthPt ?? this.ruleWidthPt,
        bandRgb: clearBand ? null : (bandRgb ?? this.bandRgb),
        bandOpacity: bandOpacity ?? this.bandOpacity,
      );

  Map<String, Object?> toJson() => {
        're': ruleEnabled,
        'rc': ruleRgb,
        'rw': ruleWidthPt,
        'bc': bandRgb,
        'bo': bandOpacity,
      };

  factory HfDecoration.fromJson(Map<String, Object?>? j) {
    if (j == null) return const HfDecoration();
    return HfDecoration(
      ruleEnabled: j['re'] as bool? ?? false,
      ruleRgb: (j['rc'] as num?)?.toInt() ?? 0x999999,
      ruleWidthPt: (j['rw'] as num?)?.toDouble() ?? 0.75,
      bandRgb: (j['bc'] as num?)?.toInt(),
      bandOpacity: (j['bo'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  List<Object?> get props =>
      [ruleEnabled, ruleRgb, ruleWidthPt, bandRgb, bandOpacity];
}

/// Complete header & footer definition — persisted in templates and inside
/// the PDF so a previous application can be edited or removed.
class HeaderFooterSpec extends Equatable {
  const HeaderFooterSpec({
    this.zones = const {},
    this.margins = const HfMargins(),
    this.range = HfPageRange.all,
    this.customRange = '',
    this.skipFirstPage = false,
    this.numberStyle = HfNumberStyle.arabic,
    this.startNumber = 1,
    this.dateFormat = 'dd/MM/yyyy',
    this.timeFormat = 'HH:mm',
    this.bates = const HfBates(),
    this.mirrorOnEvenPages = false,
    this.header = const HfDecoration(),
    this.footer = const HfDecoration(),
  });

  final Map<HfZone, HfZoneStyle> zones;
  final HfMargins margins;
  final HfPageRange range;
  final String customRange;
  final bool skipFirstPage;
  final HfNumberStyle numberStyle;

  /// Number printed on page 1 (Acrobat "Start page number").
  final int startNumber;
  final String dateFormat;
  final String timeFormat;
  final HfBates bates;

  /// Swap left/right zones on even pages (book-style facing pages).
  final bool mirrorOnEvenPages;
  final HfDecoration header;
  final HfDecoration footer;

  HfZoneStyle zone(HfZone z) => zones[z] ?? const HfZoneStyle();

  bool get hasContent =>
      HfZone.values.any((z) => !zone(z).isEmpty) ||
      header.bandRgb != null ||
      footer.bandRgb != null;

  bool get usesBates => HfZone.values.any((z) => zone(z).text.contains('{bates'));

  HeaderFooterSpec withZone(HfZone z, HfZoneStyle style) =>
      copyWith(zones: {...zones, z: style});

  HeaderFooterSpec copyWith({
    Map<HfZone, HfZoneStyle>? zones,
    HfMargins? margins,
    HfPageRange? range,
    String? customRange,
    bool? skipFirstPage,
    HfNumberStyle? numberStyle,
    int? startNumber,
    String? dateFormat,
    String? timeFormat,
    HfBates? bates,
    bool? mirrorOnEvenPages,
    HfDecoration? header,
    HfDecoration? footer,
  }) =>
      HeaderFooterSpec(
        zones: zones ?? this.zones,
        margins: margins ?? this.margins,
        range: range ?? this.range,
        customRange: customRange ?? this.customRange,
        skipFirstPage: skipFirstPage ?? this.skipFirstPage,
        numberStyle: numberStyle ?? this.numberStyle,
        startNumber: startNumber ?? this.startNumber,
        dateFormat: dateFormat ?? this.dateFormat,
        timeFormat: timeFormat ?? this.timeFormat,
        bates: bates ?? this.bates,
        mirrorOnEvenPages: mirrorOnEvenPages ?? this.mirrorOnEvenPages,
        header: header ?? this.header,
        footer: footer ?? this.footer,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'z': {
          for (final e in zones.entries)
            if (!e.value.isEmpty) e.key.name: e.value.toJson(),
        },
        'm': margins.toJson(),
        'r': range.name,
        'cr': customRange,
        'sf': skipFirstPage,
        'ns': numberStyle.name,
        'sn': startNumber,
        'df': dateFormat,
        'tf': timeFormat,
        'b': bates.toJson(),
        'mi': mirrorOnEvenPages,
        'hd': header.toJson(),
        'fd': footer.toJson(),
      };

  factory HeaderFooterSpec.fromJson(Map<String, Object?> j) {
    final zonesJson = (j['z'] as Map?)?.cast<String, Object?>() ?? const {};
    final zones = <HfZone, HfZoneStyle>{};
    for (final z in HfZone.values) {
      final raw = zonesJson[z.name];
      if (raw is Map) {
        zones[z] = HfZoneStyle.fromJson(raw.cast<String, Object?>());
      }
    }
    Map<String, Object?>? m(String k) =>
        (j[k] as Map?)?.cast<String, Object?>();
    return HeaderFooterSpec(
      zones: zones,
      margins: HfMargins.fromJson(m('m') ?? const {}),
      range: HfPageRange.byName(j['r'] as String?),
      customRange: j['cr'] as String? ?? '',
      skipFirstPage: j['sf'] as bool? ?? false,
      numberStyle: HfNumberStyle.byName(j['ns'] as String?),
      startNumber: (j['sn'] as num?)?.toInt() ?? 1,
      dateFormat: j['df'] as String? ?? 'dd/MM/yyyy',
      timeFormat: j['tf'] as String? ?? 'HH:mm',
      bates: HfBates.fromJson(m('b') ?? const {}),
      mirrorOnEvenPages: j['mi'] as bool? ?? false,
      header: HfDecoration.fromJson(m('hd')),
      footer: HfDecoration.fromJson(m('fd')),
    );
  }

  @override
  List<Object?> get props => [
        zones,
        margins,
        range,
        customRange,
        skipFirstPage,
        numberStyle,
        startNumber,
        dateFormat,
        timeFormat,
        bates,
        mirrorOnEvenPages,
        header,
        footer,
      ];
}
