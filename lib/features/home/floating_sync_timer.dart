// lib/features/home/floating_sync_timer.dart
//
// FloatingSyncTimer — widget Glassmorphism yang melayang di atas Home Feed.
//   - Mendengarkan syncTimerProvider.
//   - Menampilkan countdown sisa waktu saat status == active.
//   - Teks berubah merah jika sisa < 5 menit.
//   - Disembunyikan saat status == ready atau isLoading.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/constants.dart';
import '../../core/services/sync_timer_controller.dart';

class FloatingSyncTimer extends ConsumerWidget {
  const FloatingSyncTimer({super.key});

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(syncTimerProvider);
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Sembunyikan saat loading, belum membuka jendela (ready), ATAU waktu sudah habis (locked)
    if (timerState.isLoading ||
        timerState.status == SyncWindowStatus.ready ||
        timerState.status == SyncWindowStatus.locked) {
      return const SizedBox.shrink();
    }

    final isLocked = timerState.status == SyncWindowStatus.locked;
    final isWarning = !isLocked && timerState.remaining.inMinutes < 5;

    final displayColor = isLocked
        ? AppColors.textDisabled
        : isWarning
            ? Colors.redAccent
            : primaryColor;

    final label = isLocked ? 'WINDOW CLOSED' : '⚡ ${_format(timerState.remaining)}';

    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: displayColor.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: displayColor.withValues(alpha: 0.20),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isLocked) ...[
                    // Pulsing dot indicator
                    _PulsingDot(color: displayColor),
                    const SizedBox(width: 8),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: AppTheme.orbitron(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: displayColor,
                      letterSpacing: 2,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pulsing dot for "live" indicator ─────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.7),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
