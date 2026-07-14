// lib/features/camera/camera_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../../core/constants/constants.dart';
import '../home/floating_sync_timer.dart';
import 'preview_page.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool isCapturing = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  /// Pause kamera saat app di-background, resume saat kembali ke foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // Jika kamera belum ada, abaikan kecuali saat resume
    if (cameraController == null || !cameraController.value.isInitialized) {
      if (state != AppLifecycleState.resumed) {
        return;
      }
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Matikan kamera untuk hemat baterai/memory saat app tidak di layar
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      // Hidupkan ulang otomatis saat masuk kembali ke aplikasi
      _initCamera();
    }
  }

  // ── Camera Init ──────────────────────────────────────────────────────────

  Future<void> _initCamera(
      {CameraLensDirection direction = CameraLensDirection.back}) async {
    try {
      // Ambil daftar kamera hanya sekali
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }

      final camera = _cameras.firstWhere(
        (cam) => cam.lensDirection == direction,
        orElse: () => _cameras.first,
      );

      // Dispose controller lama SEBELUM membuat yang baru agar tidak bocor
      final oldController = _cameraController;
      if (oldController != null) {
        _cameraController = null;
        await oldController.dispose();
      }

      final newController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await newController.initialize();

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        _cameraController = newController;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  // ── Capture Flow ─────────────────────────────────────────────────────────

  Future<void> _captureDualMoments() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Mendeteksi kamera awal
    final currentDirection = _cameraController!.description.lensDirection;
    final isFrontStart = currentDirection == CameraLensDirection.front;

    // Tampilkan loading animation (menyembunyikan camera preview)
    setState(() => isCapturing = true);

    try {
      // Langkah 1: Ambil foto kamera pertama (Background)
      final XFile firstPhoto = await _cameraController!.takePicture();

      // Langkah 2: Switch ke kamera kedua (di belakang layar)
      final nextDirection = isFrontStart ? CameraLensDirection.back : CameraLensDirection.front;
      await _initCamera(direction: nextDirection);

      // Jeda singkat agar AE/AF menyesuaikan (wajib agar foto tidak blur)
      await Future.delayed(const Duration(milliseconds: 400));

      // Langkah 3: Ambil foto kamera kedua (PIP)
      final XFile secondPhoto = await _cameraController!.takePicture();

      if (!mounted) return;

      // Main image = foto dari kamera awal, PIP = foto dari kamera kedua
      File mainImageFile = File(firstPhoto.path);
      File pipImageFile = File(secondPhoto.path);

      // Langkah 4: Flip/Un-mirror foto kamera depan
      // Jika start dengan kamera depan, maka mainImage adalah selfie
      File selfieImageFile = isFrontStart ? mainImageFile : pipImageFile;
      
      final bytes = await selfieImageFile.readAsBytes();
      img.Image? capturedImage = img.decodeImage(bytes);
      if (capturedImage != null) {
        capturedImage = img.flipHorizontal(capturedImage);
        await selfieImageFile.writeAsBytes(img.encodeJpg(capturedImage));
      }

      if (!mounted) return;

      // Sembunyikan loading
      setState(() => isCapturing = false);

      // Langkah 5: Navigasi ke Preview
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPage(
            backImage: mainImageFile,
            frontImage: pipImageFile,
            isFrontMirrored: false, // File sudah di-flip secara fisik
          ),
        ),
      );

      // Langkah 6: Reinit kamera belakang saat user kembali (batal / retake)
      if (mounted) {
        await _initCamera(direction: CameraLensDirection.back);
      }
    } catch (e) {
      debugPrint('Error capturing moments: $e');
      if (mounted) {
        setState(() => isCapturing = false);
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();

      // 1. Pilih gambar pertama (backImage)
      final XFile? backFile =
          await picker.pickImage(source: ImageSource.gallery);
      if (backFile == null) return;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Gambar belakang dipilih! Sekarang pilih gambar untuk kamera depan.'),
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));

      // 2. Pilih gambar kedua (frontImage)
      final XFile? frontFile =
          await picker.pickImage(source: ImageSource.gallery);
      if (frontFile == null) return;

      if (!mounted) return;

      // Dari gallery tidak perlu di-mirror
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPage(
            frontImage: File(frontFile.path),
            backImage: File(backFile.path),
            isFrontMirrored: false,
          ),
        ),
      );

      // Reinit kamera saat kembali dari Preview Page
      if (mounted) {
        await _initCamera(direction: CameraLensDirection.back);
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.close_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'SYNC MOMENT',
          style: AppTheme.orbitron(
            fontSize: 13,
            color: AppColors.textPrimary,
            letterSpacing: 3,
          ),
        ),
        actions: const [],
      ),
      body: Stack(
        children: [
          // ── Camera Preview / Loading Overlay ──────────────────────────
          // PENTING: Saat isCapturing=true, sembunyikan CameraPreview sepenuhnya
          // agar tidak crash saat controller di-dispose untuk ganti lensa.
          Container(
            width: size.width,
            height: size.height,
            color: AppColors.black,
            child: isCapturing
                // Layar hitam + loading spinner selama proses silent capture
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            color: primary,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'CAPTURING MOMENT...',
                          style: AppTheme.orbitron(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  )
                : _cameraController != null &&
                        _cameraController!.value.isInitialized
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cameraController!.value.previewSize
                                    ?.height ??
                                size.width,
                            height: _cameraController!.value.previewSize
                                    ?.width ??
                                size.height,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_rear_outlined,
                              color: AppColors.textDisabled,
                              size: 64,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'INITIALIZING CAMERA...',
                              style: AppTheme.orbitron(
                                fontSize: 10,
                                color: AppColors.textDisabled,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
          ),



          // ── Bottom Controls ────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 32,
                right: 32,
                top: 24,
                bottom: MediaQuery.of(context).padding.bottom + 32,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.black,
                    AppColors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Gallery Button
                  GestureDetector(
                    onTap: isCapturing ? null : _pickImages,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: const Icon(
                        Icons.photo_library_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),

                  // Shutter Button
                  GestureDetector(
                    onTap: isCapturing ? null : _captureDualMoments,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCapturing ? AppColors.textDisabled : primary,
                          width: 2.5,
                        ),
                        boxShadow: isCapturing ? null : [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCapturing ? AppColors.textDisabled : primary,
                        ),
                        child: isCapturing
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Flip Camera Button
                  GestureDetector(
                    onTap: isCapturing ? null : () => _initCamera(
                        direction: (_cameraController?.description.lensDirection ==
                                CameraLensDirection.back)
                            ? CameraLensDirection.front
                            : CameraLensDirection.back),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: const Icon(
                        Icons.flip_camera_ios_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Floating Sync Timer (real-time, sama dengan Home Feed) ────────
          const FloatingSyncTimer(),
        ],
      ),
    );
  }
}


