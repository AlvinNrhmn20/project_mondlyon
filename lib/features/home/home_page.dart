import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';
import '../../core/services/global_audio_player.dart';
import '../../core/services/sync_timer_controller.dart';
import '../profile/post_detail_page.dart';
import '../profile/profile_page.dart';
import '../activity/activity_page.dart';
import '../message/chat_room_page.dart';
import 'real_moji_camera_overlay.dart';
import 'floating_sync_timer.dart';
import 'widgets/dynamic_empty_feed.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HOME PAGE
// ═══════════════════════════════════════════════════════════════════════════

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool isLoading = true;
  bool hasPostedToday = false;
  bool hasNeverPosted = false;   // true → user belum pernah posting sama sekali
  List<dynamic> feedPosts = [];
  String myId = '';
  String _username = '';          // untuk greeting di DynamicEmptyFeed
  // Map untuk menyimpan data profile user yang di-tag agar efisien (batch fetch)
  Map<String, dynamic> taggedProfilesMap = {};
  RealtimeChannel? _postsSubscription;

  // ── Explore Tab State (Dual State — firewall _fetchFeed TIDAK disentuh) ────
  int _activeTab = 0;          // 0 = Friends, 1 = Explore
  List<dynamic> explorePosts = [];
  bool isExploreLoading = false;
  // ✅ POIN 1: Map userId → status koneksi untuk user di Explore tab
  Map<String, String> _exploreConnectionStatuses = {};
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    _postsSubscription = Supabase.instance.client
        .channel('public:posts_home')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            // Ketika ada perubahan pada tabel posts, ambil ulang feed
            _fetchFeed();
          },
        )
        .subscribe();
  }

  Future<void> _fetchFeed() async {
    try {
      final supabase = Supabase.instance.client;
      myId = supabase.auth.currentUser!.id;

      // ── Ambil username untuk greeting ──
      try {
        final profileData = await supabase
            .from('profiles')
            .select('username')
            .eq('id', myId)
            .maybeSingle();
        _username = profileData?['username']?.toString() ?? '';
      } catch (_) {}

      // ── Cek apakah user PERNAH posting (seumur hidup) ──
      try {
        final allTimeCount = await supabase
            .from('posts')
            .count()
            .eq('user_id', myId);
        hasNeverPosted = (allTimeCount as int? ?? 0) == 0;
      } catch (_) {
        hasNeverPosted = false;
      }

      // Cek Status Posting User Hari Ini
      try {
        final stats = await supabase
            .from('user_stats')
            .select('last_post_date')
            .eq('user_id', myId)
            .maybeSingle();

        if (stats != null && stats['last_post_date'] != null) {
          final lastPostDate =
              DateTime.parse(stats['last_post_date']).toLocal();
          final now = DateTime.now();
          hasPostedToday = lastPostDate.year == now.year &&
              lastPostDate.month == now.month &&
              lastPostDate.day == now.day;
        } else {
          hasPostedToday = false;
        }
      } catch (_) {
        hasPostedToday = false;
      }

      // Ambil ID Teman (Mutual)
      final connections1 = await supabase
          .from('connections')
          .select('receiver_id')
          .eq('sender_id', myId)
          .eq('status', 'friends');

      final connections2 = await supabase
          .from('connections')
          .select('sender_id')
          .eq('receiver_id', myId)
          .eq('status', 'friends');

      List<String> validUserIds = [myId];
      for (var row in connections1) {
        validUserIds.add(row['receiver_id'] as String);
      }
      for (var row in connections2) {
        validUserIds.add(row['sender_id'] as String);
      }

      // Ambil Posts — HANYA teman dan diri sendiri (Friends Only Feed)
      // 24-HOUR FEED FILTER: hanya tampilkan post dari 24 jam terakhir.
      final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toUtc().toIso8601String();
      
      final posts = await supabase
          .from('posts')
          .select('*, profiles(username, avatar_url)')
          .inFilter('user_id', validUserIds)
          .or('user_id.eq.$myId,visibility.neq.private')
          .gt('created_at', cutoff)
          .order('created_at', ascending: false)
          .limit(20);

      // --- OPTIMASI QUERY TAGGED USERS ---
      // Kumpulkan semua ID yang di-tag dari seluruh posts di feed
      final Set<String> allTaggedIds = {};
      for (var post in posts) {
        final tagged = post['tagged_users'];
        if (tagged != null && tagged is List) {
          for (var id in tagged) {
            allTaggedIds.add(id.toString());
          }
        }
      }

      Map<String, dynamic> newTaggedProfiles = {};
      if (allTaggedIds.isNotEmpty) {
        // Ambil data profile mereka dalam satu kali query (Batch Fetch)
        final profiles = await supabase
            .from('profiles')
            .select('id, username')
            .inFilter('id', allTaggedIds.toList());
        
        for (var p in profiles) {
          newTaggedProfiles[p['id']] = p;
        }
      }

      if (mounted) {
        setState(() {
          feedPosts = posts;
          taggedProfilesMap = newTaggedProfiles;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching feed: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Explore Feed (Global Public Posts, 24h ephemeral, firewall-safe) ────────
  Future<void> _fetchExplorePosts() async {
    if (isExploreLoading) return;
    if (mounted) setState(() => isExploreLoading = true);
    try {
      final supabase = Supabase.instance.client;
      // Aturan 1: Sama seperti Friends — hanya 24 jam terakhir
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toUtc()
          .toIso8601String();
      // Aturan 2: Hanya public posts — TANPA filter validUserIds (global)
      final posts = await supabase
          .from('posts')
          .select('*, profiles(username, avatar_url)')
          .eq('visibility', 'public')
          .gt('created_at', cutoff)
          .order('created_at', ascending: false)
          .limit(30);

      // Batch fetch tagged users (sama dengan _fetchFeed)
      final Set<String> allTaggedIds = {};
      for (var post in posts) {
        final tagged = post['tagged_users'];
        if (tagged != null && tagged is List) {
          for (var id in tagged) { allTaggedIds.add(id.toString()); }
        }
      }
      if (allTaggedIds.isNotEmpty) {
        final profiles = await supabase
            .from('profiles')
            .select('id, username')
            .inFilter('id', allTaggedIds.toList());
        for (var p in profiles) {
          taggedProfilesMap[p['id']] = p;
        }
      }

      // ✅ POIN 1: Batch-fetch connection status untuk semua author di Explore
      final Set<String> authorIds = {};
      for (var post in posts) {
        final uid = post['user_id'] as String?;
        if (uid != null && uid != myId) authorIds.add(uid);
      }
      Map<String, String> newConnStatuses = {};
      if (authorIds.isNotEmpty) {
        final myConns = await supabase
            .from('connections')
            .select('sender_id, receiver_id, status')
            .or('sender_id.eq.$myId,receiver_id.eq.$myId') as List;
        for (var conn in myConns) {
          final senderId = conn['sender_id'] as String;
          final receiverId = conn['receiver_id'] as String;
          final status = conn['status'] as String;
          final otherId = senderId == myId ? receiverId : senderId;
          if (authorIds.contains(otherId)) newConnStatuses[otherId] = status;
        }
      }

      if (mounted) {
        setState(() {
          explorePosts = posts;
          isExploreLoading = false;
          _exploreConnectionStatuses = newConnStatuses; // ✅ POIN 1
        });
      }
    } catch (e) {
      debugPrint('Error fetching explore: $e');
      if (mounted) setState(() => isExploreLoading = false);
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: AppColors.surfaceElevated,
        edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight,
        onRefresh: () => _fetchFeed(),
        child: Stack(
          children: [
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
          // ── SliverAppBar ────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.black,
            floating: true,
            snap: true,
            title: SizedBox(
              height: 32, // Sedikit diperbesar
              child: Image.asset(
                'lib/assets/images/mondlyon.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high, // Anti-aliasing agar logo 2MB tidak pecah saat dishrink
              ),
            ),
            actions: [
              _buildNotificationIcon(),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: _buildFeedToggle(context),
            ),
          ),

          // ── Content (Tab-Aware) ─────────────────────────────────────────────────────────
          // State: isLoading (Friends initial) | isExploreLoading (Explore lazy)
          if (isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary),
              ),
            )
          else if (_activeTab == 0 && feedPosts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: !hasNeverPosted,
              child: DynamicEmptyFeed(
                hasNeverPosted: hasNeverPosted,
                username: _username,
                onPostAction: () {
                  final syncCtrl = ref.read(syncTimerProvider.notifier);
                  syncCtrl.openWindow();
                },
              ),
            )
          else if (_activeTab == 1 && isExploreLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary),
              ),
            )
          else if (_activeTab == 1 && explorePosts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_outlined,
                        color: AppColors.textDisabled, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'NO PUBLIC POSTS IN THE LAST 24H',
                      style: AppTheme.orbitron(
                        fontSize: 12,
                        color: AppColors.textDisabled,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Builder(builder: (context) {
              final activePosts = _activeTab == 0 ? feedPosts : explorePosts;
              return SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: FeedPostItem(
                        post: activePosts[index],
                        isMyPost: activePosts[index]['user_id'] == myId,
                        isUnlocked: hasPostedToday ||
                            activePosts[index]['user_id'] == myId,
                        // ✅ POIN 1: Explore Add Friend props
                        isExploreTab: _activeTab == 1,
                        connectionStatus: _activeTab == 1
                            ? (_exploreConnectionStatuses[
                                    activePosts[index]['user_id']] ??
                                'none')
                            : 'none',
                        taggedProfiles: taggedProfilesMap,
                        onPostDeleted: _activeTab == 0
                            ? _fetchFeed
                            : _fetchExplorePosts,
                        onAddFriendTap: _activeTab == 1 &&
                                activePosts[index]['user_id'] != myId
                            ? () async {
                                final uid =
                                    activePosts[index]['user_id'] as String?;
                                if (uid == null) return;
                                try {
                                  // ✅ P1 FIX: .upsert() mencegah Unique Constraint violation
                                  await Supabase.instance.client
                                      .from('connections')
                                      .upsert({
                                    'sender_id': myId,
                                    'receiver_id': uid,
                                    'status': 'requested',
                                  }, onConflict: 'sender_id,receiver_id');
                                  if (!mounted) return;
                                  setState(() => _exploreConnectionStatuses[
                                      uid] = 'requested');
                                  // Chat tersedia via ProfilePage (tap avatar) — tidak auto-navigate
                                } catch (_) {}
                              }
                            : null,
                        onUnlockTap: () {
                          final syncCtrl =
                              ref.read(syncTimerProvider.notifier);
                          syncCtrl.openWindow();
                        },
                      ),
                    ),
                    childCount: activePosts.length,
                  ),
                ),
              );
            }),
              ],  // close slivers
            ), // close CustomScrollView
            // ── Floating Sync Timer ─────────────────────────
            const FloatingSyncTimer(),
          ], // close Stack children
        ), // close Stack
      ), // close RefreshIndicator
    );
  }

  // ── Feed Toggle UI ───────────────────────────────────────────────────────────────────────
  Widget _buildFeedToggle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(
              height: 48, // ✅ FIX P4: Min 48px tap target
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleButton(context, 'Friends',
                      Icons.people_outline_rounded, 0),
                  _buildToggleButton(context, 'Explore',
                      Icons.explore_outlined, 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(
      BuildContext context, String label, IconData icon, int index) {
    final isActive = _activeTab == index;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () {
        if (_activeTab == index) return;
        setState(() => _activeTab = index);
        // Lazy load: fetch Explore hanya saat tab pertama kali dibuka
        if (index == 1 && explorePosts.isEmpty && !isExploreLoading) {
          _fetchExplorePosts();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              // ✅ P4 FIX: Putih murni saat aktif agar kontras di atas background primary
              color:
                  isActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                // ✅ P4 FIX: Putih murni saat aktif agar kontras di atas background primary
                color:
                    isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNotificationIcon() {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      // ✅ FIXED: Server-side filter pada receiver_id — hanya data milik user ini
      // yang di-stream, bukan seluruh tabel (supabase_flutter v2 hanya support 1 .eq()).
      // Filter status 'requested' dilakukan client-side di bawah.
      stream: supabase
          .from('connections')
          .stream(primaryKey: ['id'])
          .eq('receiver_id', userId),
      builder: (context, snapshot) {
        final allReceived = snapshot.data ?? [];
        // Client-side filter: hanya hitung yang masih 'requested'
        final hasRequests = allReceived.any((c) => c['status'] == 'requested');


        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ActivityPage()),
                );
              },
            ),
            if (hasRequests)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _postsSubscription?.unsubscribe();
    super.dispose();
  }
}



// ═══════════════════════════════════════════════════════════════════════════
// FEED POST ITEM — StatefulWidget dengan state PiP-nya sendiri
// ═══════════════════════════════════════════════════════════════════════════

class FeedPostItem extends StatefulWidget {
  final dynamic post;
  final bool isMyPost;
  final bool isUnlocked;
  final Map<String, dynamic> taggedProfiles;
  final VoidCallback? onPostDeleted;
  /// Dipanggil saat user mengetuk area 'Post to view' yang masih terkunci.
  /// Parent bertanggung jawab untuk membuka kamera/sync window.
  final VoidCallback? onUnlockTap;

  final bool isExploreTab;
  final String connectionStatus;
  final VoidCallback? onAddFriendTap;

  const FeedPostItem({
    super.key,
    required this.post,
    required this.isMyPost,
    required this.isUnlocked,
    this.isExploreTab = false,
    this.connectionStatus = 'none',
    this.taggedProfiles = const {},
    this.onPostDeleted,
    this.onUnlockTap,
    this.onAddFriendTap,
  });

  @override
  State<FeedPostItem> createState() => _FeedPostItemState();
}

class _FeedPostItemState extends State<FeedPostItem> with WidgetsBindingObserver {
  // ── PiP State ──────────────────────────────────────────────────────────
  Offset pipPosition = const Offset(16, 16);
  bool isFrontMain = false;
  bool _isNavigating = false;

  // ── RealMoji State ────────────────────────────────────────────────────
  /// URL gambar RealMoji yang berhasil dikirim. Null jika belum pernah bereaksi.
  String? reactionImageUrl;
  String? reactionEmojiType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchMyReaction();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      GlobalAudioPlayer().pause();
    }
  }

  Future<void> _fetchMyReaction() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('post_reactions')
          .select()
          .eq('post_id', widget.post['id'])
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          reactionImageUrl = response['reaction_image_url'] as String?;
          reactionEmojiType = response['emoji_type'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reaction: $e');
    }
  }

  Future<void> _deleteReaction() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('post_reactions')
          .delete()
          .eq('post_id', widget.post['id'])
          .eq('user_id', userId);
      
      if (mounted) {
        setState(() {
          reactionImageUrl = null;
          reactionEmojiType = null;
        });
      }
    } catch (e) {
      debugPrint('Error deleting reaction: $e');
    }
  }

  String _getEmojiIcon(String type) {
    switch (type) {
      case 'like': return '👍';
      case 'happy': return '😃';
      case 'surprised': return '😯';
      case 'laughing': return '😂';
      case 'instant': return '⚡';
      default: return type; // fallback
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _formatTimeAgo(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes < 1 ? 1 : diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  void _onReplyMessage() {
    final profile = widget.post['profiles'] as Map? ?? {};
    final friendId = widget.post['user_id'] as String? ?? '';
    final friendName = (profile['full_name'] as String? ?? profile['username'] as String? ?? 'Unknown');
    final friendUsername = profile['username'] as String? ?? 'unknown';
    final friendAvatar = profile['avatar_url'] as String? ?? '';

    if (friendId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomPage(
          friendId: friendId,
          friendName: friendName,
          friendUsername: friendUsername,
          friendAvatar: friendAvatar,
          postId: widget.post['id']?.toString(),
          postThumbnailUrl: widget.post['back_video_url'] as String?,
        ),
      ),
    );
  }

  void _onOpenComments() async {
    _isNavigating = true;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailPage(
          post: Map<String, dynamic>.from(widget.post as Map),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  void _onOpenRealMoji() {
    final postId = widget.post['id']?.toString();
    if (postId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => RealMojiMenuSheet(
        postId: postId,
        parentContext: context, // context FeedPostItem yang tetap hidup
        onCameraSuccess: (url, emojiType) {
          setState(() {
            reactionImageUrl = url;
            reactionEmojiType = emojiType;
          });
        },
      ),
    ).then((_) {
      // Refresh saat bottom sheet ditutup (untuk menangkap reaksi emoji biasa)
      _fetchMyReaction();
    });
  }

  Future<void> _reportPost(String postId) async {
    final supabase = Supabase.instance.client;
    final reporterId = supabase.auth.currentUser?.id;
    if (reporterId == null) return;

    try {
      await supabase.from('reports').insert({
        'post_id': postId,
        'reporter_id': reporterId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for keeping SyncReal safe! Report submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit report: $e')),
        );
      }
    }
  }

  void _confirmReportPost(String postId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Report Post', style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Report this post for inappropriate content?', style: AppTheme.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTheme.inter(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reportPost(postId);
            },
            child: Text('Report', style: AppTheme.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;
    final isMyPost = widget.post['user_id'] == currentUserId;
    final postId = widget.post['id'].toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: Text('Share', style: AppTheme.inter(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  SharePlus.instance.share(
                    ShareParams(text: 'Check out this SyncReal post! [AppURL]'),
                  );
                },
              ),
              if (isMyPost)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Delete Post', style: AppTheme.inter(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeletePost(postId);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined, color: Colors.white),
                  title: Text('Report Post', style: AppTheme.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmReportPost(postId);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeletePost(String postId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Delete Post', style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this post?', style: AppTheme.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: AppTheme.inter(color: Colors.white)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await Supabase.instance.client.from('posts').delete().eq('id', postId);
                if (!mounted) return;
                if (widget.onPostDeleted != null) {
                  widget.onPostDeleted!();
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete post: $e')));
              }
            },
            child: Text('Delete', style: AppTheme.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile = widget.post['profiles'] ?? {};
    final username = profile['username'] ?? 'unknown';
    final avatarUrl = profile['avatar_url'];
    final timeAgo = _formatTimeAgo(widget.post['created_at']);
    final caption = widget.post['caption'] ?? '';

    String? previewUrl;
    try {
      final rawMusic = widget.post['spotify_data'];
      if (rawMusic != null) {
        final Map<String, dynamic> music = rawMusic is String 
            ? jsonDecode(rawMusic) 
            : Map<String, dynamic>.from(rawMusic as Map);
        previewUrl = music['preview_url'];
      }
    } catch (_) {}

    return VisibilityDetector(
      key: Key('feed_post_${widget.post['id']}'),
      onVisibilityChanged: (info) async {
        if (_isNavigating) return;
        
        if (previewUrl == null) return;
        
        if (info.visibleFraction >= 0.7) {
          if (GlobalAudioPlayer().currentUrl.value != previewUrl || !GlobalAudioPlayer().isPlaying.value) {
            try {
              await GlobalAudioPlayer().play(previewUrl);
            } catch (_) {}
          }
        } else {
          if (GlobalAudioPlayer().currentUrl.value == previewUrl && GlobalAudioPlayer().isPlaying.value) {
            try {
              await GlobalAudioPlayer().pause();
            } catch (_) {}
          }
        }
      },
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: AppColors.surfaceElevated,
            blurRadius: 10,
            spreadRadius: 1,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    final uid = widget.post['user_id']?.toString();
                    if (uid != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage(userId: uid)));
                    }
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.surfaceElevated,
                    backgroundImage: avatarUrl != null &&
                            avatarUrl.toString().isNotEmpty
                        ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
                        : null,
                    child: (avatarUrl == null || avatarUrl.toString().isEmpty)
                        ? Icon(Icons.person,
                            size: 20, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final uid = widget.post['user_id']?.toString();
                      if (uid != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage(userId: uid)));
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // Baris 1: Username & TimeAgo
                      Row(
                        children: [
                          Text(
                            username,
                            style: AppTheme.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: AppTheme.inter(color: AppColors.textDisabled, fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeAgo,
                            style: AppTheme.inter(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      // Baris 2: Location
                      if (widget.post['weather_data'] != null) ...[
                        const SizedBox(height: 2),
                        Builder(
                          builder: (context) {
                            try {
                              final rawWeather = widget.post['weather_data'];
                              if (rawWeather == null) return const SizedBox.shrink();
                              
                              final Map<String, dynamic> weather = rawWeather is String 
                                  ? jsonDecode(rawWeather) 
                                  : Map<String, dynamic>.from(rawWeather as Map);

                              return Row(
                                children: [
                                  const Icon(Icons.location_on, size: 12, color: AppColors.textDisabled),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${weather['location']}, ${weather['temperature']}',
                                      style: AppTheme.inter(
                                        color: AppColors.textDisabled,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            } catch (_) {
                              return const SizedBox.shrink();
                            }
                          },
                        ),
                      ],
                      // Baris 3: Music
                      if (widget.post['spotify_data'] != null) ...[
                        const SizedBox(height: 2),
                        Builder(
                          builder: (context) {
                            try {
                              final rawMusic = widget.post['spotify_data'];
                              if (rawMusic == null) return const SizedBox.shrink();
                              
                              final Map<String, dynamic> music = rawMusic is String 
                                  ? jsonDecode(rawMusic) 
                                  : Map<String, dynamic>.from(rawMusic as Map);

                              final title = music['title'] ?? 'Unknown';
                              final artist = music['artist'] ?? 'Unknown Artist';
                              final previewUrl = music['preview_url'];

                              return ValueListenableBuilder<bool>(
                                valueListenable: GlobalAudioPlayer().isPlaying,
                                builder: (context, isPlaying, child) {
                                  final isThisPlaying = GlobalAudioPlayer().currentUrl.value == previewUrl && isPlaying;

                                  return GestureDetector(
                                    onTap: () async {
                                      if (previewUrl == null) return;
                                      if (isThisPlaying) {
                                        await GlobalAudioPlayer().pause();
                                      } else {
                                        await GlobalAudioPlayer().play(previewUrl);
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.music_note, 
                                          size: 12, 
                                          color: isThisPlaying ? Theme.of(context).colorScheme.primary : AppColors.textDisabled,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$title • $artist',
                                            style: AppTheme.inter(
                                              color: isThisPlaying ? Theme.of(context).colorScheme.primary : AppColors.textDisabled,
                                              fontSize: 12,
                                              fontWeight: isThisPlaying ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            } catch (_) {
                              return const SizedBox.shrink();
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                ),
                // ✅ POIN 1: Add Friend button di Explore tab
                if (widget.isExploreTab && !widget.isMyPost) ...[
                  if (widget.connectionStatus == 'none')
                    GestureDetector(
                      onTap: widget.onAddFriendTap,
                      child: Container(
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Add',
                              style: AppTheme.inter(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (widget.connectionStatus == 'requested')
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle_outline,
                          color: AppColors.textDisabled, size: 18),
                    ),
                ],
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: AppColors.textDisabled),
                  onPressed: _showMoreOptions,
                ),
              ],
            ),
          ),

          // ── Media Stack ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: _buildMediaStack(),
          ),

          // ── Footer / Caption (tap → PostDetailPage) ──────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onOpenComments,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Display Tagged Users (Elegantly)
                  _buildTaggedUsersLabel(),
                  
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      style: AppTheme.inter(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildTaggedUsersLabel() {
    final taggedIds = widget.post['tagged_users'] as List?;
    if (taggedIds == null || taggedIds.isEmpty) return const SizedBox.shrink();

    final List<Widget> spans = [
      Text('with ', style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
    ];

    for (int i = 0; i < taggedIds.length; i++) {
      final id = taggedIds[i].toString();
      final profile = widget.taggedProfiles[id];
      if (profile != null) {
        spans.add(
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage(userId: id)));
            },
            child: Text('@${profile['username']}', style: AppTheme.inter(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
          ),
        );
        if (i < taggedIds.length - 1) {
          spans.add(Text(', ', style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)));
        }
      }
    }

    if (spans.length == 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: spans,
      ),
    );
  }

  // ── Media Stack Builder ───────────────────────────────────────────────

  Widget _buildMediaStack() {
    final backUrl = widget.post['back_video_url']?.toString() ?? '';
    final frontUrl = widget.post['front_video_url']?.toString() ?? '';

    // Tentukan mana gambar utama dan mana PiP berdasarkan isFrontMain
    final mainUrl = isFrontMain ? frontUrl : backUrl;
    final pipUrl = isFrontMain ? backUrl : frontUrl;

    // Ukuran area gambar utama
    const double cardHeight = 440;
    const double pipW = 90.0;
    const double pipH = 120.0;
    // Batas clamp agar PiP tidak keluar area
    const double maxPipY = cardHeight - pipH - 8;

    Widget mediaContent = LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── Gambar Utama ───────────────────────────────────────────
            GestureDetector(
              onTap: widget.isUnlocked ? _onOpenComments : null,
              child: mainUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: mainUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2)),
                      errorWidget: (context, url, error) => Container(color: AppColors.surfaceElevated, child: const Icon(Icons.broken_image, color: AppColors.textDisabled)),
                    )
                  : Container(color: AppColors.surfaceElevated),
            ),

            // ── PiP: Draggable & Swappable ─────────────────────────────
            Positioned(
              left: pipPosition.dx.clamp(8.0, areaW - pipW - 8),
              top: pipPosition.dy.clamp(8.0, maxPipY),
              child: GestureDetector(
                // Tap: tukar gambar utama ↔ PiP
                onTap: () => setState(() => isFrontMain = !isFrontMain),
                // Drag: geser posisi PiP
                onPanUpdate: (details) {
                  setState(() {
                    pipPosition = Offset(
                      (pipPosition.dx + details.delta.dx)
                          .clamp(8.0, areaW - pipW - 8),
                      (pipPosition.dy + details.delta.dy)
                          .clamp(8.0, maxPipY),
                    );
                  });
                },
                child: Container(
                  width: pipW,
                  height: pipH,
                  decoration: BoxDecoration(
                    color: AppColors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.neonCyan, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonCyan.withValues(alpha: 0.25),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: pipUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: pipUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: AppColors.surfaceElevated),
                            errorWidget: (context, url, error) => Container(color: AppColors.surfaceElevated),
                          )
                        : Container(color: AppColors.surfaceElevated),
                  ),
                ),
              ),
            ),

            // ── Tombol Interaksi ─
            if (widget.isUnlocked && !widget.isMyPost)
              Positioned(
                bottom: 14,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInteractionButton(
                      icon: Icons.emoji_emotions_outlined,
                      onPressed: _onOpenRealMoji,
                    ),
                    const SizedBox(height: 10),
                    _buildInteractionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      onPressed: _onOpenComments,
                    ),
                    const SizedBox(height: 10),
                    _buildInteractionButton(
                      icon: Icons.send_rounded,
                      onPressed: _onReplyMessage,
                    ),
                  ],
                ),
              ),

            // ── RealMoji badge (pojok kiri bawah, muncul setelah bereaksi) ─
            if (widget.isUnlocked && (reactionImageUrl != null || reactionEmojiType != null))
              Positioned(
                bottom: 12,
                left: 12,
                child: GestureDetector(
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppColors.surfaceCard,
                        title: Text('Hapus RealMoji?', style: AppTheme.orbitron(color: Colors.white, fontSize: 18)),
                        content: Text('Hapus reaksi ini dari momen temanmu?', style: AppTheme.inter(color: AppColors.textSecondary)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Batal', style: AppTheme.inter(color: AppColors.textDisabled)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteReaction();
                            },
                            child: Text('Hapus', style: AppTheme.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                          boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                        ),
                        child: ClipOval(
                          child: reactionImageUrl != null
                              ? Transform.scale(
                                  scaleX: -1,
                                  child: CachedNetworkImage(
                                    imageUrl: reactionImageUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: AppColors.surfaceCard),
                                    errorWidget: (context, url, error) => Container(
                                      color: AppColors.surfaceCard,
                                      child: Icon(Icons.person,
                                          color: Theme.of(context).colorScheme.primary, size: 20),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: AppColors.surfaceCard,
                                  child: Icon(Icons.person,
                                      color: Theme.of(context).colorScheme.primary, size: 20),
                                ),
                        ),
                      ),
                      if (reactionEmojiType != null)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceCard,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _getEmojiIcon(reactionEmojiType!),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );

    // ── Blur overlay jika belum posting ──────────────────────────────────────
    if (!widget.isUnlocked) {
      mediaContent = GestureDetector(
        onTap: widget.onUnlockTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
              child: mediaContent,
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Ikon kamera dengan animasi pulse glow ──
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOut,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    onEnd: () => setState(() {}),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                            blurRadius: 24,
                            spreadRadius: 6,
                          )
                        ],
                      ),
                      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 44),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Post to view',
                    style: AppTheme.orbitron(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ).copyWith(shadows: [
                      Shadow(
                        color: Theme.of(context).colorScheme.primary,
                        blurRadius: 10,
                      )
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded,
                            color: Theme.of(context).colorScheme.primary, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Tap to open camera',
                          style: AppTheme.inter(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 440,
        width: double.infinity,
        child: mediaContent,
      ),
    );
  }

  // ── Interaction Button (ukuran lebih kecil & proporsional) ───────────

  Widget _buildInteractionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              blurRadius: 6,
            )
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}


