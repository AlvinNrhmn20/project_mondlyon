// lib/features/profile/profile_page.dart
//
// ProfilePage — authenticated user's profile screen.
//
// Scroll structure (CustomScrollView):
//   1. SliverAppBar       — pinned, settings + share actions
//   2. SliverToBoxAdapter — _ProfileHeader  (avatar, bio, stats)
//   3. SliverToBoxAdapter — _ImpactSection  (streak card, KPIs, bar chart)
//   4. SliverToBoxAdapter — _HobbiesSection (NeonChip grid)
//   5. SliverGrid         — _MomentsSection (2-col thumbnail grid)
//   6. SliverToBoxAdapter — bottom padding
//
// This file ONLY contains profile-specific widgets.
// Shared primitives live in:
//   package:syncreal/shared/widgets/lucide_icons.dart  → LucideIcon, LucideIcons
//   package:syncreal/shared/widgets/neon_widgets.dart  → NeonCard, NeonChip,
//                                                        NeonOutlineButton,
//                                                        SectionLabel
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui'; // P2: ImageFilter untuk BackdropFilter blur overlay
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';
import 'package:syncreal/shared/widgets/neon_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_profile/edit_profile_page.dart';
import 'settings_page.dart';
import 'post_detail_page.dart';
import 'connections_page.dart';
import 'memories_page.dart';
import '../message/chat_room_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local data models
// ─────────────────────────────────────────────────────────────────────────────

class _HobbyTag {
  const _HobbyTag(this.label, this.color);
  final String label;
  final Color color;
}

class _BarData {
  const _BarData(this.day, this.value); // value: 0.0–1.0
  final String day;
  final double value;
}


