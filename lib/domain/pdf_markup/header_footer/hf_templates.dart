import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';

/// A named, ready-made header/footer design.
class HfTemplate {
  const HfTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.spec,
    this.category = 'General',
    this.builtIn = true,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final HeaderFooterSpec spec;
  final bool builtIn;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'spec': spec.toJson(),
      };

  static HfTemplate? fromJson(Map<String, Object?> j) {
    final spec = j['spec'];
    final id = j['id'];
    final name = j['name'];
    if (spec is! Map || id is! String || name is! String) return null;
    return HfTemplate(
      id: id,
      name: name,
      description: j['description'] as String? ?? '',
      category: j['category'] as String? ?? 'My templates',
      spec: HeaderFooterSpec.fromJson(spec.cast<String, Object?>()),
      builtIn: false,
    );
  }
}

const _ink = 0x1F2937;
const _muted = 0x6B7280;
const _navy = 0x1E3A5F;
const _red = 0xC62828;

const builtInHfTemplates = <HfTemplate>[
  HfTemplate(
    id: 'minimal',
    name: 'Minimal page number',
    description: 'A quiet centered number at the bottom.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.footerCenter:
            HfZoneStyle(text: '{page}', sizePt: 9, colorRgb: _muted),
      },
    ),
  ),
  HfTemplate(
    id: 'page-x-of-y',
    name: 'Page X of Y',
    description: 'Bottom-right "Page 3 of 12".',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.footerRight: HfZoneStyle(
          text: 'Page {page} of {pages}',
          sizePt: 9,
          colorRgb: _ink,
        ),
      },
    ),
  ),
  HfTemplate(
    id: 'corporate',
    name: 'Corporate',
    category: 'Business',
    description: 'Title and date with hairline rules.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerLeft: HfZoneStyle(
          text: '{title}',
          font: HfFont.helveticaBold,
          sizePt: 9,
          colorRgb: _navy,
        ),
        HfZone.headerRight:
            HfZoneStyle(text: '{date}', sizePt: 9, colorRgb: _muted),
        HfZone.footerLeft: HfZoneStyle(
          text: 'Internal use only',
          sizePt: 8,
          colorRgb: _muted,
        ),
        HfZone.footerRight: HfZoneStyle(
          text: 'Page {page} of {pages}',
          sizePt: 8,
          colorRgb: _navy,
        ),
      },
      dateFormat: 'd MMMM yyyy',
      header: HfDecoration(ruleEnabled: true, ruleRgb: _navy, ruleWidthPt: 0.6),
      footer: HfDecoration(ruleEnabled: true, ruleRgb: 0xB0B8C4, ruleWidthPt: 0.5),
    ),
  ),
  HfTemplate(
    id: 'legal-bates',
    name: 'Legal Bates',
    category: 'Legal',
    description: 'Bates numbers bottom-right, file name bottom-left.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.footerRight: HfZoneStyle(
          text: '{bates}',
          font: HfFont.courierBold,
          sizePt: 10,
          colorRgb: 0x000000,
        ),
        HfZone.footerLeft: HfZoneStyle(
          text: '{filename}',
          font: HfFont.courier,
          sizePt: 8,
          colorRgb: _muted,
        ),
      },
      bates: HfBates(prefix: 'DS', start: 1, digits: 6),
      margins: HfMargins(bottom: 28, left: 42, right: 42),
    ),
  ),
  HfTemplate(
    id: 'confidential',
    name: 'Confidential banner',
    category: 'Business',
    description: 'Bold red banner across the top of every page.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerCenter: HfZoneStyle(
          text: 'CONFIDENTIAL',
          font: HfFont.helveticaBold,
          sizePt: 11,
          colorRgb: 0xFFFFFF,
        ),
        HfZone.footerCenter: HfZoneStyle(
          text: 'Do not copy or distribute  ·  {date}',
          sizePt: 7.5,
          colorRgb: _red,
        ),
      },
      margins: HfMargins(top: 12, bottom: 24),
      header: HfDecoration(bandRgb: _red),
    ),
  ),
  HfTemplate(
    id: 'academic',
    name: 'Academic',
    category: 'Education',
    description: 'Serif running head with author, centered number.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerLeft:
            HfZoneStyle(text: '{title}', font: HfFont.times, sizePt: 10, colorRgb: _ink),
        HfZone.headerRight:
            HfZoneStyle(text: '{author}', font: HfFont.times, sizePt: 10, colorRgb: _ink),
        HfZone.footerCenter:
            HfZoneStyle(text: '{page}', font: HfFont.times, sizePt: 10, colorRgb: _ink),
      },
      margins: HfMargins(top: 40, bottom: 40, left: 72, right: 72),
      header: HfDecoration(ruleEnabled: true, ruleRgb: 0x444444, ruleWidthPt: 0.4),
      skipFirstPage: true,
    ),
  ),
  HfTemplate(
    id: 'invoice',
    name: 'Invoice',
    category: 'Business',
    description: 'Invoice mark, date and a soft footer band.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerLeft: HfZoneStyle(
          text: 'INVOICE',
          font: HfFont.helveticaBold,
          sizePt: 13,
          colorRgb: _navy,
        ),
        HfZone.headerRight: HfZoneStyle(
          text: 'Issued {date}',
          sizePt: 9,
          colorRgb: _muted,
        ),
        HfZone.footerCenter: HfZoneStyle(
          text: 'Thank you for your business  ·  Page {page}/{pages}',
          sizePt: 8,
          colorRgb: _navy,
        ),
      },
      dateFormat: 'd MMM yyyy',
      footer: HfDecoration(bandRgb: 0xE8EEF6),
    ),
  ),
  HfTemplate(
    id: 'draft',
    name: 'Draft',
    category: 'Review',
    description: 'Draft stamp with timestamp, file and page count.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerCenter: HfZoneStyle(
          text: 'DRAFT  —  {date} {time}',
          font: HfFont.helveticaBold,
          sizePt: 10,
          colorRgb: 0xD97706,
        ),
        HfZone.footerLeft:
            HfZoneStyle(text: '{file}', sizePt: 8, colorRgb: _muted),
        HfZone.footerRight:
            HfZoneStyle(text: '{page} / {pages}', sizePt: 8, colorRgb: _muted),
      },
      dateFormat: 'yyyy-MM-dd',
    ),
  ),
  HfTemplate(
    id: 'book',
    name: 'Book (alternating)',
    category: 'Publishing',
    description: 'Numbers and running head on the outer edge of facing pages.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.headerRight: HfZoneStyle(
          text: '{title}',
          font: HfFont.times,
          sizePt: 9,
          colorRgb: _muted,
        ),
        HfZone.footerRight: HfZoneStyle(
          text: '{page}',
          font: HfFont.timesBold,
          sizePt: 10,
          colorRgb: _ink,
        ),
      },
      mirrorOnEvenPages: true,
      margins: HfMargins(top: 32, bottom: 32, left: 60, right: 60),
    ),
  ),
  HfTemplate(
    id: 'front-matter',
    name: 'Front matter (i, ii, iii)',
    category: 'Publishing',
    description: 'Lower-case Roman numerals, centered.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.footerCenter: HfZoneStyle(
          text: '{page}',
          font: HfFont.times,
          sizePt: 10,
          colorRgb: _ink,
        ),
      },
      numberStyle: HfNumberStyle.romanLower,
    ),
  ),
  HfTemplate(
    id: 'printed-on',
    name: 'Printed on',
    category: 'Review',
    description: 'Print timestamp left, page number right.',
    spec: HeaderFooterSpec(
      zones: {
        HfZone.footerLeft: HfZoneStyle(
          text: 'Printed {date} at {time}',
          sizePt: 8,
          colorRgb: _muted,
        ),
        HfZone.footerRight:
            HfZoneStyle(text: '{page}', sizePt: 8, colorRgb: _ink),
      },
      dateFormat: 'EEE, d MMM yyyy',
      timeFormat: 'h:mm a',
    ),
  ),
];
