import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';
import '../profile/post_detail_page.dart';
import '../profile/profile_page.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final _supabase = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _notificationsStream;
  late final String myId;

  // ✅ FIXED: Cache profil di State level — menggantikan FutureBuilder yang
  // menembak query baru setiap kali stream emit (N+1 anti-pattern real-time).
  // Profil hanya di-fetch saat actor_id baru ditemukan yang belum ada di cache.
  final Map<String, Map<String, dynamic>> _cachedProfiles = {};

  // ✅ BUG#4 FIX: Track IDs yang sedang di-fetch untuk mencegah double-rebuild
  // saat _ensureProfilesCached() dipanggil di dalam build().
  final Set<String> _fetchingProfileIds = {};

  // ✅ BUG#2 FIX: Cache status connection per actor_id untuk menyembunyikan
  // tombol Accept/Decline pada notifikasi yang sudah diproses.
  final Map<String, String?> _connectionStatusCache = {};

  @override
  void initState() {
    super.initState();
    myId = _supabase.auth.currentUser!.id;
    _notificationsStream = _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', myId)
        .order('created_at', ascending: false)
        .limit(20);
  }

  /// Fetch profil untuk actor_id yang belum ada di cache.
  /// Dipanggil setiap kali stream emits, tapi hanya query ID yang belum di-cache.
  /// ✅ BUG#4 FIX: Menggunakan _fetchingProfileIds untuk mencegah fetch ulang
  /// saat setState() memicu rebuild dan builder memanggil fungsi ini lagi.
  Future<void> _ensureProfilesCached(List<String> actorIds) async {
    final missingIds = actorIds.where(
      (id) => !_cachedProfiles.containsKey(id) && !_fetchingProfileIds.contains(id),
    ).toList();
    if (missingIds.isEmpty) return;

    _fetchingProfileIds.addAll(missingIds);

    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', missingIds);

      if (mounted) {
        setState(() {
          for (final p in profiles) {
            _cachedProfiles[p['id'] as String] = Map<String, dynamic>.from(p);
          }
        });
      }
    } catch (e) {
      debugPrint('[ActivityPage] Error fetching profiles: $e');
    } finally {
      _fetchingProfileIds.removeAll(missingIds);
    }
  }

  /// ✅ BUG#2 FIX: Cek status connection aktual untuk menentukan apakah
  /// friend_request masih valid (belum di-accept/decline).
  Future<void> _refreshConnectionStatuses(List<String> actorIds) async {
    // Hanya cek actor yang belum pernah di-cache status-nya
    final uncheckedIds = actorIds.where(
      (id) => !_connectionStatusCache.containsKey(id),
    ).toList();
    if (uncheckedIds.isEmpty) return;

    try {
      final results = await _supabase
          .from('connections')
          .select('sender_id, status')
          .eq('receiver_id', myId)
          .inFilter('sender_id', uncheckedIds);

      if (mounted) {
        setState(() {
          // Set null untuk actor yang tidak punya connection row (sudah dihapus)
          for (final id in uncheckedIds) {
            _connectionStatusCache[id] = null;
          }
          // Override dengan data aktual
          for (final row in results) {
            _connectionStatusCache[row['sender_id'] as String] =
                row['status'] as String?;
          }
        });
      }
    } catch (e) {
      debugPrint('[ActivityPage] Error checking connection statuses: $e');
    }
  }

  Future<void> _acceptRequest(String actorId) async {
    try {
      final response = await _supabase
          .from('connections')
          .select('id')
          .eq('sender_id', actorId)
          .eq('receiver_id', myId)
          .eq('status', 'requested')
          .maybeSingle();

      if (response != null) {
        await _supabase.from('connections').update({'status': 'friends'}).eq('id', response['id']);

        // ✅ P3 FIX: Buat notifikasi accept_friend untuk si pengirim request
        await _supabase.from('notifications').upsert({
          'receiver_id': actorId, // target notifikasi
          'actor_id': myId,       // orang yang meng-accept
          'type': 'accept_friend',
        }, onConflict: 'receiver_id,actor_id,type');

        // Note: Kita TIDAK menghapus notifikasi friend_request untuk diri kita sendiri
        // karena stream builder di bawah (line 344) akan merender ulang notifikasi 
        // friend_request menjadi teks "sekarang berteman dengan kamu" jika 
        // status di cache sudah 'friends'.

        // ✅ BUG#2 FIX: Update cache status connection
        _connectionStatusCache[actorId] = 'friends';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permintaan pertemanan diterima!')));
        }
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permintaan ini sudah diproses.')));
      }
    } catch (e) {
      debugPrint('[ActivityPage] Error accepting request: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memproses permintaan. Coba lagi.')));
    }
  }

  Future<void> _declineRequest(String actorId) async {
    try {
      final response = await _supabase
          .from('connections')
          .select('id')
          .eq('sender_id', actorId)
          .eq('receiver_id', myId)
          .eq('status', 'requested')
          .maybeSingle();

      if (response != null) {
        await _supabase.from('connections').delete().eq('id', response['id']);

        // ✅ BUG#1 FIX: Hapus notifikasi friend_request setelah decline
        // agar tidak muncul terus di Activity page.
        await _supabase
            .from('notifications')
            .delete()
            .eq('receiver_id', myId)
            .eq('actor_id', actorId)
            .eq('type', 'friend_request');

        // ✅ BUG#2 FIX: Update cache status connection
        _connectionStatusCache[actorId] = null;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permintaan pertemanan ditolak.')));
        }
      }
    } catch (e) {
      debugPrint('[ActivityPage] Error declining request: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menolak permintaan. Coba lagi.')));
    }
  }

  Future<void> _navigateToPost(Map<String, dynamic> notification) async {
    final postId = notification['post_id'] ?? notification['source_id'];
    if (postId == null) return;
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );

      final postResponse = await _supabase
          .from('posts')
          .select('*, profiles(*)')
          .eq('id', postId)
          .single();

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailPage(post: postResponse),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching post: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post tidak ditemukan atau sudah dihapus.')));
      }
    }
  }

  String _formatTimeAgo(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr).toLocal();
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text(
          'ACTIVITY',
          style: AppTheme.orbitron(fontSize: 13, color: AppColors.textPrimary, letterSpacing: 4),
        ),
        leading: const BackButton(color: Colors.white),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.divider, height: 1),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
             return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
          }
          if (snapshot.hasError) {
             return Center(child: Text('Gagal memuat notifikasi', style: AppTheme.inter(color: Colors.redAccent)));
          }

          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
             return Center(
                child: Text(
                  'Belum ada aktivitas baru.',
                  style: AppTheme.inter(color: AppColors.textSecondary),
                ),
              );
          }

          // ✅ Fetch profil yang belum di-cache secara async.
          // Tidak memblokir render — widget akan rebuild otomatis setelah
          // _ensureProfilesCached() memanggil setState().
          final actorIds = notifications
              .map((n) => n['actor_id'] as String)
              .toSet()
              .toList();
          _ensureProfilesCached(actorIds);

          // ✅ BUG#2 FIX: Cek status connection untuk friend_request
          // agar tombol Accept/Decline disembunyikan jika sudah diproses.
          final friendRequestActorIds = notifications
              .where((n) => n['type'] == 'friend_request')
              .map((n) => n['actor_id'] as String)
              .toSet()
              .toList();
          _refreshConnectionStatuses(friendRequestActorIds);

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(color: AppColors.divider),
            itemBuilder: (context, index) {
              final notif = notifications[index];
              final actorId = notif['actor_id'] as String;
              final type = notif['type'] as String;
              final timeStr = _formatTimeAgo(notif['created_at']);

              // Ambil dari cache — bisa null jika belum selesai fetch
              final profile = _cachedProfiles[actorId];
              final username = profile?['username'] as String? ?? 'User';
              final avatarUrl = profile?['avatar_url'] as String?;

              String message = '';
              Widget? trailing;
              VoidCallback? onTap;
              // ✅ Ikon kosmetik per tipe notifikasi
              IconData typeIcon = Icons.notifications_none_rounded;
              Color typeColor = AppColors.textDisabled;

              switch (type) {
                case 'friend_request':
                  message = 'mengirimkan permintaan pertemanan.';
                  typeIcon = Icons.person_add_alt_1_rounded;
                  typeColor = Theme.of(context).colorScheme.primary;

                  // ✅ BUG#2 FIX: Cek status connection aktual sebelum
                  // menampilkan tombol Accept/Decline. Jika sudah diproses
                  // (friends / null), tampilkan label status saja.
                  final connStatus = _connectionStatusCache[actorId];
                  final isStillRequested = connStatus == 'requested' ||
                      !_connectionStatusCache.containsKey(actorId); // belum di-cache = anggap valid

                  if (isStillRequested) {
                    trailing = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: () => _acceptRequest(actorId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: Text(
                            'Accept',
                            style: AppTheme.inter(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textDisabled),
                          onPressed: () => _declineRequest(actorId),
                        ),
                      ],
                    );
                  } else if (connStatus == 'friends') {
                    message = 'sekarang berteman dengan kamu.';
                    typeIcon = Icons.people_rounded;
                    typeColor = AppColors.neonGreen;
                  } else {
                    // Connection sudah dihapus / declined
                    message = 'permintaan pertemanan sudah diproses.';
                    typeColor = AppColors.textDisabled;
                  }
                  break;
                case 'comment':
                  message = 'mengomentari momenmu.';
                  typeIcon = Icons.chat_bubble_rounded;
                  typeColor = AppColors.neonCyan;
                  onTap = () => _navigateToPost(notif);
                  break;
                case 'reaction':
                  message = 'bereaksi pada momenmu.';
                  typeIcon = Icons.bolt_rounded;
                  typeColor = Colors.amberAccent;
                  onTap = () => _navigateToPost(notif);
                  break;
                case 'accept_friend':
                  message = 'menerima permintaan pertemananmu.';
                  typeIcon = Icons.people_rounded;
                  typeColor = AppColors.neonGreen;
                  // ✅ FIX: Navigasi ke profil teman baru saat tile ditekan.
                  onTap = () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(userId: actorId),
                      ),
                    );
                  };
                  break;
                default:
                  message = 'berinteraksi dengan Anda.';
              }

              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: onTap,
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.surfaceElevated,
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
                          : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, color: AppColors.textDisabled)
                          : null,
                    ),
                    // ✅ Badge ikon tipe notifikasi
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: typeColor, width: 1.5),
                        ),
                        child: Icon(typeIcon, size: 11, color: typeColor),
                      ),
                    ),
                  ],
                ),
                title: RichText(
                  text: TextSpan(
                    style: AppTheme.inter(color: Colors.white, fontSize: 14),
                    children: [
                      TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: ' $message'),
                    ],
                  ),
                ),
                subtitle: Text(
                  timeStr,
                  style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: trailing,
              );
            },
          );
        },
      ),
    );
  }
}
