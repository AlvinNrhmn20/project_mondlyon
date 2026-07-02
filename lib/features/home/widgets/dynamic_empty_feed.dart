// lib/features/home/widgets/dynamic_empty_feed.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/constants.dart';
import '../../../core/services/sync_timer_controller.dart';
import '../../profile/profile_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DynamicEmptyFeed
// ─────────────────────────────────────────────────────────────────────────────

class DynamicEmptyFeed extends ConsumerStatefulWidget {
  final bool hasNeverPosted;
  final String username;
  final VoidCallback onPostAction;

  const DynamicEmptyFeed({
    super.key,
    required this.hasNeverPosted,
    required this.username,
    required this.onPostAction,
  });

  @override
  ConsumerState<DynamicEmptyFeed> createState() => _DynamicEmptyFeedState();
}

class _DynamicEmptyFeedState extends ConsumerState<DynamicEmptyFeed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  List<_SuggestionUser> _suggestions = [];
  bool _loadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    if (!widget.hasNeverPosted) _fetchSuggestions();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestions() async {
    if (_loadingSuggestions) return;
    setState(() => _loadingSuggestions = true);
    try {
      final supabase = Supabase.instance.client;
      final myId = supabase.auth.currentUser!.id;

      // Ambil daftar teman (exclude dari suggestion)
      final c1 = await supabase
          .from('connections')
          .select('receiver_id')
          .eq('sender_id', myId)
          .eq('status', 'friends');
      final c2 = await supabase
          .from('connections')
          .select('sender_id')
          .eq('receiver_id', myId)
          .eq('status', 'friends');

      final Set<String> friendIds = {myId};
      for (var r in c1) { friendIds.add(r['receiver_id'] as String); }
      for (var r in c2) { friendIds.add(r['sender_id'] as String); }

      // Ambil hobi saya
      final myHobbiesRaw = await supabase
          .from('user_hobbies')
          .select('hobby_id')
          .eq('user_id', myId);
      final Set<String> myHobbies =
          (myHobbiesRaw as List).map((e) => e['hobby_id'].toString()).toSet();

      // Ambil kandidat profiles (exclude friends)
      final profilesRaw = await supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .limit(30);

      final List<Map<String, dynamic>> candidates = (profilesRaw as List)
          .where((p) => !friendIds.contains(p['id']))
          .cast<Map<String, dynamic>>()
          .toList();

      // Untuk setiap kandidat: hitung mutual friends & shared hobbies
      final List<_SuggestionUser> result = [];
      for (final p in candidates.take(10)) {
        final uid = p['id'] as String;

        // Shared hobbies
        final hobbyRaw = await supabase
            .from('user_hobbies')
            .select('hobby_id')
            .eq('user_id', uid);
        final theirHobbies =
            (hobbyRaw as List).map((e) => e['hobby_id'].toString()).toSet();
        final sharedHobbies = myHobbies.intersection(theirHobbies).length;

        // Mutual friends: teman saya yang juga teman kandidat
        final mutualFriendIds = <String>{};
        for (final fid in friendIds.where((id) => id != myId)) {
          final mCheck = await supabase
              .from('connections')
              .select('id')
              .or('and(sender_id.eq.$fid,receiver_id.eq.$uid),and(sender_id.eq.$uid,receiver_id.eq.$fid)')
              .eq('status', 'friends')
              .maybeSingle();
          if (mCheck != null) mutualFriendIds.add(fid);
        }

        result.add(_SuggestionUser(
          id: uid,
          username: p['username']?.toString() ?? 'unknown',
          avatarUrl: p['avatar_url']?.toString(),
          mutualFriends: mutualFriendIds.length,
          sharedHobbies: sharedHobbies,
          connectionStatus: 'none',
        ));
      }

      // Sort: mutual friends dulu, lalu shared hobbies
      result.sort((a, b) {
        final score = (b.mutualFriends * 2 + b.sharedHobbies)
            .compareTo(a.mutualFriends * 2 + a.sharedHobbies);
        return score;
      });

      if (mounted) {
        setState(() {
          _suggestions = result.take(8).toList();
          _loadingSuggestions = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _sendFriendRequest(String targetId, int index) async {
    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;
      // ✅ P1-B FIX: .upsert() mencegah Unique Constraint violation
      // saat user re-request setelah cancel sebelumnya.
      await Supabase.instance.client.from('connections').upsert({
        'sender_id': myId,
        'receiver_id': targetId,
        'status': 'requested',
      }, onConflict: 'sender_id,receiver_id');
      if (mounted) {
        setState(() => _suggestions[index] =
            _suggestions[index].copyWith(connectionStatus: 'requested'));
      }
    } catch (e) {
      // ✅ P1-C FIX: Ganti catch kosong dengan logging + feedback ke user.
      debugPrint('[DynamicEmptyFeed] _sendFriendRequest error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengirim permintaan. Coba lagi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;
    final timerState = ref.watch(syncTimerProvider);
    final canPost = timerState.status == SyncWindowStatus.ready ||
        timerState.status == SyncWindowStatus.active;

    return widget.hasNeverPosted
        ? _ScenarioA(
            neon: neon,
            glowCtrl: _glowCtrl,
            username: widget.username,
            onPost: widget.onPostAction,
          )
        : _ScenarioB(
            neon: neon,
            glowCtrl: _glowCtrl,
            canPost: canPost,
            onPost: widget.onPostAction,
            suggestions: _suggestions,
            loadingSuggestions: _loadingSuggestions,
            onAddFriend: _sendFriendRequest,
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario A — Brand New User
// ─────────────────────────────────────────────────────────────────────────────

class _ScenarioA extends StatelessWidget {
  const _ScenarioA({
    required this.neon,
    required this.glowCtrl,
    required this.username,
    required this.onPost,
  });

  final Color neon;
  final AnimationController glowCtrl;
  final String username;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Glow radial background ──
          AnimatedBuilder(
            animation: glowCtrl,
            builder: (_, __) {
              final t = Curves.easeInOut.transform(glowCtrl.value);
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      neon.withValues(alpha: 0.08 + 0.06 * t),
                      AppColors.black,
                    ],
                  ),
                ),
              );
            },
          ),

          // ── Glassmorphism card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
                  decoration: BoxDecoration(
                    color: neon.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: neon.withValues(alpha: 0.25), width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Neon orb
                      AnimatedBuilder(
                        animation: glowCtrl,
                        builder: (_, __) {
                          final t = Curves.easeInOut.transform(glowCtrl.value);
                          return Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: neon.withValues(alpha: 0.12),
                              border: Border.all(
                                  color: neon.withValues(alpha: 0.6 + 0.4 * t),
                                  width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: neon.withValues(alpha: 0.35 + 0.25 * t),
                                  blurRadius: 28 + 14 * t,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(Icons.bolt_rounded, color: neon, size: 36),
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Headline
                      Text(
                        'HEY ${username.toUpperCase()},',
                        style: AppTheme.orbitron(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),

                      // Subtitle
                      Text(
                        'Are you ready? It\'s time to SyncReal.\nSave this moment and share it with your friends.',
                        style: AppTheme.inter(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.7,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // CTA button
                      GestureDetector(
                        onTap: onPost,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                neon.withValues(alpha: 0.9),
                                neon.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: neon.withValues(alpha: 0.45),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'POST YOUR FIRST SYNCREAL',
                            style: AppTheme.orbitron(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario B — Returning User, Feed Empty
// ─────────────────────────────────────────────────────────────────────────────

class _ScenarioB extends StatelessWidget {
  const _ScenarioB({
    required this.neon,
    required this.glowCtrl,
    required this.canPost,
    required this.onPost,
    required this.suggestions,
    required this.loadingSuggestions,
    required this.onAddFriend,
  });

  final Color neon;
  final AnimationController glowCtrl;
  final bool canPost;
  final VoidCallback onPost;
  final List<_SuggestionUser> suggestions;
  final bool loadingSuggestions;
  final void Function(String id, int index) onAddFriend;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Hero message ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 48, 28, 0),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: glowCtrl,
                  builder: (_, __) {
                    final t = Curves.easeInOut.transform(glowCtrl.value);
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: neon.withValues(alpha: 0.08),
                        border: Border.all(
                            color: neon.withValues(alpha: 0.4 + 0.3 * t),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: neon.withValues(alpha: 0.20 + 0.15 * t),
                            blurRadius: 20 + 10 * t,
                          ),
                        ],
                      ),
                      child: Icon(Icons.nights_stay_rounded,
                          color: neon, size: 30),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Wow, it\'s really calm in here!',
                  style: AppTheme.orbitron(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your friends haven\'t posted their\nSyncReal yet. Be the first one.',
                  style: AppTheme.inter(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (canPost) ...[
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: onPost,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: neon.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: neon.withValues(alpha: 0.55), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: neon.withValues(alpha: 0.25),
                              blurRadius: 18),
                        ],
                      ),
                      child: Text(
                        'TAKE YOUR SYNCREAL',
                        style: AppTheme.orbitron(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: neon,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),

        // ── Divider + title ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                        color: neon,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                              color: neon.withValues(alpha: 0.6), blurRadius: 6)
                        ])),
                const SizedBox(width: 10),
                Text(
                  'SUGGESTIONS FOR YOU',
                  style: AppTheme.orbitron(
                    fontSize: 10,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Horizontal suggestions list ─────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: 180,
            child: loadingSuggestions
                ? Center(
                    child: CircularProgressIndicator(
                        color: neon, strokeWidth: 2))
                : suggestions.isEmpty
                    ? Center(
                        child: Text(
                          'No suggestions yet.',
                          style: AppTheme.inter(
                              color: AppColors.textDisabled, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, i) => _SuggestionCard(
                          user: suggestions[i],
                          neon: neon,
                          onAdd: () => onAddFriend(suggestions[i].id, i),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfilePage(userId: suggestions[i].id),
                            ),
                          ),
                        ),
                      ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SuggestionCard
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.user,
    required this.neon,
    required this.onAdd,
    required this.onTap,
  });

  final _SuggestionUser user;
  final Color neon;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  String get _subtext {
    if (user.mutualFriends > 0 && user.sharedHobbies > 0) {
      return '${user.mutualFriends} mutual · ${user.sharedHobbies} hobbies';
    } else if (user.mutualFriends > 0) {
      return '${user.mutualFriends} mutual friend${user.mutualFriends > 1 ? 's' : ''}';
    } else if (user.sharedHobbies > 0) {
      return 'Shares ${user.sharedHobbies} hobb${user.sharedHobbies > 1 ? 'ies' : 'y'}';
    }
    return 'Suggested for you';
  }

  @override
  Widget build(BuildContext context) {
    final isRequested = user.connectionStatus == 'requested';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: neon.withValues(alpha: 0.20), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: neon.withValues(alpha: 0.06),
                blurRadius: 14,
                spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.surfaceElevated,
              backgroundImage: (user.avatarUrl != null &&
                      user.avatarUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                  ? Icon(Icons.person_rounded,
                      size: 28, color: neon.withValues(alpha: 0.5))
                  : null,
            ),
            const SizedBox(height: 10),

            // Username
            Text(
              '@${user.username}',
              style: AppTheme.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // Sub-text
            Text(
              _subtext,
              style: AppTheme.inter(
                fontSize: 9,
                color: AppColors.textDisabled,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // ADD button
            GestureDetector(
              onTap: isRequested ? null : onAdd,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isRequested
                      ? AppColors.surfaceElevated
                      : neon.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isRequested
                        ? AppColors.divider
                        : neon.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Text(
                  isRequested ? 'SENT' : 'ADD',
                  style: AppTheme.orbitron(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: isRequested ? AppColors.textDisabled : neon,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final int mutualFriends;
  final int sharedHobbies;
  final String connectionStatus;

  const _SuggestionUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.mutualFriends,
    required this.sharedHobbies,
    required this.connectionStatus,
  });

  _SuggestionUser copyWith({String? connectionStatus}) => _SuggestionUser(
        id: id,
        username: username,
        avatarUrl: avatarUrl,
        mutualFriends: mutualFriends,
        sharedHobbies: sharedHobbies,
        connectionStatus: connectionStatus ?? this.connectionStatus,
      );
}
