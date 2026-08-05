import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final VoidCallback onVerified;

  const FaceVerificationScreen({super.key, required this.onVerified});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  bool _isVerified = false;
  String _statusKey = "look_at_camera";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() {});
      _cameraController!.startImageStream(_processCameraImage);
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing || _isVerified) return;
    _isProcessing = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation =
          InputImageRotation.rotation270deg;
      final InputImageFormat inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        // Simple "Liveness" check: look for eyes open
        if (face.leftEyeOpenProbability != null &&
            face.rightEyeOpenProbability != null) {
          if (face.leftEyeOpenProbability! > 0.5 &&
              face.rightEyeOpenProbability! > 0.5) {
            setState(() {
              _isVerified = true;
              _statusKey = "verification_complete";
            });
            _cameraController?.stopImageStream();
            Future.delayed(const Duration(seconds: 2), () {
              widget.onVerified();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Face detection error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                LocalizationService.translate('initializing_camera', lang),
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          LocalizationService.translate('face_verification', lang),
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 1 / _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
          // Overlay Circle
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isVerified ? Colors.green : Colors.white,
                  width: 4,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Text(
              LocalizationService.translate(_statusKey, lang),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
