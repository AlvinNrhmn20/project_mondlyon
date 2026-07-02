// lib/core/services/sync_timer_service.dart
//
// SyncTimerService — layer for interacting with the `user_sync_status` table.
// Responsible for reading/writing window_opened_at timestamps only.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:supabase_flutter/supabase_flutter.dart';

class SyncTimerService {
  final _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser!.id;

  /// Ambil row user_sync_status milik user yang login.
  /// Mengembalikan null jika belum ada record.
  Future<Map<String, dynamic>?> fetchSyncStatus() async {
    try {
      final data = await _supabase
          .from('user_sync_status')
          .select('window_opened_at, window_date')
          .eq('user_id', _userId)
          .maybeSingle();
      return data;
    } catch (e) {
      return null;
    }
  }

  /// Buka jendela 1 jam baru: simpan window_opened_at = now() dan
  /// window_date = tanggal hari ini.
  Future<void> openNewWindow() async {
    final now = DateTime.now().toUtc();
    try {
      await _supabase.from('user_sync_status').upsert(
        {
          'user_id': _userId,
          'window_opened_at': now.toIso8601String(),
          'window_date': now.toIso8601String().split('T').first, // 'YYYY-MM-DD'
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      // Rethrow to be caught by the UI/Controller
      rethrow;
    }
  }
}
