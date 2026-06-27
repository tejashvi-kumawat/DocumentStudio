import 'dart:typed_data';

/// Pulls complete JPEG frames out of an ffmpeg MJPEG byte stream.
///
/// Preview only: nothing here writes a file. The shutter copies [latest].
class MjpegAssembler {
  final List<int> _pending = <int>[];
  Uint8List? latest;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _pending.addAll(chunk);
    _trimIfHuge();
    while (true) {
      final start = _find(0xD8, 0);
      if (start < 0) {
        if (_pending.length > 1) {
          final last = _pending.last;
          _pending
            ..clear()
            ..add(last);
        }
        return;
      }
      if (start > 0) _pending.removeRange(0, start);
      final end = _find(0xD9, 2);
      if (end < 0) return;
      latest = Uint8List.fromList(_pending.sublist(0, end + 2));
      _pending.removeRange(0, end + 2);
    }
  }

  void _trimIfHuge() {
    const cap = 2 * 1024 * 1024;
    if (_pending.length <= cap) return;
    final start = _find(0xD8, _pending.length - cap);
    if (start > 0) {
      _pending.removeRange(0, start);
    } else if (start < 0) {
      final last = _pending.last;
      _pending
        ..clear()
        ..add(last);
    }
  }

  int _find(int marker, int from) {
    if (from < 0) from = 0;
    for (var i = from; i < _pending.length - 1; i++) {
      if (_pending[i] == 0xFF && _pending[i + 1] == marker) return i;
    }
    return -1;
  }
}
