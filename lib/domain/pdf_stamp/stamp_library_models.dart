import 'package:flutter/foundation.dart';

/// ARGB palette used by the stamp library UI.
abstract final class StampColors {
  static const int blue = 0xFF1B4F9C;
  static const int red = 0xFFB42318;
  static const int green = 0xFF1B7A3D;
  static const int orange = 0xFFC2410C;
  static const int purple = 0xFF6D28D9;
  static const int slate = 0xFF334155;
  static const int teal = 0xFF0F766E;
  static const int black = 0xFF111827;
  static const List<int> palette = [
    blue,
    red,
    green,
    orange,
    purple,
    teal,
    slate,
    black,
  ];
}

enum StampCategory { dynamic, standard, signHere, date, custom }

enum StampBorder {
  single('Single'),
  doubleLine('Double'),
  none('None');

  const StampBorder(this.label);
  final String label;
}

enum StampShape {
  rectangle('Rectangle'),
  rounded('Rounded'),
  oval('Oval'),
  arrow('Tab');

  const StampShape(this.label);
  final String label;
}

enum StampIcon {
  none('None'),
  check('Check'),
  cross('Cross'),
  star('Star');

  const StampIcon(this.label);
  final String label;
}

const List<String> kStampDateFormats = [
  'MMM d, yyyy',
  'yyyy-MM-dd',
  'dd/MM/yyyy',
  'MM/dd/yyyy',
  'd MMMM yyyy',
  'EEEE, MMMM d, yyyy',
  'dd.MM.yyyy',
];

/// Time suffix used by dynamic stamps (`h:mm a`).
String formatStampTime(DateTime when) {
  final h = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final m = when.minute.toString().padLeft(2, '0');
  return '$h:$m ${when.hour < 12 ? 'AM' : 'PM'}';
}

String formatStampDate(DateTime when, String format) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  final y = when.year.toString().padLeft(4, '0');
  final m = when.month.toString().padLeft(2, '0');
  final d = when.day.toString().padLeft(2, '0');
  switch (format) {
    case 'yyyy-MM-dd':
      return '$y-$m-$d';
    case 'dd/MM/yyyy':
      return '$d/$m/$y';
    case 'MM/dd/yyyy':
      return '$m/$d/$y';
    case 'dd.MM.yyyy':
      return '$d.$m.$y';
    case 'd MMMM yyyy':
      return '${when.day} ${months[when.month - 1]} $y';
    case 'EEEE, MMMM d, yyyy':
      return '${weekdays[when.weekday - 1]}, ${months[when.month - 1]} '
          '${when.day}, $y';
    case 'MMM d, yyyy':
    default:
      return '${months[when.month - 1].substring(0, 3)} ${when.day}, $y';
  }
}

@immutable
class StampContext {
  const StampContext({required this.userName, required this.now});
  final String userName;
  final DateTime now;
}

@immutable
class StampDesign {
  const StampDesign({
    required this.id,
    required this.title,
    required this.colorArgb,
    required this.category,
    this.subtitle,
    this.includeDate = false,
    this.includeTime = false,
    this.includeUser = false,
    this.dateFormat = 'MMM d, yyyy',
    this.border = StampBorder.single,
    this.shape = StampShape.rounded,
    this.filled = true,
    this.icon = StampIcon.none,
  });

  final String id;
  final String title;
  final String? subtitle;
  final int colorArgb;
  final StampCategory category;
  final bool includeDate;
  final bool includeTime;
  final bool includeUser;
  final String dateFormat;
  final StampBorder border;
  final StampShape shape;
  final bool filled;
  final StampIcon icon;

  bool get isDynamic => includeUser || includeDate || includeTime;

  StampDesign copyWith({
    String? id,
    String? title,
    String? subtitle,
    bool clearSubtitle = false,
    int? colorArgb,
    StampCategory? category,
    bool? includeDate,
    bool? includeTime,
    bool? includeUser,
    String? dateFormat,
    StampBorder? border,
    StampShape? shape,
    bool? filled,
    StampIcon? icon,
  }) {
    return StampDesign(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      colorArgb: colorArgb ?? this.colorArgb,
      category: category ?? this.category,
      includeDate: includeDate ?? this.includeDate,
      includeTime: includeTime ?? this.includeTime,
      includeUser: includeUser ?? this.includeUser,
      dateFormat: dateFormat ?? this.dateFormat,
      border: border ?? this.border,
      shape: shape ?? this.shape,
      filled: filled ?? this.filled,
      icon: icon ?? this.icon,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'colorArgb': colorArgb,
        'category': category.name,
        'includeDate': includeDate,
        'includeTime': includeTime,
        'includeUser': includeUser,
        'dateFormat': dateFormat,
        'border': border.name,
        'shape': shape.name,
        'filled': filled,
        'icon': icon.name,
      };

  factory StampDesign.fromJson(Map<String, Object?> json) {
    StampBorder border = StampBorder.single;
    for (final b in StampBorder.values) {
      if (b.name == json['border']) border = b;
    }
    StampShape shape = StampShape.rounded;
    for (final s in StampShape.values) {
      if (s.name == json['shape']) shape = s;
    }
    StampIcon icon = StampIcon.none;
    for (final i in StampIcon.values) {
      if (i.name == json['icon']) icon = i;
    }
    StampCategory category = StampCategory.custom;
    for (final c in StampCategory.values) {
      if (c.name == json['category']) category = c;
    }
    return StampDesign(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      colorArgb: json['colorArgb'] as int? ?? StampColors.blue,
      category: category,
      includeDate: json['includeDate'] as bool? ?? false,
      includeTime: json['includeTime'] as bool? ?? false,
      includeUser: json['includeUser'] as bool? ?? false,
      dateFormat: json['dateFormat'] as String? ?? kStampDateFormats.first,
      border: border,
      shape: shape,
      filled: json['filled'] as bool? ?? true,
      icon: icon,
    );
  }
}

@immutable
class SavedImageStamp {
  const SavedImageStamp({
    required this.id,
    required this.name,
    required this.bytes,
  });

