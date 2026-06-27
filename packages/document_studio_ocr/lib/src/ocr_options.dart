/// Recognition options aligned with Document Studio OCR-ENGINE.md.
class OcrOptions {
  const OcrOptions({
    this.language = 'eng',
    this.dpi = 300,
    this.deskew = false,
    this.denoise = false,
    this.autoRotate = false,
    this.skipPagesWithText = true,
  });

  /// Tesseract traineddata language id (e.g. `eng`, `deu`).
  final String language;

  /// DPI hint when the input is a rendered PDF page bitmap.
  final int dpi;

  /// DS-OCR-004 — mild deskew via projection search when enabled.
  ///
  /// Image OCR only: rotating the bitmap would misalign a PDF text layer.
  final bool deskew;

  /// DS-OCR-004 — grayscale + contrast boost when enabled.
  final bool denoise;

  /// Use Tesseract OSD to detect and correct page orientation when available.
  final bool autoRotate;

  /// Searchable PDF: leave pages that already have a text layer untouched.
  final bool skipPagesWithText;

  /// Individual traineddata ids in [language] (`eng+deu` → `[eng, deu]`).
  List<String> get languageCodes => [
        for (final part in language.split('+'))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  OcrOptions copyWith({
    String? language,
    int? dpi,
    bool? deskew,
    bool? denoise,
    bool? autoRotate,
    bool? skipPagesWithText,
  }) {
    return OcrOptions(
      language: language ?? this.language,
      dpi: dpi ?? this.dpi,
      deskew: deskew ?? this.deskew,
      denoise: denoise ?? this.denoise,
      autoRotate: autoRotate ?? this.autoRotate,
      skipPagesWithText: skipPagesWithText ?? this.skipPagesWithText,
    );
  }
}

/// Human-readable names for common Tesseract traineddata ids.
const kOcrLanguageLabels = <String, String>{
  'eng': 'English',
  'deu': 'German',
  'fra': 'French',
  'spa': 'Spanish',
  'ita': 'Italian',
  'por': 'Portuguese',
  'nld': 'Dutch',
  'pol': 'Polish',
  'rus': 'Russian',
  'ukr': 'Ukrainian',
  'tur': 'Turkish',
  'swe': 'Swedish',
  'dan': 'Danish',
  'nor': 'Norwegian',
  'fin': 'Finnish',
  'ces': 'Czech',
  'ell': 'Greek',
  'hin': 'Hindi',
  'ben': 'Bengali',
  'tam': 'Tamil',
  'tel': 'Telugu',
  'mar': 'Marathi',
  'guj': 'Gujarati',
  'pan': 'Punjabi',
  'urd': 'Urdu',
  'ara': 'Arabic',
  'heb': 'Hebrew',
  'fas': 'Persian',
  'chi_sim': 'Chinese (Simplified)',
  'chi_tra': 'Chinese (Traditional)',
  'jpn': 'Japanese',
  'kor': 'Korean',
  'tha': 'Thai',
  'vie': 'Vietnamese',
  'ind': 'Indonesian',
};

String ocrLanguageLabel(String code) => kOcrLanguageLabels[code] ?? code;

/// Bundled + optional tessdata ids for UI (DS-OCR-003).
const kOcrLanguageChoices = <({String id, String label, bool bundled})>[
  (id: 'eng', label: 'English', bundled: true),
  (id: 'deu', label: 'German', bundled: false),
  (id: 'fra', label: 'French', bundled: false),
  (id: 'hin', label: 'Hindi', bundled: false),
  (id: 'eng+deu', label: 'English + German', bundled: false),
];
