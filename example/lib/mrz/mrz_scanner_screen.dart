import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'mrz_parser.dart';

/// Live camera scanner for the passport MRZ. Pops with an [MrzResult] once the
/// same check-digit-valid read is seen in consecutive frames.
class MrzScannerScreen extends StatefulWidget {
  const MrzScannerScreen({super.key});

  @override
  State<MrzScannerScreen> createState() => _MrzScannerScreenState();
}

class _MrzScannerScreenState extends State<MrzScannerScreen> with WidgetsBindingObserver {
  // Identical valid reads required before accepting, to guard against a lucky misread.
  static const int _requiredMatches = 2;

  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _controller;
  CameraDescription? _camera;
  bool _isProcessing = false;
  bool _isDone = false;
  bool _torchOn = false;
  String? _error;

  MrzResult? _lastResult;
  int _matchCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null && !_isDone) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = back;
      setState(() {
        _controller = controller;
        _torchOn = false;
        _error = null;
      });
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code.contains('AccessDenied') || e.code.contains('Restricted')
            ? 'Camera permission denied. Enable camera access for this app in Settings.'
            : 'Could not start camera: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not start camera: $e');
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    await controller.dispose();
  }

  Future<void> _onFrame(CameraImage image) async {
    // Drop frames while the previous one is still being recognised.
    if (_isProcessing || _isDone) return;
    _isProcessing = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final recognized = await _recognizer.processImage(inputImage);
      final lines = [
        for (final block in recognized.blocks)
          for (final line in block.lines) line.text,
      ];
      final result = MrzParser.parse(lines);
      if (result == null) return;

      if (result == _lastResult) {
        _matchCount++;
      } else {
        _lastResult = result;
        _matchCount = 1;
      }

      if (_matchCount >= _requiredMatches && !_isDone && mounted) {
        _isDone = true;
        HapticFeedback.mediumImpact();
        await _disposeCamera();
        if (mounted) Navigator.of(context).pop(result);
      }
    } catch (e) {
      debugPrint('MRZ OCR error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    // Orientation is locked to portrait, so the image rotation is just the sensor's.
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    // nv21 (Android) and bgra8888 (iOS) are single-plane, as ML Kit expects.
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Passport MRZ'),
        actions: [
          if (controller != null)
            IconButton(
              tooltip: 'Torch',
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : controller == null || !controller.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: CameraPreview(controller)),
                    const _MrzOverlay(),
                  ],
                ),
    );
  }
}

/// Dims the preview and highlights a band where the two MRZ lines should sit.
class _MrzOverlay extends StatelessWidget {
  const _MrzOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.92;
        // MRZ band on a TD3 page is roughly 125mm x 20mm; leave room for alignment slop.
        final height = width * 0.26;
        return Stack(
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.srcOut),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.55),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Line up the two lines of <<< text at the bottom of the photo page inside the box. Hold steady with good lighting.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
