import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';

/// Insertable token shown in the editor's token menu.
class HfTokenInfo {
  const HfTokenInfo(this.token, this.label, this.description);

  final String token;
  final String label;
  final String description;
}

const hfTokenCatalog = <HfTokenInfo>[
  HfTokenInfo('{page}', 'Page number', 'Current page in the chosen style'),
  HfTokenInfo('{pages}', 'Total pages', 'Number of pages in the document'),
  HfTokenInfo('Page {page} of {pages}', 'Page X of Y', 'e.g. Page 3 of 12'),
  HfTokenInfo('{page}/{pages}', 'X / Y', 'e.g. 3/12'),
  HfTokenInfo('{date}', 'Date', 'Date in the chosen format'),
  HfTokenInfo('{time}', 'Time', 'Time in the chosen format'),
  HfTokenInfo('{file}', 'File name', 'File name with extension'),
  HfTokenInfo('{filename}', 'File name (no ext.)', 'File name without .pdf'),
  HfTokenInfo('{title}', 'Title', 'Document title (falls back to file name)'),
  HfTokenInfo('{author}', 'Author', 'Document author'),
  HfTokenInfo('{subject}', 'Subject', 'Document subject'),
  HfTokenInfo('{bates}', 'Bates number', 'Prefix + zero-padded counter + suffix'),
];

const hfDateFormats = <String>[
  'dd/MM/yyyy',
  'MM/dd/yyyy',
  'yyyy-MM-dd',
  'd MMM yyyy',
  'd MMMM yyyy',
  'MMMM d, yyyy',
  'EEE, d MMM yyyy',
  'EEEE, MMMM d, yyyy',
];

const hfTimeFormats = <String>['HH:mm', 'HH:mm:ss', 'h:mm a', 'h:mm:ss a'];

const _knownTokens = {
  'page',
  'pages',
  'date',
  'time',
  'file',
  'filename',
  'title',
  'author',
  'subject',
  'bates',
};

/// Document-level values available to tokens.
class HfDocInfo {
  const HfDocInfo({
    required this.fileName,
    required this.pageCount,
    this.title,
    this.author,
    this.subject,
    this.now,
  });

  final String fileName;
  final int pageCount;
  final String? title;
  final String? author;
  final String? subject;

  /// Timestamp baked into `{date}` / `{time}`; `null` means "now".
  final DateTime? now;

  HfDocInfo withNow(DateTime value) => HfDocInfo(
        fileName: fileName,
        pageCount: pageCount,
        title: title,
        author: author,
        subject: subject,
        now: value,
      );
}

final RegExp _tokenPattern = RegExp(r'\{([a-zA-Z]+)(?::([^}]*))?\}');

/// Validation messages for a zone template (unknown tokens, stray braces).
List<String> validateHfTemplate(String template) {
  final issues = <String>[];
  var depth = 0;
  for (final c in template.split('')) {
    if (c == '{') depth++;
    if (c == '}') depth--;
    if (depth < 0 || depth > 1) {
      issues.add('Unbalanced "{" / "}"');
      return issues;
    }
  }
  if (depth != 0) {
    issues.add('Unclosed "{"');
    return issues;
  }
  for (final m in _tokenPattern.allMatches(template)) {
    final name = m.group(1)!.toLowerCase();
    if (!_knownTokens.contains(name)) issues.add('Unknown token {$name}');
  }
  return issues;
}

String hfFormatNumber(int n, HfNumberStyle style) {
  switch (style) {
    case HfNumberStyle.arabic:
      return '$n';
    case HfNumberStyle.romanLower:
      return _roman(n).toLowerCase();
    case HfNumberStyle.romanUpper:
      return _roman(n);
    case HfNumberStyle.alphaLower:
      return _alpha(n).toLowerCase();
    case HfNumberStyle.alphaUpper:
      return _alpha(n);
  }
}

