/// Plain-text OCR output from [OcrPort.recognizeText].
class OcrTextResult {
  const OcrTextResult({
    required this.text,
    this.language,
  });

  final String text;

  /// BCP-47 or Tesseract language code used for recognition (e.g. `eng`).
  final String? language;
}
