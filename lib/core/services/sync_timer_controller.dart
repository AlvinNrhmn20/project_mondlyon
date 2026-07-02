// lib/core/services/sync_timer_controller.dart
//
// SyncTimerController — Riverpod StateNotifier yang:
//   1. Menentukan state: ready | active | locked
//   2. Menghitung sisa waktu secara real-time menggunakan dart:async Timer.
//
// State Machine:
//   ready  → Belum pernah buka jendela hari ini / hari sudah berganti.
//   active → Jendela sedang terbuka, sisa waktu < 60 menit.
//   locked → Jendela sudah habis untuk hari ini (>= 60 menit sejak dibuka).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_timer_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum SyncWindowStatus { ready, active, locked }

class SyncTimerState {
  const SyncTimerState({
    this.status = SyncWindowStatus.ready,
    this.remaining = Duration.zero,
    this.isLoading = true,
  });

  final SyncWindowStatus status;
  final Duration remaining;
  final bool isLoading;

  SyncTimerState copyWith({
    SyncWindowStatus? status,
    Duration? remaining,
    bool? isLoading,
  }) {
    return SyncTimerState(
      status: status ?? this.status,
      remaining: remaining ?? this.remaining,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

class SyncTimerController extends StateNotifier<SyncTimerState> {
  SyncTimerController() : super(const SyncTimerState()) {
    _init();
  }

  final _service = SyncTimerService();
  Timer? _ticker;

  static const _windowDuration = Duration(hours: 1);

  /// Inisialisasi: baca data dari Supabase lalu mulai timer jika diperlukan.
  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await _refresh();
  }

  /// Ambil data terbaru dari Supabase dan perbarui state.
  Future<void> _refresh() async {
    _ticker?.cancel();

    final data = await _service.fetchSyncStatus();

    if (data == null) {
      // Belum ada record → belum pernah buka kamera
      state = state.copyWith(status: SyncWindowStatus.ready, isLoading: false, remaining: Duration.zero);
      return;
    }

    final windowDate = data['window_date'] as String?;
    final openedAtStr = data['window_opened_at'] as String?;

    if (windowDate == null || openedAtStr == null) {
      state = state.copyWith(status: SyncWindowStatus.ready, isLoading: false, remaining: Duration.zero);
      return;
    }

    // Cek apakah window_date adalah hari ini (local timezone)
    final todayStr = DateTime.now().toLocal().toIso8601String().split('T').first;

    if (windowDate != todayStr) {
      // Hari sudah berganti → reset ke ready
      state = state.copyWith(status: SyncWindowStatus.ready, isLoading: false, remaining: Duration.zero);
      return;
    }

    // Hitung sisa waktu
    final openedAt = DateTime.parse(openedAtStr).toLocal();
    final elapsed = DateTime.now().difference(openedAt);
    final remaining = _windowDuration - elapsed;

    if (remaining.isNegative || remaining == Duration.zero) {
      state = state.copyWith(status: SyncWindowStatus.locked, isLoading: false, remaining: Duration.zero);
    } else {
      state = state.copyWith(
        status: SyncWindowStatus.active,
        isLoading: false,
        remaining: remaining,
      );
      _startTicker();
    }
  }

  /// Mulai periodik ticker setiap detik untuk countdown.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final newRemaining = state.remaining - const Duration(seconds: 1);
      if (newRemaining.isNegative || newRemaining == Duration.zero) {
        _ticker?.cancel();
        state = state.copyWith(status: SyncWindowStatus.locked, remaining: Duration.zero);
      } else {
        state = state.copyWith(remaining: newRemaining);
      }
    });
  }

  /// Dipanggil saat user menyetujui membuka jendela baru.
  Future<void> openWindow() async {
    await _service.openNewWindow();
    await _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final syncTimerProvider = StateNotifierProvider<SyncTimerController, SyncTimerState>((ref) {
  return SyncTimerController();
});
