/// User-visible print failure.
class PrintException implements Exception {
  PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}
