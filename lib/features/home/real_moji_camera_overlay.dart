// lib/features/home/real_moji_camera_overlay.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EMOJI MENU BOTTOM SHEET
// Tampil saat tombol emoji ditekan. User pilih emoji preset ATAU ⚡ untuk cam.
// ═══════════════════════════════════════════════════════════════════════════

class RealMojiMenuSheet extends StatelessWidget {
  final String postId;
  final void Function(String reactionImageUrl, String emojiType) onCameraSuccess;
  /// Context dari widget induk (FeedPostItem) — tetap valid setelah sheet ditutup.
  final BuildContext parentContext;

  const RealMojiMenuSheet({
    super.key,
    required this.postId,
    required this.onCameraSuccess,
    required this.parentContext,
  });

  static const Map<String, String> _emojiMapping = {
    '👍': 'like',
    '😃': 'happy',
    '😯': 'surprised',
    '😂': 'laughing',
  };

  void _openCamera(BuildContext context, String emojiType) {
    Navigator.pop(context); // tutup sheet
    // Delay singkat agar animasi sheet selesai
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!parentContext.mounted) return;
      showDialog(
        context: parentContext, // pakai parent context yang masih hidup
        barrierColor: Colors.black.withValues(alpha: 0.88),
        builder: (_) => RealMojiCameraOverlay(
          postId: postId,
          emojiType: emojiType,
          onSuccess: onCameraSuccess,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'REACT',
            style: AppTheme.orbitron(
              fontSize: 11,
              color: AppColors.textSecondary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 20),

          // ── Emoji Row ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Emoji preset dari mapping
              ..._emojiMapping.entries.map(
                (entry) => GestureDetector(
                  onTap: () => _openCamera(context, entry.value),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                    alignment: Alignment.center,
                    child: Text(entry.key, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),

              // ⚡ Tombol kamera — buka Circle Cam (instant)
              GestureDetector(
                onTap: () => _openCamera(context, 'instant'),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CIRCLE CAM OVERLAY
// Hanya dibuka saat user mengetuk ⚡ di emoji menu.
// ═══════════════════════════════════════════════════════════════════════════

class RealMojiCameraOverlay extends StatefulWidget {
  final String postId;
  final String emojiType;
  final void Function(String reactionImageUrl, String emojiType) onSuccess;

  const RealMojiCameraOverlay({
    super.key,
    required this.postId,
    required this.emojiType,
    required this.onSuccess,
  });

  @override
  State<RealMojiCameraOverlay> createState() =>
      _RealMojiCameraOverlayState();
}

class _RealMojiCameraOverlayState extends State<RealMojiCameraOverlay> {
  CameraController? _controller;
  bool _isInitializing = true;
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initFrontCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ── Camera Init ──────────────────────────────────────────────────────────

  Future<void> _initFrontCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (e) {
      debugPrint('RealMoji cam init error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Kamera tidak bisa dibuka, coba lagi.';
          _isInitializing = false;
        });
      }
    }
  }

  // ── Capture & Upload ─────────────────────────────────────────────────────

  Future<void> _captureAndUpload() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      // 1. Ambil foto dari kamera depan
      final XFile photo = await _controller!.takePicture();
      final file = File(photo.path);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User tidak login');

      // 2. Upload ke Storage bucket 'realmojis'
      //    Format path: userId_timestamp.jpg (tanpa subfolder agar policy lebih mudah)
      final storagePath =
          '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      debugPrint('RealMoji: uploading to realmojis/$storagePath');

      await supabase.storage.from('realmojis').upload(
        storagePath,
        file,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );

      debugPrint('RealMoji: upload sukses');

      final publicUrl =
          supabase.storage.from('realmojis').getPublicUrl(storagePath);

      // 3. Upsert ke tabel post_reactions
      // Pakai upsert agar jika user react ulang, data lama diupdate (bukan duplicate error)
      await supabase.from('post_reactions').upsert(
        {
          'post_id': widget.postId,
          'user_id': userId,
          'reaction_image_url': publicUrl,
          'emoji_type': widget.emojiType,
        },
        onConflict: 'post_id,user_id',
      );

      debugPrint('RealMoji: upsert post_reactions sukses, url=$publicUrl');

      if (!mounted) return;

      // 4. Tutup overlay & notify parent
      Navigator.of(context, rootNavigator: true).pop();
      widget.onSuccess(publicUrl, widget.emojiType);
    } catch (e) {
      debugPrint('RealMoji Upload Error: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'Gagal mengirim reaksi, coba lagi nanti ya!';
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label
          Text(
            'INSTANT REALMOJI',
            style: AppTheme.orbitron(
              fontSize: 11,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),

          // ── Lingkaran Kamera ──────────────────────────────────────────
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
              color: AppColors.black,
            ),
            child: ClipOval(child: _buildCircleContent()),
          ),

          const SizedBox(height: 24),

          // ── Error / Buttons ───────────────────────────────────────────
          if (_errorMessage != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _errorMessage!,
                style: AppTheme.inter(color: Colors.redAccent, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isUploading = false;
                });
              },
              child: Text('Coba Lagi',
                  style: AppTheme.inter(color: Theme.of(context).colorScheme.primary)),
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Batal
                GestureDetector(
                  onTap: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceCard,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 22),
                  ),
                ),
                const SizedBox(width: 24),

                // Shutter ⚡
                GestureDetector(
                  onTap: (_isInitializing || _isUploading) ? null : _captureAndUpload,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isInitializing || _isUploading)
                          ? AppColors.textDisabled
                          : Theme.of(context).colorScheme.primary,
                      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                    ),
                    child: _isUploading
                        ? const Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : const Icon(Icons.bolt_rounded,
                            color: Colors.white, size: 32),
                  ),
                ),

                const SizedBox(width: 24),
                const SizedBox(width: 48), // simetris
              ],
            ),

          const SizedBox(height: 8),

          if (!_isUploading && _errorMessage == null)
            Text(
              'Tap ⚡ untuk kirim RealMoji',
              style: AppTheme.inter(
                  fontSize: 11, color: AppColors.textDisabled),
            ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCircleContent() {
    if (_isInitializing) {
      return Container(
        color: AppColors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.white),
        ),
      );
    }

    if (_controller == null || _errorMessage != null) {
      return Container(
        color: AppColors.black,
        child: const Center(
          child: Icon(Icons.camera_front_outlined,
              color: AppColors.textDisabled, size: 40),
        ),
      );
    }

    if (_isUploading) {
      return Container(
        color: AppColors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text('Uploading...',
                style: AppTheme.inter(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return CameraPreview(_controller!);
  }
}
