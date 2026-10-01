import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:flutter/material.dart';

/// Tools of the on-page markup editor.
enum MarkupTool {
  select,
  text,
  callout,
  note,
  highlight,
  underline,
  strikeout,
  squiggly,
  pen,
  highlighter,
  rectangle,
  ellipse,
  line,
  arrow,
  polygon,
  cloud,
  eraser,
  link,
  image;

  String get label => switch (this) {
        MarkupTool.select => 'Select',
        MarkupTool.text => 'Text',
        MarkupTool.callout => 'Callout',
        MarkupTool.note => 'Sticky note',
        MarkupTool.highlight => 'Highlight',
        MarkupTool.underline => 'Underline',
        MarkupTool.strikeout => 'Strikethrough',
        MarkupTool.squiggly => 'Squiggly',
        MarkupTool.pen => 'Pen',
        MarkupTool.highlighter => 'Highlighter',
        MarkupTool.rectangle => 'Rectangle',
        MarkupTool.ellipse => 'Ellipse',
        MarkupTool.line => 'Line',
        MarkupTool.arrow => 'Arrow',
        MarkupTool.polygon => 'Polygon',
        MarkupTool.cloud => 'Cloud',
        MarkupTool.eraser => 'Eraser',
        MarkupTool.link => 'Link',
        MarkupTool.image => 'Image',
      };

  IconData get icon => switch (this) {
        MarkupTool.select => Icons.near_me_outlined,
        MarkupTool.text => Icons.text_fields,
        MarkupTool.callout => Icons.chat_bubble_outline,
        MarkupTool.note => Icons.sticky_note_2_outlined,
        MarkupTool.highlight => Icons.highlight,
        MarkupTool.underline => Icons.format_underline,
        MarkupTool.strikeout => Icons.format_strikethrough,
        MarkupTool.squiggly => Icons.waves,
        MarkupTool.pen => Icons.draw_outlined,
        MarkupTool.highlighter => Icons.border_color_outlined,
        MarkupTool.rectangle => Icons.crop_square,
        MarkupTool.ellipse => Icons.circle_outlined,
        MarkupTool.line => Icons.horizontal_rule,
        MarkupTool.arrow => Icons.arrow_right_alt,
        MarkupTool.polygon => Icons.pentagon_outlined,
        MarkupTool.cloud => Icons.cloud_outlined,
        MarkupTool.eraser => Icons.auto_fix_normal_outlined,
        MarkupTool.link => Icons.link,
        MarkupTool.image => Icons.image_outlined,
      };

  String? get shortcutHint => switch (this) {
        MarkupTool.select => 'V',
        MarkupTool.text => 'T',
        MarkupTool.note => 'N',
        MarkupTool.highlight => 'H',
        MarkupTool.underline => 'U',
        MarkupTool.pen => 'D',
        MarkupTool.rectangle => 'R',
        MarkupTool.line => 'L',
        MarkupTool.link => 'K',
        MarkupTool.image => 'I',
        _ => null,
      };

  TextMarkupKind? get textMarkupKind => switch (this) {
        MarkupTool.highlight => TextMarkupKind.highlight,
        MarkupTool.underline => TextMarkupKind.underline,
        MarkupTool.strikeout => TextMarkupKind.strikeout,
        MarkupTool.squiggly => TextMarkupKind.squiggly,
        _ => null,
      };

  ShapeKind? get shapeKind => switch (this) {
        MarkupTool.rectangle => ShapeKind.rectangle,
        MarkupTool.ellipse => ShapeKind.ellipse,
        MarkupTool.line => ShapeKind.line,
        MarkupTool.arrow => ShapeKind.arrow,
        MarkupTool.polygon => ShapeKind.polygon,
        MarkupTool.cloud => ShapeKind.cloud,
        _ => null,
      };

  bool get isTextMarkup => textMarkupKind != null;
  bool get isShape => shapeKind != null;
  bool get isFreehand => this == MarkupTool.pen || this == MarkupTool.highlighter;

  /// Polygon-style tools collect clicks until double-click / Enter.
  bool get isMultiClick =>
      this == MarkupTool.polygon || this == MarkupTool.cloud;
}

/// Tool groups shown in the markup panel.
const List<(String, List<MarkupTool>)> kMarkupToolGroups = [
  ('Select', [MarkupTool.select, MarkupTool.eraser]),
  (
    'Text markup',
    [
      MarkupTool.highlight,
      MarkupTool.underline,
      MarkupTool.strikeout,
      MarkupTool.squiggly,
    ]
  ),
  ('Draw', [MarkupTool.pen, MarkupTool.highlighter]),
  (
    'Shapes',
    [
      MarkupTool.rectangle,
      MarkupTool.ellipse,
      MarkupTool.line,
      MarkupTool.arrow,
      MarkupTool.polygon,
      MarkupTool.cloud,
    ]
  ),
  (
    'Insert',
    [
      MarkupTool.text,
      MarkupTool.callout,
      MarkupTool.note,
      MarkupTool.image,
      MarkupTool.link,
    ]
  ),
];

/// Palette shared by the panel and the floating toolbar (ARGB).
const List<int> kMarkupPalette = [
  0xFF000000,
  0xFF5F6368,
  0xFFFFFFFF,
  0xFFE53935,
  0xFFFB8C00,
  0xFFFDD835,
  0xFF43A047,
  0xFF1E88E5,
  0xFF3949AB,
  0xFF8E24AA,
];

/// Highlighter palette (Preview-like soft colors).
const List<int> kHighlightPalette = [
  0xFFFFEB3B,
  0xFF8BE78B,
  0xFF7FD3FF,
  0xFFFF9ECF,
  0xFFC9A0FF,
  0xFFFFB74D,
];

const List<int> kNotePalette = [
  0xFFFFD54F,
  0xFFA5D6A7,
  0xFF90CAF9,
  0xFFF48FB1,
  0xFFCE93D8,
];

const List<double> kMarkupFontSizes = [
  8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 72,
];

const List<double> kMarkupStrokeWidths = [0.5, 1, 1.5, 2, 3, 4, 6, 8, 12];