  final String id;
  final String name;
  final Uint8List bytes;
}

@immutable
class DateStampPrefs {
  const DateStampPrefs({required this.format, required this.color});
  final String format;
  final int color;
}

const List<StampDesign> kBuiltInStamps = [
  // Dynamic: stamped with the reviewer's name and the current date / time.
  StampDesign(
    id: 'dyn_approved',
    title: 'APPROVED',
    colorArgb: StampColors.green,
    category: StampCategory.dynamic,
    includeUser: true,
    includeDate: true,
    includeTime: true,
  ),
  StampDesign(
    id: 'dyn_reviewed',
    title: 'REVIEWED',
    colorArgb: StampColors.blue,
    category: StampCategory.dynamic,
    includeUser: true,
    includeDate: true,
    includeTime: true,
  ),
  StampDesign(
    id: 'dyn_received',
    title: 'RECEIVED',
    colorArgb: StampColors.purple,
    category: StampCategory.dynamic,
    includeUser: true,
    includeDate: true,
    includeTime: true,
  ),
  StampDesign(
    id: 'dyn_revised',
    title: 'REVISED',
    colorArgb: StampColors.orange,
    category: StampCategory.dynamic,
    includeUser: true,
    includeDate: true,
  ),
  StampDesign(
    id: 'dyn_rejected',
    title: 'REJECTED',
    colorArgb: StampColors.red,
    category: StampCategory.dynamic,
    includeUser: true,
    includeDate: true,
    includeTime: true,
  ),
  // Standard business stamps.
  StampDesign(
    id: 'std_approved',
    title: 'APPROVED',
    colorArgb: StampColors.green,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_not_approved',
    title: 'NOT APPROVED',
    colorArgb: StampColors.red,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_rejected',
    title: 'REJECTED',
    colorArgb: StampColors.red,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_draft',
    title: 'DRAFT',
    colorArgb: StampColors.orange,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_confidential',
    title: 'CONFIDENTIAL',
    colorArgb: StampColors.red,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_final',
    title: 'FINAL',
    colorArgb: StampColors.green,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_reviewed',
    title: 'REVIEWED',
    colorArgb: StampColors.blue,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_received',
    title: 'RECEIVED',
    colorArgb: StampColors.purple,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_void',
    title: 'VOID',
    colorArgb: StampColors.red,
    category: StampCategory.standard,
    border: StampBorder.doubleLine,
  ),
  StampDesign(
    id: 'std_for_comment',
    title: 'FOR COMMENT',
    colorArgb: StampColors.blue,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_for_public_release',
    title: 'FOR PUBLIC RELEASE',
    colorArgb: StampColors.green,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_not_for_public_release',
    title: 'NOT FOR PUBLIC RELEASE',
    colorArgb: StampColors.red,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_completed',
    title: 'COMPLETED',
    colorArgb: StampColors.green,
    category: StampCategory.standard,
  ),
  StampDesign(
    id: 'std_copy',
    title: 'COPY',
    colorArgb: StampColors.slate,
    category: StampCategory.standard,
  ),
  // Sign-here tabs.
  StampDesign(
    id: 'sign_here',
    title: 'SIGN HERE',
    colorArgb: StampColors.red,
    category: StampCategory.signHere,
    shape: StampShape.arrow,
  ),
  StampDesign(
    id: 'initial_here',
    title: 'INITIAL HERE',
    colorArgb: StampColors.blue,
    category: StampCategory.signHere,
    shape: StampShape.arrow,
  ),
  StampDesign(
    id: 'witness',
    title: 'WITNESS',
    colorArgb: StampColors.green,
    category: StampCategory.signHere,
    shape: StampShape.arrow,
  ),
  StampDesign(
    id: 'accepted',
    title: 'ACCEPTED',
    colorArgb: StampColors.green,
    category: StampCategory.signHere,
    shape: StampShape.rounded,
    border: StampBorder.none,
    icon: StampIcon.check,
  ),
  StampDesign(
    id: 'rejected_mark',
    title: 'REJECTED',
    colorArgb: StampColors.red,
    category: StampCategory.signHere,
    shape: StampShape.rounded,
    border: StampBorder.none,
    icon: StampIcon.cross,
  ),
];
