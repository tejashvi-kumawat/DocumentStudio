/// Thrown when OCR engines are not yet wired (status `[B]` in inventory).
class OcrEngineBlockedException implements Exception {
  OcrEngineBlockedException(this.message);

  final String message;

  @override
  String toString() => 'OcrEngineBlockedException: $message';
}
