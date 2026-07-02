import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/constants.dart';

class PostPreviewPage extends StatefulWidget {
  final String? frontImageUrl;
  final String? backImageUrl;

  const PostPreviewPage({
    super.key,
    this.frontImageUrl,
    this.backImageUrl,
  });

  @override
  State<PostPreviewPage> createState() => _PostPreviewPageState();
}

class _PostPreviewPageState extends State<PostPreviewPage> {
  bool isFrontMain = false;

  // ─── Location / Weather Chip State ───────────────────────────────────────
  /// null  = chip belum diklik
  /// true  = sedang loading (simulasi fetch lokasi)
  /// false = data dummy sudah dimuat
  bool? _weatherLoading;

  /// Data dummy yang akan ditampilkan & disimpan ke Supabase
  static const Map<String, String> _dummyWeather = {
    'location': 'Jakarta Utara',
    'temperature': '30°C',
    'condition': 'Sunny',
  };

  /// Label yang ditampilkan di chip saat aktif
  String get _weatherChipLabel =>
      '${_dummyWeather['location']}, ${_dummyWeather['temperature']}';

  /// Apakah chip sudah aktif (data sudah dimuat, bukan sedang loading)
  bool get _isWeatherActive => _weatherLoading == false;

  // ─── Upload State ─────────────────────────────────────────────────────────
  bool _isUploading = false;

  // ─── Helper: Build Image ──────────────────────────────────────────────────
  Widget _buildImage(String? url, {BoxFit fit = BoxFit.contain}) {
    if (url == null || url.isEmpty) {
      return Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.image_not_supported,
              color: AppColors.textDisabled, size: 40),
        ),
      );
    }
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.broken_image,
              color: AppColors.textDisabled, size: 40),
        ),
      ),
    );
  }

  // ─── Handler: Klik Chip Location ─────────────────────────────────────────
  Future<void> _onWeatherChipTapped() async {
    if (_isWeatherActive || _weatherLoading == true) return; // sudah aktif / loading

    setState(() => _weatherLoading = true);

    // Simulasi delay "fetch lokasi" selama 1 detik
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() => _weatherLoading = false);
  }

  // ─── Handler: Tombol Upload ───────────────────────────────────────────────
  Future<void> _onUploadPressed() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _showSnackBar('Sesi habis, silakan login ulang.', isError: true);
        return;
      }

      // Susun payload; sertakan weather_data hanya jika chip aktif
      final Map<String, dynamic> payload = {
        'user_id': user.id,
        'front_image_url': widget.frontImageUrl,
        'back_image_url': widget.backImageUrl,
        if (_isWeatherActive)
          'weather_data': jsonEncode(_dummyWeather),
        // Tambahkan kolom lain sesuai skema tabel posts Anda di sini
      };

      await supabase.from('posts').insert(payload);

      if (!mounted) return;
      _showSnackBar('Post berhasil diupload! 🎉');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Koneksi terputus, gagal menyimpan data.', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.neonMagenta : AppColors.neonGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── Build: Location / Weather Chip ──────────────────────────────────────
  Widget _buildWeatherChip() {
    // State: Loading
    if (_weatherLoading == true) {
      return _chipContainer(
        color: AppColors.surfaceElevated,
        borderColor: AppColors.textDisabled,
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    // State: Aktif (data dummy sudah dimuat)
    if (_isWeatherActive) {
      return _chipContainer(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderColor: Theme.of(context).colorScheme.primary,
        glowColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_rounded,
                size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 5),
            Text(
              _weatherChipLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    // State: Idle (belum diklik) — pakai InkWell untuk gesture yang lebih andal
    return InkWell(
      onTap: _onWeatherChipTapped,
      borderRadius: BorderRadius.circular(20),
      splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      child: _chipContainer(
        color: Colors.black.withValues(alpha: 0.55),
        borderColor: AppColors.textSecondary,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined,
                size: 14, color: AppColors.textSecondary),
            SizedBox(width: 5),
            Text(
              'Tambah Lokasi',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipContainer({
    required Widget child,
    required Color color,
    required Color borderColor,
    Color? glowColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor,
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: child,
    );
  }

  // ─── Build: Upload Button ─────────────────────────────────────────────────
  Widget _buildUploadButton() {
    return GestureDetector(
      onTap: _isUploading ? null : _onUploadPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          gradient: _isUploading
              ? LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)])
              : LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: _isUploading
              ? null
              : [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.50),
                    blurRadius: 16,
                    spreadRadius: 1,
                  )
                ],
        ),
        child: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Upload Moment',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mainUrl = isFrontMain ? widget.frontImageUrl : widget.backImageUrl;
    final pipUrl = isFrontMain ? widget.backImageUrl : widget.frontImageUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Layer Bawah: Main Image ──────────────────────────────────
            // IgnorePointer: gambar tidak boleh menyerap tap apapun
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey('main_$mainUrl'),
                    child: _buildImage(mainUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),

            // ── Layer PiP (Picture-in-Picture) ───────────────────────────
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => isFrontMain = !isFrontMain),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey('pip_$isFrontMain'),
                    width: 110,
                    height: 145,
                    decoration: BoxDecoration(
                      color: AppColors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImage(pipUrl, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),

            // ── Tombol Back ──────────────────────────────────────────────
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            // ── Bottom Bar: Chip + Upload Button ─────────────────────────
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Location / Weather Chip
                  // Material(elevation:0) memberi chip gesture layer sendiri
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        elevation: 0,
                        child: _buildWeatherChip(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Upload Button
                  _buildUploadButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