// ─────────────────────────────────────────────────────────────────────────────
// ProfilePage
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  late final AnimationController _barsController;
  late final AnimationController _streakPulseController;
  late final AnimationController _avatarGlowController;

  final GlobalKey momentsKey = GlobalKey();
  final GlobalKey impactKey = GlobalKey();

  // ── State Variables ────────────────────────────────────────────────────────
  bool get isMe => widget.userId == null || widget.userId == Supabase.instance.client.auth.currentUser?.id;
  String connectionStatus = 'none';

  String _username = '';
  String _displayName = '';
  String _bio = '';
  String? _avatarUrl;
  List<_HobbyTag> _hobbies = [];
  List<Map<String, dynamic>> _userPosts = [];
  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  bool _isPrivateProfile = false;
  RealtimeChannel? _profilePostsSubscription;

  // ── New Rich Profile Fields ──
  String _location = '';
  String _education = '';
  String _work = '';
  String? _astrologicalSign;

  // ── P2: Has Posted Today (untuk logika gembok _MomentTile) ───────────────
  bool _myHasPostedToday = false;
  // ─────────────────────────────────────────────────────────────────────────

  // ── Dynamic Impact Stats ──
  int totalMoments = 0;
  int totalFriends = 0;    // status == 'friends'
  int totalFollowers = 0;  // status == 'requested' where receiver_id == targetId
  int totalFollowing = 0;  // status == 'requested' where sender_id == targetId
  int impactScore = 0;
  int dayStreak = 0;
  double syncRate = 0.0;
  String topHobby = '-';

  List<double> _weeklyData = List.filled(7, 0.0);

  List<_BarData> get _dynamicWeeklyBars {
    final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return List.generate(7, (i) => _BarData(days[i], _weeklyData[i]));
  }

  Future<void> _fetchProfileStats() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final targetId = widget.userId ?? user.id;

      // 1. Total Moments
      final Future<dynamic> momentsFuture = Supabase.instance.client
          .from('posts')
          .count()
          .eq('user_id', targetId);

      // 2. Total Friends (status == 'friends', both directions)
      final Future<dynamic> friendsFuture = Supabase.instance.client
          .from('connections')
          .count()
          .or('sender_id.eq.$targetId,receiver_id.eq.$targetId')
          .eq('status', 'friends');

      // 3. Total Followers (pending requests TO this user)
      final Future<dynamic> followersFuture = Supabase.instance.client
          .from('connections')
          .count()
          .eq('receiver_id', targetId)
          .eq('status', 'requested');

      // 4. Total Following (pending requests FROM this user)
      final Future<dynamic> followingFuture = Supabase.instance.client
          .from('connections')
          .count()
          .eq('sender_id', targetId)
          .eq('status', 'requested');

      // 5. User stats (sync rate & top hobby — streak dihitung secara dinamis)
      final Future<dynamic> statsFuture = Supabase.instance.client
          .from('user_stats')
          .select('sync_rate, top_hobby')
          .eq('user_id', targetId)
          .maybeSingle();

      // ✅ B1 FIX: Ambil SEMUA created_at post untuk kalkulasi streak dinamis
      // Tidak lagi bergantung pada user_stats.streak_count yang bisa stale.
      final Future<dynamic> postDatesFuture = Supabase.instance.client
          .from('posts')
          .select('created_at')
          .eq('user_id', targetId);

      final results = await Future.wait([
        momentsFuture, friendsFuture, followersFuture, followingFuture,
        statsFuture, postDatesFuture,
      ]);

      final momentsCount   = results[0] as int? ?? 0;
      final friendsCount   = results[1] as int? ?? 0;
      final followersCount = results[2] as int? ?? 0;
      final followingCount = results[3] as int? ?? 0;
      final statsData      = results[4] as Map<String, dynamic>?;
      final postDatesData  = results[5] as List<dynamic>? ?? [];

      // ✅ B1 FIX: Hitung streak dari data post aktual (timezone-aware)
      final int newStreak = _calculateStreak(postDatesData);
      double newSyncRate = 0.0;
      String newTopHobby = '-';

      if (statsData != null) {
        final rawSync = statsData['sync_rate'];
        if (rawSync is num) newSyncRate = rawSync.toDouble();
        newTopHobby = statsData['top_hobby']?.toString() ?? '-';
      }

      final newImpactScore = (momentsCount * 5) + (newStreak * 10);

      if (mounted) {
        setState(() {
          totalMoments   = momentsCount;
          totalFriends   = friendsCount;
          totalFollowers = followersCount;
          totalFollowing = followingCount;
          dayStreak      = newStreak;
          syncRate      = newSyncRate;
          topHobby      = newTopHobby;
          impactScore   = newImpactScore;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile stats: $e');
    }
  }

  /// ✅ B1 FIX: Menghitung streak secara lokal dari tanggal post aktual.
  /// Menghindari ketergantungan pada user_stats.streak_count yang bisa stale
  /// atau tidak ter-update saat melihat profil orang lain.
  int _calculateStreak(List<dynamic> postDates) {
    if (postDates.isEmpty) return 0;

    // Kumpulkan hari-hari unik dalam waktu LOKAL dari semua post
    final Set<DateTime> uniqueDays = {};
    for (var p in postDates) {
      final raw = p['created_at']?.toString();
      if (raw == null) continue;
      try {
        final dt = DateTime.parse(raw).toLocal();
        uniqueDays.add(DateTime(dt.year, dt.month, dt.day));
      } catch (_) {}
    }

    if (uniqueDays.isEmpty) return 0;

    final now = DateTime.now();
    final todayDay = DateTime(now.year, now.month, now.day);
    final yesterdayDay = todayDay.subtract(const Duration(days: 1));

    // Streak hanya valid jika user posting hari ini ATAU kemarin
    if (!uniqueDays.contains(todayDay) && !uniqueDays.contains(yesterdayDay)) {
      return 0;
    }

    // Mulai dari hari ini (atau kemarin jika hari ini belum posting)
    final DateTime startDay =
        uniqueDays.contains(todayDay) ? todayDay : yesterdayDay;

    int streak = 0;
    DateTime checkDay = startDay;
    while (uniqueDays.contains(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _fetchProfileData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final targetId = widget.userId ?? user.id;

      final Future<dynamic> profilesFuture = Supabase.instance.client
          .from('profiles')
          .select('username, full_name, bio, dob, avatar_url, is_private, location, education, work, astrological_sign')
          .eq('id', targetId)
          .single();

      final Future<dynamic> userHobbiesFuture = Supabase.instance.client
          .from('user_hobbies')
          .select('hobby_id')
          .eq('user_id', targetId);

      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      // ── P2: Hitung awal hari ini (UTC) untuk query posting hari ini ──────
      final todayStartUtc =
          DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      // ─────────────────────────────────────────────────────────────────────

      final Future<dynamic> recentPostsFuture = Supabase.instance.client
          .from('posts')
          .select('created_at')
          .eq('user_id', targetId)
          .gte('created_at', sevenDaysAgo.toUtc().toIso8601String());

      final Future<dynamic> allPostsFuture = Supabase.instance.client
          .from('posts')
          // ✅ B2 FIX: Join profiles agar PostDetailPage dapat data header yang benar
          .select('*, profiles(username, avatar_url)')
          .eq('user_id', targetId)
          .order('created_at', ascending: false);

      final Future<dynamic> connectionStatusFuture = isMe
          ? Future.value(null)
          : Supabase.instance.client
              .from('connections')
              .select('status')
              .or('and(sender_id.eq.${user.id},receiver_id.eq.$targetId),and(sender_id.eq.$targetId,receiver_id.eq.${user.id})')
              .maybeSingle();

      // ── P2: Query ringan — apakah MY USER sudah posting hari ini? ────────
      // Jika isMe, lock tidak berlaku jadi skip query (selalu unlocked).
      final Future<dynamic> myTodayPostsFuture = isMe
          ? Future.value(1)
          : Supabase.instance.client
              .from('posts')
              .count()
              .eq('user_id', user.id)
              .gte('created_at', todayStartUtc);
      // ─────────────────────────────────────────────────────────────────────

      final results = await Future.wait<dynamic>([
        profilesFuture,        // 0
        userHobbiesFuture,     // 1
        recentPostsFuture,     // 2
        allPostsFuture,        // 3
        connectionStatusFuture, // 4
        myTodayPostsFuture,    // 5 — P2
      ]);

      final profilesData = results[0] as Map<String, dynamic>;
      final uhList = results[1] as List<dynamic>? ?? [];
      final recentPostsData = results[2] as List<dynamic>? ?? [];
      final allPostsData = results[3] as List<dynamic>? ?? [];
      final connStatusData = results[4] as Map<String, dynamic>?;
      final myTodayCount = isMe ? 1 : (results[5] as int? ?? 0);


      final List<dynamic> hobbyIds =
          uhList.map((uh) => uh['hobby_id']).toList();

      List<double> weeklyCounts = List.filled(7, 0.0);
      for (var post in recentPostsData) {
        if (post['created_at'] != null) {
          final parsedDate = DateTime.tryParse(post['created_at'].toString());
          if (parsedDate != null) {
            final date = parsedDate.toLocal();
            int dayIndex = date.weekday - 1;
            weeklyCounts[dayIndex]++; // ✅ P3 Fix: Hapus print() di production
          }
        }
      }

      List<_HobbyTag> fetchedHobbies = [];
      if (hobbyIds.isNotEmpty) {
        // Ambil nama hobi dari tabel hobbies berdasarkan id
        final hobbiesData = await Supabase.instance.client
            .from('hobbies')
            .select('name')
            .inFilter('id', hobbyIds);

        final List<dynamic> hList = hobbiesData as List<dynamic>? ?? [];
        fetchedHobbies = hList.map((h) {
          final hobbyName = h['name']?.toString() ?? 'Unknown';
          return _HobbyTag(hobbyName, Theme.of(context).colorScheme.primary);
        }).toList();
      }

      if (mounted) {
        setState(() {
          final rawUsername = profilesData['username']?.toString() ?? '';
          _username =
              rawUsername.startsWith('@') ? rawUsername : '@$rawUsername';

          final fullName = profilesData['full_name']?.toString();
          _displayName = (fullName != null && fullName.isNotEmpty)
              ? fullName
              : rawUsername.replaceAll(
                  '@', ''); // Fallback ke username jika full_name kosong

          _bio = profilesData['bio']?.toString() ?? '';
          _avatarUrl = profilesData['avatar_url']?.toString();
          _isPrivateProfile = profilesData['is_private'] as bool? ?? false;
          _location = profilesData['location']?.toString() ?? '';
          _education = profilesData['education']?.toString() ?? '';
          _work = profilesData['work']?.toString() ?? '';
          _astrologicalSign = profilesData['astrological_sign']?.toString();

          _weeklyData = weeklyCounts;
          
          if (!isMe && connStatusData != null) {
            connectionStatus = connStatusData['status']?.toString() ?? 'none';
          } else {
            connectionStatus = 'none';
          }

          // ── HYBRID PRIVACY FILTER (Master Switch) ──
          List<Map<String, dynamic>> safePosts = [];
          for (var p in allPostsData) {
            final vis = p['visibility'];
            if (isMe) {
              safePosts.add(Map<String, dynamic>.from(p));
            } else if (connectionStatus == 'friends') {
              if (vis == 'public' || vis == 'friends') {
                safePosts.add(Map<String, dynamic>.from(p));
              }
            } else {
              // Stranger / Requested
              if (vis == 'public') {
                safePosts.add(Map<String, dynamic>.from(p));
              }
            }
          }
          _userPosts = safePosts;

          // ── P2: Set state gembok ──────────────────────────────────────────
          _myHasPostedToday = myTodayCount > 0;
          // ─────────────────────────────────────────────────────────────────

          _hobbies = fetchedHobbies;
          _isLoading = false;
        });

        // Trigger ulang animasi bar chart setelah data berhasil diload
        _barsController.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );

      if (image == null) return;

      setState(() => _isUploadingAvatar = true);

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final file = File(image.path);
      final fileExt = image.path.split('.').last;
      final fileName =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await Supabase.instance.client.storage.from('avatars').upload(
            fileName,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      final String publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': publicUrl}).eq('id', user.id);

      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
          _isUploadingAvatar = false;
        });
      }
    } catch (e) {
      debugPrint('Error uploading avatar: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to upload image: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showAvatarOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.black,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border:
                Border(top: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'UPDATE AVATAR',
                style: AppTheme.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const LucideIcon(
                    icon: LucideIcons.camera, color: AppColors.neonCyan),
                title: Text('Take a Photo',
                    style: AppTheme.inter(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _uploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: LucideIcon(
                    icon: LucideIcons.image, color: Theme.of(context).colorScheme.primary),
                title: Text('Choose from Gallery',
                    style: AppTheme.inter(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _uploadAvatar(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // ✅ FIX P6: Reset semua variabel stat ke 0 SECARA SINKRON sebelum fetch
    // agar tidak ada data stale dari profil sebelumnya yang bocor ke UI.
    dayStreak = 0;
    totalMoments = 0;
    totalFriends = 0;
    totalFollowers = 0;
    totalFollowing = 0;
    impactScore = 0;
    syncRate = 0.0;
    topHobby = '-';
    // ✅ FIX P6: Gunakan Future.wait agar stats & profile data diinisialisasi
    // secara terkoordinasi — mencegah race condition antar kedua fetch.
    _initProfileData();
    _setupRealtimeSubscription();
    _barsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _streakPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  /// Menggabungkan kedua fetch dengan Future.wait agar keduanya selesai
  /// sebelum UI dirender — mencegah stats & profile tampil di waktu berbeda.
  Future<void> _initProfileData() async {
    await Future.wait([
      _fetchProfileStats(),
      _fetchProfileData(),
    ]);
  }

  void _setupRealtimeSubscription() {
    _profilePostsSubscription = Supabase.instance.client
        .channel('public:posts_profile_${widget.userId ?? "me"}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            // ✅ FIX P6: Gunakan _initProfileData agar konsisten
            _initProfileData();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _profilePostsSubscription?.unsubscribe();
    _barsController.dispose();
    _streakPulseController.dispose();
    _avatarGlowController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: AppColors.surfaceElevated,
              edgeOffset: MediaQuery.of(context).padding.top + kToolbarHeight,
              onRefresh: () async {
                // ✅ FIX P6: Refresh juga menggunakan Future.wait
                await Future.wait([
                  _fetchProfileStats(),
                  _fetchProfileData(),
                ]);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                slivers: [
                  // ── 1. AppBar ────────────────────────────────────────────────────
                  _buildAppBar(),

                  // ── 2. Profile header ────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: _ProfileHeader(
                      momentsKey: momentsKey,
                      impactKey: impactKey,
                      glowController: _avatarGlowController,
                      displayName: _displayName,
                      username: _username,
                      bio: _bio,
                      location: _location,
                      education: _education,
                      work: _work,
                      astrologicalSign: _astrologicalSign,
                      totalFriends: totalFriends,
                      totalFollowers: totalFollowers,
                      totalFollowing: totalFollowing,
                      avatarUrl: _avatarUrl,
                      isUploadingAvatar: _isUploadingAvatar,
                      onAvatarTap: isMe ? _showAvatarOptionsBottomSheet : () {},
                      isMe: isMe,
                      connectionStatus: connectionStatus,
                      onAddFriendPressed: () async {
                        final user = Supabase.instance.client.auth.currentUser;
                        if (user != null && widget.userId != null) {
                          try {
                            // ✅ P2 FIX: Cek apakah target sudah ngirim request ke kita duluan
                            final existing = await Supabase.instance.client
                                .from('connections')
                                .select('id, status')
                                .or('and(sender_id.eq.${user.id},receiver_id.eq.${widget.userId}),and(sender_id.eq.${widget.userId},receiver_id.eq.${user.id})')
                                .maybeSingle();

                            if (existing != null) {
                              if (existing['status'] == 'requested') {
                                // Target sudah ngirim, langsung accept aja
                                await Supabase.instance.client
                                    .from('connections')
                                    .update({'status': 'friends'})
                                    .eq('id', existing['id']);
                                if (!context.mounted) return;
                                setState(() => connectionStatus = 'friends');
                                return;
                              } else {
                                // Sudah friends atau status lain
                                if (!context.mounted) return;
                                setState(() => connectionStatus = existing['status']?.toString() ?? 'requested');
                                return;
                              }
                            }

                            // Belum ada koneksi sama sekali, buat baru
                            await Supabase.instance.client.from('connections').insert({
                              'sender_id': user.id,
                              'receiver_id': widget.userId,
                              'status': 'requested',
                            });
                            if (!context.mounted) return;
                            setState(() => connectionStatus = 'requested');
                            // Chat tersedia via tombol di sebelah Pending — tidak auto-navigate
                          } catch (e) {
                            debugPrint('[ProfilePage] onAddFriendPressed error: $e');
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
                          }
                        }
                      },
                      onUnfriendPressed: () async {
                        final user = Supabase.instance.client.auth.currentUser;
                        if (user != null && widget.userId != null) {
                          try {
                            await Supabase.instance.client
                                .from('connections')
                                .delete()
                                .or('and(sender_id.eq.${user.id},receiver_id.eq.${widget.userId}),and(sender_id.eq.${widget.userId},receiver_id.eq.${user.id})');
                            if (!context.mounted) return;
                            setState(() => connectionStatus = 'none');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
                          }
                        }
                      },
                      onCancelRequestPressed: () async {
                        final user = Supabase.instance.client.auth.currentUser;
                        if (user != null && widget.userId != null) {
                          try {
                            await Supabase.instance.client
                                .from('connections')
                                .delete()
                                .eq('sender_id', user.id)
                                .eq('receiver_id', widget.userId!)
                                .eq('status', 'requested');
                            if (!context.mounted) return;
                            setState(() => connectionStatus = 'none');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
                          }
                        }
                      },
                      onMessagePressed: () {
                        if (widget.userId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatRoomPage(
                                friendId: widget.userId!,
                                friendName: _displayName,
                                friendUsername: _username.replaceAll('@', ''),
                                friendAvatar: _avatarUrl ?? '',
                                triggerIcebreaker: true, // ← Trigger otomatis hanya dari Profile
                              ),
                            ),
                          );
                        }
                      },
                      onRequestedChatPressed: () {
                        if (widget.userId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatRoomPage(
                                friendId: widget.userId!,
                                friendName: _displayName,
                                friendUsername: _username.replaceAll('@', ''),
                                friendAvatar: _avatarUrl ?? '',
                                initialText: 'Hei! Aku baru aja add kamu sebagai teman di SyncReal 👋',
                                triggerIcebreaker: true, // ← Trigger otomatis (akan prioritaskan hobi, lalu fallback initialText)
                              ),
                            ),
                          );
                        }
                      },
                      onEditPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const EditProfilePage()),
                        );
                        if (result == true && mounted) {
                          setState(() => _isLoading = true);
                          _fetchProfileStats();
                          _fetchProfileData();
                        }
                      },
                      onConnectionsTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ConnectionsPage(
                              profileName: _username,
                              userId: widget.userId ?? Supabase.instance.client.auth.currentUser!.id,
                            ),
                          ),
                        ).then((_) {
                          if (mounted) _initProfileData();
                        });
                      },
                    ),
                  ),

                  _gap(24),

                  // ── 3. Impact dashboard ──────────────────────────────────────────
                  if (isMe)
                    SliverToBoxAdapter(
                      key: impactKey,
                      child: _ImpactSection(
                        streakDays: dayStreak,
                        syncRate: '${syncRate.toStringAsFixed(1)}%',
                        topHobby: topHobby.toUpperCase(),
                        weeklyBars: _dynamicWeeklyBars,
                        barsController: _barsController,
                        streakPulseController: _streakPulseController,
                      ),
                    )
                  else if (!isMe)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionLabel(
                              label: 'IMPACT STREAK',
                              icon: LucideIcons.flame,
                              accentColor: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 14),
                            _StreakCard(
                              days: dayStreak,
                              pulseController: _streakPulseController,
                            ),
                          ],
                        ),
                      ),
                    ),

                  _gap(24),

                  // ── 4. Hobbies ───────────────────────────────────────────────────
                  if (isMe || connectionStatus == 'friends' || !_isPrivateProfile)
                    SliverToBoxAdapter(
                      child: _HobbiesSection(hobbies: _hobbies, isMe: isMe),
                    ),

                  _gap(24),

                  // ── 5. My Moments (SliverGrid — makes page scrollable) ───────────
                  _MomentsSection.header(key: momentsKey),

                  if (!isMe && connectionStatus != 'friends' && _isPrivateProfile && _userPosts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        child: NeonCard(
                          accentColor: AppColors.textDisabled,
                          padding: const EdgeInsets.all(12),
                          borderOpacity: 0.3,
                          glowOpacity: 0.05,
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline_rounded, color: AppColors.textDisabled, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This account is private. You are only seeing public moments.',
                                  style: AppTheme.inter(
                                    fontSize: 12,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (!isMe && connectionStatus != 'friends' && _isPrivateProfile && _userPosts.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                        child: NeonCard(
                          accentColor: Theme.of(context).colorScheme.primary,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                'ACCOUNT IS PRIVATE',
                                style: AppTheme.orbitron(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_userPosts.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: Text(
                            'NO MOMENTS DETECTED\nIN THE VOID',
                            style: AppTheme.orbitron(
                              fontSize: 14,
                              color: AppColors.textDisabled.withValues(alpha: 0.5),
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    _MomentsSection.grid(
                      posts: _userPosts,
                      // ✅ P1 FIX: isLocked = true jika profil orang lain DAN kamu belum posting.
                      // Aturan: Jika kamu sudah posting, semua post profil orang otomatis terbuka.
                      isLocked: !isMe && !_myHasPostedToday,
                    ),

                  // ── 6. Bottom padding ────────────────────────────────────────────
                  _gap(80),
                ],
              ),
            ),
    );
  }

  SliverToBoxAdapter _gap(double h) =>
      SliverToBoxAdapter(child: SizedBox(height: h));

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.black,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'PROFILE',
        style: AppTheme.orbitron(
            fontSize: 13, color: AppColors.textPrimary, letterSpacing: 4),
      ),
      actions: [
        if (isMe) ...[
          // ① Calendar → MemoriesPage (Archive)
          IconButton(
            tooltip: 'Memories',
            icon: LucideIcon(
              icon: LucideIcons.calendarDays,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              final targetId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
              if (targetId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MemoriesPage(userId: targetId),
                  ),
                );
              }
            },
          ),
          // ③ Settings
          IconButton(
            tooltip: 'Settings',
            icon: const LucideIcon(icon: LucideIcons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            padding: const EdgeInsets.only(right: 4),
          ),
        ],
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProfileHeader
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.momentsKey,
    required this.impactKey,
    required this.glowController,
    required this.displayName,
    required this.username,
    required this.bio,
    required this.location,
    required this.education,
    required this.work,
    this.astrologicalSign,
    required this.totalFriends,
    required this.totalFollowers,
    required this.totalFollowing,
    this.avatarUrl,
    required this.isUploadingAvatar,
    required this.onAvatarTap,
    required this.onEditPressed,
    required this.onConnectionsTap,
    required this.isMe,
    required this.connectionStatus,
    required this.onAddFriendPressed,
    required this.onUnfriendPressed,
    required this.onCancelRequestPressed,
    required this.onMessagePressed,
    required this.onRequestedChatPressed,
  });

  final GlobalKey momentsKey;
  final GlobalKey impactKey;
  final AnimationController glowController;
  final String displayName;
  final String username;
  final String bio;
  final String location;
  final String education;
  final String work;
  final String? astrologicalSign;
  final int totalFriends;
  final int totalFollowers;
  final int totalFollowing;
  final String? avatarUrl;
  final bool isUploadingAvatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditPressed;
  final VoidCallback onConnectionsTap;
  final bool isMe;
  final String connectionStatus;
  final VoidCallback onAddFriendPressed;
  final VoidCallback onUnfriendPressed;
  final VoidCallback onCancelRequestPressed;
  final VoidCallback onMessagePressed;
  final VoidCallback onRequestedChatPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + name ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _GlowingAvatar(
                        controller: glowController, avatarUrl: avatarUrl),
                    if (isUploadingAvatar)
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppColors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: AppTheme.orbitron(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      username,
                      style: AppTheme.inter(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // ↓ Profile action buttons
                    if (isMe)
                      Row(
                        children: [
                          // Share Profile — wide expanded button
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final user = Supabase.instance.client.auth.currentUser;
                                if (user != null) {
                                  SharePlus.instance.share(
                                    ShareParams(text: "Let's connect on SyncReal! Add me: [AppURL]/user/${user.id}"),
                                  );
                                }
                              },
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.ios_share_rounded,
                                      color: AppColors.textSecondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'SHARE PROFILE',
                                      style: AppTheme.orbitron(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Edit Profile — small square icon button
                          GestureDetector(
                            onTap: onEditPressed,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.edit_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (connectionStatus == 'friends')
                      Row(
                        children: [
                          Expanded(
                            child: NeonOutlineButton(
                              label: 'FRIENDS',
                              icon: LucideIcons.check,
                              color: AppColors.textDisabled,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: AppColors.surfaceCard,
                                    title: Text('Unfriend this user?', style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('Cancel', style: AppTheme.inter(color: AppColors.textDisabled)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          onUnfriendPressed();
                                        },
                                        child: Text('Unfriend', style: AppTheme.inter(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Message — small square icon button
                          GestureDetector(
                            onTap: onMessagePressed,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 2.0, top: 2.0),
                                  child: LucideIcon(
                                    icon: LucideIcons.send,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (connectionStatus == 'requested')
                      // ✅ Status 'requested': tampilkan [Pending] + [💬 Chat] berdampingan
                      Row(
                        children: [
                          Expanded(
                            child: NeonOutlineButton(
                              label: 'REQUESTED',
                              icon: LucideIcons.timer,
                              color: AppColors.textDisabled,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: AppColors.surfaceCard,
                                    title: Text('Cancel friend request?', style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('No', style: AppTheme.inter(color: AppColors.textDisabled)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          onCancelRequestPressed();
                                        },
                                        child: Text('Cancel Request', style: AppTheme.inter(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          // ── Chat icon button (tersedia saat masih pending) ──
                          GestureDetector(
                            onTap: onRequestedChatPressed,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 2.0, top: 2.0),
                                  child: LucideIcon(
                                    icon: LucideIcons.send,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      NeonOutlineButton(
                        label: 'ADD FRIEND',
                        icon: LucideIcons.plus,
                        onTap: onAddFriendPressed,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── Bio ──
          Text(
            bio,
            style: AppTheme.inter(
                fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),

          // ── Rich Metadata Row ──
          if (location.isNotEmpty || education.isNotEmpty || work.isNotEmpty || (astrologicalSign != null && astrologicalSign!.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (location.isNotEmpty)
                  _MetaChip(icon: '📍', text: location),
                if (education.isNotEmpty)
                  _MetaChip(icon: '🎓', text: education),
                if (work.isNotEmpty)
                  _MetaChip(icon: '💻', text: work),
                if (astrologicalSign != null && astrologicalSign!.isNotEmpty)
                  _MetaChip(icon: '🌙', text: astrologicalSign!),
              ],
            ),
          ],

          const SizedBox(height: 14),

          // ── Stats text line ──
          GestureDetector(
            onTap: onConnectionsTap,
            child: RichText(
              text: TextSpan(
                style: AppTheme.inter(fontSize: 13, color: AppColors.textDisabled),
                children: [
                  TextSpan(
                    text: '$totalFriends',
                    style: AppTheme.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' friends  ·  '),
                  TextSpan(
                    text: '$totalFollowers',
                    style: AppTheme.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' followers  ·  '),
                  TextSpan(
                    text: '$totalFollowing',
                    style: AppTheme.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' following'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MetaChip — small pill with emoji icon for rich profile metadata
// ─────────────────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Text(
            text,
            style: AppTheme.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlowingAvatar
// ─────────────────────────────────────────────────────────────────────────────

class _GlowingAvatar extends StatelessWidget {
  const _GlowingAvatar({required this.controller, this.avatarUrl});
  final AnimationController controller;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(controller.value);
        return Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30 + 0.30 * t),
                blurRadius: 16 + 16 * t,
                spreadRadius: 1 + 3 * t,
              ),
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                blurRadius: 40,
                spreadRadius: 6,
              ),
            ],
          ),
          child: ClipOval(
            child: Container(
              color: AppColors.surfaceCard,
              alignment: Alignment.center,
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover, width: 90, height: 90,
                      placeholder: (context, url) => Icon(Icons.person_rounded, size: 44, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                      errorWidget: (context, url, error) => Icon(Icons.person_rounded, size: 44, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                    )
                  : Icon(Icons.person_rounded,
                      size: 44, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ImpactSection
// ─────────────────────────────────────────────────────────────────────────────

class _ImpactSection extends StatelessWidget {
  const _ImpactSection({
    required this.streakDays,
    required this.syncRate,
    required this.topHobby,
    required this.weeklyBars,
    required this.barsController,
    required this.streakPulseController,
  });

  final int streakDays;
  final String syncRate;
  final String topHobby;
  final List<_BarData> weeklyBars;
  final AnimationController barsController;
  final AnimationController streakPulseController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──
          SectionLabel(
            label: 'YOUR IMPACT',
            icon: LucideIcons.barChart2,
            accentColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),

          // ── Streak + KPIs side by side ──
          // IntrinsicHeight forces both columns to the same height,
          // eliminating the overflow/overlap that appeared in the screenshot.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: streak card
                Expanded(
                  child: _StreakCard(
                    days: streakDays,
                    pulseController: streakPulseController,
                  ),
                ),
                const SizedBox(width: 12),
                // Right: two stacked KPI tiles
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _MiniMetricCard(
                          label: 'SYNC RATE',
                          value: syncRate,
                          icon: LucideIcons.zap,
                          color: AppColors.neonCyan,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _MiniMetricCard(
                          label: 'TOP HOBBY',
                          value: topHobby,
                          icon: LucideIcons.trophy,
                          color: AppColors.neonGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Bar chart ──
          _WeeklyBarChart(bars: weeklyBars, controller: barsController),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StreakCard   — uses NeonCard from neon_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.days, required this.pulseController});
  final int days;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final pulse = Curves.easeInOut.transform(pulseController.value);
        // We use NeonCard but animate the border/glow via a raw Container
        // so we can interpolate the border colour each frame.
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), Theme.of(context).colorScheme.primary, pulse)!,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10 + 0.15 * pulse),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flame icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.25 + 0.25 * pulse),
                      blurRadius: 12 + 8 * pulse,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: LucideIcon(
                    icon: LucideIcons.flame,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22),
              ),
              const SizedBox(height: 14),
              Text(
                '$days',
                style: AppTheme.orbitron(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0),
              ),
              Text(
                'DAY STREAK',
                style: AppTheme.orbitron(
                    fontSize: 8,
                    color: AppColors.textSecondary,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 10),
              // Weekly progress dots
              Row(
                children: List.generate(7, (i) {
                  final filled = i < (days % 7 == 0 ? 7 : days % 7);
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            filled ? Theme.of(context).colorScheme.primary : AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: filled
                            ? [
                                BoxShadow(
                                    color:
                                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                    blurRadius: 4)
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MiniMetricCard   — uses NeonCard from neon_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────

class _MiniMetricCard extends StatelessWidget {
  const _MiniMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final LucideIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      accentColor: color,
      borderOpacity: 0.30,
      glowOpacity: 0.06,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 12,
      child: Row(
        children: [
          LucideIcon(icon: icon, color: color, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: AppTheme.orbitron(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1),
              ),
              Text(
                label,
                style: AppTheme.orbitron(
                    fontSize: 7,
                    color: AppColors.textDisabled,
                    letterSpacing: 1.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WeeklyBarChart
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.bars, required this.controller});
  final List<_BarData> bars;
  final AnimationController controller;

  String get _todayLabel {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEEKLY INTERACTIONS',
                style: AppTheme.orbitron(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                    letterSpacing: 2),
              ),
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                  ),
                ),
                const SizedBox(width: 6),
                Text('THIS WEEK',
                    style: AppTheme.orbitron(
                        fontSize: 7,
                        color: AppColors.textDisabled,
                        letterSpacing: 1.5)),
              ]),
            ],
          ),
          const SizedBox(height: 18),
          // Animated bars
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final progress = Curves.easeOutCubic.transform(controller.value);
              final maxVal =
                  bars.fold(0.0, (max, bar) => math.max(max, bar.value));
              final scale = maxVal > 0 ? 80.0 / maxVal : 0.0;

              return SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: bars.map((bar) {
                    final isToday = bar.day == _todayLabel;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: double.infinity,
                              height: bar.value * scale * progress,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: isToday
                                      ? [
                                          Theme.of(context).colorScheme.primary,
                                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.60)
                                        ]
                                      : [
                                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                                              .withValues(alpha: 0.60),
                                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                                              .withValues(alpha: 0.25)
                                        ],
                                ),
                                boxShadow: isToday
                                    ? [
                                        BoxShadow(
                                            color: Theme.of(context).colorScheme.primary
                                                .withValues(alpha: 0.55),
                                            blurRadius: 12,
                                            offset: const Offset(0, -2))
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bar.day,
                              style: AppTheme.orbitron(
                                fontSize: 7,
                                color: isToday
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.textDisabled,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HobbiesSection
// ─────────────────────────────────────────────────────────────────────────────

class _HobbiesSection extends StatelessWidget {
  const _HobbiesSection({required this.hobbies, this.isMe = true});
  final List<_HobbyTag> hobbies;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            label: isMe ? 'MY HOBBIES' : 'HOBBIES',
            icon: LucideIcons.sparkles,
            accentColor: AppColors.neonCyan,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: hobbies
                .map((h) => NeonChip(label: h.label, color: h.color))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MomentsSection   — SliverGrid that makes the page scrollable
// ─────────────────────────────────────────────────────────────────────────────

/// Provides two static sliver factory methods so ProfilePage can insert
/// the header and grid directly into its sliver list without nesting.
class _MomentsSection {
  _MomentsSection._();

  /// The "MY MOMENTS" section label as a [SliverToBoxAdapter].
  static SliverToBoxAdapter header({Key? key}) {
    return SliverToBoxAdapter(
      key: key,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SectionLabel(
          label: 'MY MOMENTS',
          icon: LucideIcons.image,
          accentColor: AppColors.neonMagenta,
        ),
      ),
    );
  }

  /// 2-column grid of dynamic moment thumbnails.
  static SliverPadding grid({
    required List<Map<String, dynamic>> posts,
    bool isLocked = false, // ✅ P2: gembok semua tile jika salah satu belum posting
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _MomentTile(
            index: index,
            post: posts[index],
            isLocked: isLocked, // ✅ P2
          ),
          childCount: posts.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MomentTile   — individual moment thumbnail with swap-camera interaction
// ─────────────────────────────────────────────────────────────────────────────

class _MomentTile extends StatefulWidget {
  const _MomentTile({
    required this.index,
    required this.post,
    this.isLocked = false, // ✅ P2
  });
  final int index;
  final Map<String, dynamic> post;
  final bool isLocked; // ✅ P2: true = blur + gembok, false = tampil normal

  @override
  State<_MomentTile> createState() => _MomentTileState();
}

class _MomentTileState extends State<_MomentTile> {
  bool isSwapped = false;

  List<Color> get _accentCycle => [
    Theme.of(context).colorScheme.primary,
    AppColors.neonCyan,
    AppColors.neonGreen,
    AppColors.neonMagenta,
  ];

  Widget _netImg(String? url, String tag) {
    if (url == null || url.isEmpty) {
      return Container(
        key: ValueKey('empty_$tag'),
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.image_not_supported, color: AppColors.textDisabled),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      key: ValueKey('${tag}_$url'),
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(color: AppColors.surfaceElevated, child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2))),
      errorWidget: (context, url, error) => Container(
        key: ValueKey('err_$tag'),
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.broken_image, color: AppColors.textDisabled),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentCycle[widget.index % _accentCycle.length];
    final backUrl  = widget.post['back_video_url']?.toString();
    final frontUrl = widget.post['front_video_url']?.toString();

    final mainUrl = isSwapped ? frontUrl : backUrl;
    final pipUrl  = isSwapped ? backUrl  : frontUrl;

    return GestureDetector(
      // ✅ P2: Matikan navigasi ke Detail jika tile sedang digembok
      onTap: widget.isLocked
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailPage(
                    post: widget.post,
                  ),
                ),
              );
            },
      child: Container(
        decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background image (animated swap) ──
          ClipRRect(
            borderRadius: BorderRadius.circular(10.5),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: SizedBox.expand(
                child: _netImg(mainUrl, 'main'),
              ),
            ),
          ),

          // ── PiP thumbnail top-right — tap to swap ──
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.isLocked ? null : () => setState(() => isSwapped = !isSwapped),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey('pip_$isSwapped'),
                  width: 36,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.black,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: pipUrl != null && pipUrl.isNotEmpty
                      ? CachedNetworkImage(imageUrl: pipUrl, fit: BoxFit.cover, placeholder: (context, url) => const SizedBox.shrink(), errorWidget: (context, url, error) => const SizedBox.shrink())
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // ── Caption tag (bottom-left) ──
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: accent.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                '#SYNC${widget.index + 1}',
                style: AppTheme.orbitron(
                  fontSize: 7,
                  color: accent,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // ── P2: Blur + Gembok Overlay (tampil jika isLocked) ────────────────
          if (widget.isLocked)
            ClipRRect(
              borderRadius: BorderRadius.circular(10.5),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'POST TO VIEW',
                        style: AppTheme.orbitron(
                          fontSize: 7,
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // ─────────────────────────────────────────────────────────────────
        ],
      ),
    ));
  }
}