String _roman(int n) {
  if (n <= 0 || n > 3999) return '$n';
  const table = [
    (1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'), (100, 'C'), (90, 'XC'),
    (50, 'L'), (40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I'),
  ];
  var v = n;
  final b = StringBuffer();
  for (final (value, numeral) in table) {
    while (v >= value) {
      b.write(numeral);
      v -= value;
    }
  }
  return b.toString();
}

/// Spreadsheet-style letters: 1 → A, 26 → Z, 27 → AA.
String _alpha(int n) {
  if (n <= 0) return '$n';
  var v = n;
  final chars = <String>[];
  while (v > 0) {
    v--;
    chars.insert(0, String.fromCharCode(0x41 + v % 26));
    v ~/= 26;
  }
  return chars.join();
}

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];
const _daysLong = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// Minimal ICU-style date formatter (yyyy yy MMMM MMM MM M dd d EEEE EEE
/// HH H hh h mm ss a). Text in single quotes is literal.
String hfFormatDate(DateTime d, String pattern) {
  final out = StringBuffer();
  var i = 0;
  String two(int v) => v.toString().padLeft(2, '0');
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == "'") {
      final end = pattern.indexOf("'", i + 1);
      if (end < 0) {
        out.write(pattern.substring(i + 1));
        break;
      }
      out.write(pattern.substring(i + 1, end));
      i = end + 1;
      continue;
    }
    var run = 1;
    while (i + run < pattern.length && pattern[i + run] == c) {
      run++;
    }
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    switch (c) {
      case 'y':
        out.write(run == 2
            ? two(d.year % 100)
            : d.year.toString().padLeft(run.clamp(1, 4), '0'));
      case 'M':
        out.write(switch (run) {
          >= 4 => _monthsLong[d.month - 1],
          3 => _monthsLong[d.month - 1].substring(0, 3),
          2 => two(d.month),
          _ => '${d.month}',
        });
      case 'd':
        out.write(run >= 2 ? two(d.day) : '${d.day}');
      case 'E':
        final name = _daysLong[d.weekday - 1];
        out.write(run >= 4 ? name : name.substring(0, 3));
      case 'H':
        out.write(run >= 2 ? two(d.hour) : '${d.hour}');
      case 'h':
        out.write(run >= 2 ? two(h12) : '$h12');
      case 'm':
        out.write(run >= 2 ? two(d.minute) : '${d.minute}');
      case 's':
        out.write(run >= 2 ? two(d.second) : '${d.second}');
      case 'a':
        out.write(d.hour < 12 ? 'AM' : 'PM');
      default:
        out.write(c * run);
    }
    i += run;
  }
  return out.toString();
}

/// Per-page values for [resolveHfTemplate].
class HfPageContext {
  const HfPageContext({
    required this.page1Based,
    required this.batesValue,
  });

  final int page1Based;

  /// Bates counter for this page (only meaningful for stamped pages).
  final int batesValue;
}

String resolveHfTemplate(
  String template, {
  required HeaderFooterSpec spec,
  required HfDocInfo doc,
  required HfPageContext page,
}) {
  final now = doc.now ?? DateTime.now();
  final fileBase = doc.fileName.toLowerCase().endsWith('.pdf')
      ? doc.fileName.substring(0, doc.fileName.length - 4)
      : doc.fileName;
  return template.replaceAllMapped(_tokenPattern, (m) {
    final name = m.group(1)!.toLowerCase();
    final arg = m.group(2);
    switch (name) {
      case 'page':
        return hfFormatNumber(
          page.page1Based + spec.startNumber - 1,
          spec.numberStyle,
        );
      case 'pages':
        return hfFormatNumber(
          doc.pageCount + spec.startNumber - 1,
          spec.numberStyle,
        );
      case 'date':
        return hfFormatDate(now, arg ?? spec.dateFormat);
      case 'time':
        return hfFormatDate(now, arg ?? spec.timeFormat);
      case 'file':
        return doc.fileName;
      case 'filename':
        return fileBase;
      case 'title':
        final t = doc.title?.trim();
        return t == null || t.isEmpty ? fileBase : t;
      case 'author':
        return doc.author?.trim() ?? '';
      case 'subject':
        return doc.subject?.trim() ?? '';
      case 'bates':
        return spec.bates.format(page.batesValue);
    }
    return m.group(0)!;
  });
}
