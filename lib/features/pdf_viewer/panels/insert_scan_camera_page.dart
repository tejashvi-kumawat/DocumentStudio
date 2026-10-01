import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:document_studio/features/pdf_viewer/panels/insert_scan_mjpeg.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

CameraDescription preferBackCamera(List<CameraDescription> cameras) {
  for (final camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.back) return camera;
  }
  return cameras.first;
}

/// Full-screen camera. Opens a live preview and takes a still only when
/// Capture is tapped. Closing the screen does not save a picture.
class InsertScanMobileCameraPage extends StatefulWidget {
  const InsertScanMobileCameraPage({super.key, required this.captureDirectory});

  final String captureDirectory;

  @override
  State<InsertScanMobileCameraPage> createState() =>
      _InsertScanMobileCameraPageState();
}

class _InsertScanMobileCameraPageState extends State<InsertScanMobileCameraPage> {
  CameraController? _controller;
  var _ready = false;
  var _taking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Preview only. takePicture runs from the Capture button.
    unawaited(_openPreview());
  }

  Future<void> _openPreview() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final controller = CameraController(
        preferBackCamera(cameras),
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        _releaseController();
        return;
      }
      setState(() => _ready = true);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.description ?? 'Could not open the camera.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _capture() async {
    if (_taking) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _taking = true);
    try {
      final shot = await controller.takePicture();
      final dest = p.join(
        widget.captureDirectory,
        'scan-shot-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(shot.path).copy(dest);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      if (!mounted) {
        try {
          await File(dest).delete();
        } catch (_) {}
        return;
      }
      Navigator.of(context).pop(dest);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _error = e.description ?? 'Could not take the picture.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _error = 'Could not save the picture.';
      });
    }
  }

  void _releaseController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
  }

  @override
  void dispose() {
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showPreview = _ready && controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Frame the page'),
      ),
      body: Column(
        children: [
          Expanded(
            child: showPreview
                ? Center(child: CameraPreview(controller))
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _error != null
                          ? Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
          ),
          if (showPreview && _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _taking ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('insert_scan_shutter'),
                    onPressed: showPreview && !_taking
                        ? () => unawaited(_capture())
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_taking ? 'Capturing…' : 'Capture'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop preview via ffmpeg. The stream starts when this screen opens.
/// A still is written only when Capture is tapped.
class InsertScanDesktopCameraPage extends StatefulWidget {
  const InsertScanDesktopCameraPage({
    super.key,
    required this.ffmpegPath,
    required this.captureDirectory,
  });

  final String ffmpegPath;
  final String captureDirectory;

  @override
  State<InsertScanDesktopCameraPage> createState() =>
      _InsertScanDesktopCameraPageState();
}

class _InsertScanDesktopCameraPageState extends State<InsertScanDesktopCameraPage> {
  final MjpegAssembler _assembler = MjpegAssembler();
  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final StringBuffer _stderr = StringBuffer();
  Uint8List? _frame;
  var _taking = false;
  var _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Live preview. The still file is written from the Capture button.
    unawaited(_startPreview());
  }

  Future<void> _startPreview() async {
    try {
      final process = await Process.start(widget.ffmpegPath, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-fflags',
        'nobuffer',
        '-flags',
        'low_delay',
        '-f',
        'v4l2',
        '-i',
        '/dev/video0',
        '-an',
        '-vf',
        'fps=10,scale=960:-2',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        '-q:v',
        '6',
        'pipe:1',
      ]);
      if (!mounted) {
        process.kill();
        return;
      }
      _process = process;
      _stderrSub = process.stderr.listen((chunk) {
        if (_stderr.length > 2000) return;
        _stderr.write(String.fromCharCodes(chunk));
      });
      _stdoutSub = process.stdout.listen((chunk) {
        _assembler.add(chunk);
        final frame = _assembler.latest;
        if (frame == null || !mounted) return;
        setState(() => _frame = frame);
      });
      unawaited(
        process.exitCode.then((code) {
          if (!mounted || _closed || _frame != null) return;
          final detail = _stderr.toString().trim();
          setState(() {
            _error = detail.isEmpty
                ? 'Camera preview stopped ($code).'
                : detail;
          });
        }),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _capture() async {
    if (_taking) return;
    final frame = _frame;
    if (frame == null) return;
    setState(() => _taking = true);
    try {
      final dest = p.join(
        widget.captureDirectory,
        'scan-shot-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(dest).writeAsBytes(frame, flush: true);
      if (!mounted) {
        try {
          await File(dest).delete();
        } catch (_) {}
        return;
      }
      _closed = true;
      Navigator.of(context).pop(dest);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _error = 'Could not save the picture.';
      });
    }
  }

  @override
  void dispose() {
    _closed = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Frame the page'),
      ),
      body: Column(
        children: [
          Expanded(
            child: frame != null
                ? Center(
                    child: Image.memory(frame, fit: BoxFit.contain),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _error != null
                          ? Text(
                              '$_error\nClose this screen and choose an image file instead.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'Starting camera…',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                    ),
                  ),
          ),
          if (frame != null && _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _taking
                        ? null
                        : () {
                            _closed = true;
                            Navigator.of(context).pop();
                          },
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('insert_scan_shutter'),
                    onPressed: frame != null && !_taking
                        ? () => unawaited(_capture())
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_taking ? 'Capturing…' : 'Capture'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
