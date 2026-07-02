// lib/features/search/search_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';
import '../profile/profile_page.dart';
import '../message/chat_room_page.dart';
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // ─── Supabase ─────────────────────────────────────────────────────────────
  final _supabase = Supabase.instance.client;

  // ─── State ────────────────────────────────────────────────────────────────
  String searchQuery = '';
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> suggestedUsers = [];
  bool isLoading = false;
  List<String> selectedHobbies = [];

  /// allHobbies holds entries with 'label' (String from DB) and 'icon' (IconData local).
  List<Map<String, dynamic>> allHobbies = [];

  /// Cached current user ID.
  late final String myId;

  /// IDs currently in the process of being added (anti-spam & loading state).
  final Set<String> sendingRequestTo = {};

  /// Map hobby label → icon — keys must exactly match 'name' column in hobbies table.
  static const Map<String, IconData> _hobbyIconMap = {
    'Coding': Icons.code_rounded,
    'Gaming': Icons.sports_esports_rounded,
    'Crypto': Icons.currency_bitcoin,
    'Skateboarding': Icons.directions_run_rounded,
    'Photography': Icons.camera_alt_outlined,
    'Music': Icons.music_note_rounded,
    'Design': Icons.brush_rounded,
    'Content Creation': Icons.video_call_rounded,
    'Video Editing': Icons.video_camera_back_outlined,
    'Stock Trading': Icons.show_chart_rounded,
    'Anime / Manga': Icons.auto_stories_rounded,
    'Cafe Hopping': Icons.local_cafe_rounded,
    'Thrifting': Icons.shopping_bag_rounded,
    'Movies & Series': Icons.movie_rounded,
    'Fitness / Gym': Icons.fitness_center_rounded,
    'Traveling': Icons.flight_rounded,
    'Futsal': Icons.sports_soccer_rounded,
    'Strategy Games': Icons.extension_rounded,
  };

  final TextEditingController _searchController = TextEditingController();

  // Debounce timer so we don't hammer Supabase on every keystroke
  Timer? _debounce;

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    myId = _supabase.auth.currentUser!.id;
    _fetchInitialData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Fetch Initial Data ───────────────────────────────────────────────────
  Future<void> _fetchInitialData() async {
    try {
      final response = await _supabase.from('hobbies').select('*');
      
      if (!mounted) return;

      final hobbiesData = response as List<dynamic>;
      final List<Map<String, dynamic>> fetchedHobbies = hobbiesData
          .map((row) {
            final name = row['name'] as String? ?? '';
            final idStr = row['id'].toString();
            return {
              'id': idStr,
              'name': name,
              'label': name,
              'icon': _hobbyIconMap[name] ?? Icons.tag_rounded,
            };
          })
          .where((h) => (h['label'] as String).isNotEmpty)
          .toList();

      setState(() {
        allHobbies = fetchedHobbies.isNotEmpty ? fetchedHobbies : _buildFallbackHobbies();
      });

      _performSearch();
    } catch (e) {
      debugPrint('[SearchPage] _fetchInitialData error: $e');
      if (!mounted) return;
      setState(() => allHobbies = _buildFallbackHobbies());
      _performSearch();
    }
  }

  List<Map<String, dynamic>> _buildFallbackHobbies() => _hobbyIconMap.entries
      .map((e) => {
            'id': e.key,
            'name': e.key,
            'label': e.key,
            'icon': e.value
          })
      .toList();

  // ─── Main Search & Filter Logic ───────────────────────────────────────────
  Future<void> _performSearch() async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => isLoading = true);

      try {
        final List<dynamic> response = await _supabase.rpc(
          'search_and_suggest_users',
          params: {
            'p_my_id': myId,
            'p_search_text': searchQuery,
            'p_hobby_filter': selectedHobbies,
          },
        );
        
        if (!mounted) return;

        final List<Map<String, dynamic>> results = List<Map<String, dynamic>>.from(response);

        setState(() {
          if (searchQuery.isEmpty && selectedHobbies.isEmpty) {
            suggestedUsers = results;
            searchResults = [];
          } else {
            searchResults = results;
            suggestedUsers = [];
          }
          isLoading = false;
        });
      } catch (e) {
        debugPrint('[SearchPage] _performSearch error: $e');
        if (mounted) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.surfaceCard,
            ),
          );
        }
      }
    });
  }

  // ─── Friend Request Logic ────────────────────────────────────────────────
  Future<void> _sendFriendRequest(String targetUserId) async {
    // 1. Anti-spam check
    if (sendingRequestTo.contains(targetUserId)) return;

    setState(() => sendingRequestTo.add(targetUserId));

    try {
      // ✅ P1-A FIX: .upsert() mencegah Unique Constraint violation
      // saat user re-request setelah cancel sebelumnya.
      await _supabase.from('connections').upsert({
        'sender_id': myId,
        'receiver_id': targetUserId,
        'status': 'requested',
      }, onConflict: 'sender_id,receiver_id');

      // 3. Optimistic UI Update: Masukkan ke list lokal agar UI berubah seketika
      if (mounted) {
        setState(() {
          sendingRequestTo.remove(targetUserId);
          for (var u in suggestedUsers) {
            if (u['id'] == targetUserId) u['connection_status'] = 'requested';
          }
          for (var u in searchResults) {
            if (u['id'] == targetUserId) u['connection_status'] = 'requested';
          }
        });
      }
    } catch (e) {
      debugPrint('[SearchPage] _sendFriendRequest error: $e');
      if (mounted) {
        setState(() => sendingRequestTo.remove(targetUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim permintaan: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ─── Bottom Sheet ─────────────────────────────────────────────────────────
  void _showHobbiesFilterBottomSheet(BuildContext context) {
    List<String> tempSelected = List.from(selectedHobbies);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), width: 1.2),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Drag Handle ──
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),

                  // ── Title Row ──
                  Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: Theme.of(context).colorScheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Filter by Hobbies',
                        style: AppTheme.orbitron(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      if (tempSelected.isNotEmpty)
                        GestureDetector(
                          onTap: () =>
                              setModalState(() => tempSelected.clear()),
                          child: Text(
                            'CLEAR',
                            style: AppTheme.orbitron(
                              fontSize: 9,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Chips (from DB or fallback) ──
                  allHobbies.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                            strokeWidth: 2,
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allHobbies.map((hobby) {
                            final label = hobby['label'] as String;
                            final isSelected = tempSelected.contains(label);
                            return FilterChip(
                              label: Text(
                                label,
                                style: AppTheme.inter(
                                  fontSize: 12,
                                  color: isSelected
                                      ? AppColors.black
                                      : AppColors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (val) {
                                setModalState(() {
                                  if (val) {
                                    tempSelected.add(label);
                                  } else {
                                    tempSelected.remove(label);
                                  }
                                });
                              },
                              selectedColor: Theme.of(context).colorScheme.primary,
                              backgroundColor: AppColors.surfaceElevated,
                              checkmarkColor: AppColors.black,
                              side: BorderSide(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.divider,
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              showCheckmark: false,
                              avatar: Icon(
                                hobby['icon'] as IconData,
                                size: 14,
                                color: isSelected
                                    ? AppColors.black
                                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            );
                          }).toList(),
                        ),

                  const SizedBox(height: 24),

                  // ── Apply Button ──
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(
                            () => selectedHobbies = List.from(tempSelected));
                        Navigator.pop(context);
                        // Trigger real search with new filters
                        _performSearch();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: AppColors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'APPLY FILTER',
                        style: AppTheme.orbitron(
                          fontSize: 12,
                          color: AppColors.black,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── User Tile ────────────────────────────────────────────────────────────
  Widget _buildUserTile(Map<String, dynamic> user) {
    final String? avatarUrl = user['avatar_url'] as String?;
    final String fullName =
        (user['full_name'] as String?)?.trim().isNotEmpty == true
            ? user['full_name'] as String
            : (user['username'] as String? ?? '—');
    final String username = user['username'] as String? ?? '';

    final String? mutualHobby = user['mutual_hobby'] as String?;
    final int mutualFriendsCount = user['mutual_friends_count'] as int? ?? 0;
    final String status = user['connection_status'] as String? ?? 'none';

    return GestureDetector(
      onTap: () {
        debugPrint('[SearchPage] Navigating to profile: $username');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfilePage(userId: user['id']),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            // ── Avatar ──
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage:
                    avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) as ImageProvider : null,
                child: avatarUrl == null
                    ? Icon(Icons.person_rounded,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), size: 24)
                    : null,
              ),
            ),
            const SizedBox(width: 12),

            // ── Name + Subtitle ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: AppTheme.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Builder(builder: (context) {
                    if (mutualHobby != null) {
                      return Text(
                        '✨ Sama-sama suka $mutualHobby',
                        style: AppTheme.inter(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    } else if (mutualFriendsCount > 0) {
                      return Text(
                        '🤝 $mutualFriendsCount mutual friends',
                        style: AppTheme.inter(
                          color: AppColors.neonCyan,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    } else {
                      return Text(
                        '@$username',
                        style: AppTheme.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }
                  }),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Add/Requested/Chat Button ──
            Builder(builder: (context) {
              final String userId = user['id']?.toString() ?? '';
              final bool isConnecting = sendingRequestTo.contains(userId);
              
              if (status == 'friends') {
                return IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  color: AppColors.neonCyan,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomPage(
                          friendId: userId,
                          friendName: fullName,
                          friendUsername: username,
                          friendAvatar: avatarUrl ?? '',
                        ),
                      ),
                    );
                  },
                );
              }
              
              String label = 'Add';
              Color btnColor = Theme.of(context).colorScheme.primary;
              bool isBtnDisabled = isConnecting;

              if (isConnecting) {
                label = '...';
              } else if (status == 'requested') {
                isBtnDisabled = true;
                label = 'Requested';
                btnColor = AppColors.textDisabled;
              }

              return OutlinedButton(
                onPressed: isBtnDisabled ? null : () => _sendFriendRequest(userId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: btnColor,
                  side: BorderSide(
                    color: isBtnDisabled ? btnColor.withValues(alpha: 0.3) : btnColor,
                    width: 1.2,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isConnecting
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTheme.inter(
                          fontSize: 12,
                          color: btnColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Active Filter Badges ─────────────────────────────────────────────────
  Widget _buildActiveFilters() {
    if (selectedHobbies.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: selectedHobbies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final label = selectedHobbies[i];
          return GestureDetector(
            onTap: () {
              setState(() => selectedHobbies.remove(label));
              _performSearch();
            },
            child: Container(
              alignment: Alignment.center,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTheme.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.close_rounded,
                      size: 12, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        title: Text(
          'DISCOVER',
          style: AppTheme.orbitron(
            fontSize: 13,
            color: AppColors.textPrimary,
            letterSpacing: 4,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search Bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              style: AppTheme.inter(color: AppColors.textPrimary),
              onChanged: (val) {
                setState(() => searchQuery = val.trim());
                _performSearch();
              },
              decoration: InputDecoration(
                hintText: 'Search people, hobbies…',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textDisabled,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.tune_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                  onPressed: () => _showHobbiesFilterBottomSheet(context),
                  splashRadius: 20,
                  tooltip: 'Filter hobbies',
                ),
              ),
            ),
          ),

          // ── Active Filter Badges ──────────────────────────────────────────
          if (selectedHobbies.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildActiveFilters(),
          ],
          const SizedBox(height: 16),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: (searchQuery.isEmpty && selectedHobbies.isEmpty)
                ? _buildSuggestedSection()
                : _buildSearchResultsSection(),
          ),
        ],
      ),
    );
  }

  // ─── Suggested For You ────────────────────────────────────────────────────
  Widget _buildSuggestedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'SUGGESTED FOR YOU',
            style: AppTheme.orbitron(
              fontSize: 9,
              color: AppColors.textSecondary,
              letterSpacing: 3,
            ),
          ),
        ),
        Expanded(
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    strokeWidth: 2,
                  ),
                )
              : suggestedUsers.isEmpty
                  ? _buildEmptyState(isSuggested: true)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: suggestedUsers.length,
                      itemBuilder: (_, i) =>
                          _buildUserTile(suggestedUsers[i]),
                    ),
        ),
      ],
    );
  }

  // ─── Search Results ───────────────────────────────────────────────────────
  Widget _buildSearchResultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Text(
                'SEARCH RESULTS',
                style: AppTheme.orbitron(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                  letterSpacing: 3,
                ),
              ),
              if (!isLoading && searchResults.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${searchResults.length}',
                    style: AppTheme.orbitron(
                      fontSize: 8,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    strokeWidth: 2,
                  ),
                )
              : searchResults.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: searchResults.length,
                      itemBuilder: (_, i) =>
                          _buildUserTile(searchResults[i]),
                    ),
        ),
      ],
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────
  Widget _buildEmptyState({bool isSuggested = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_rounded,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            size: 56,
          ),
          const SizedBox(height: 14),
          Text(
            isSuggested ? 'NO USERS YET' : 'NO RESULTS FOUND',
            style: AppTheme.orbitron(
              fontSize: 11,
              color: AppColors.textSecondary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isSuggested
                ? 'Be the first to join the community!'
                : 'Try a different name or adjust your filter',
            style: AppTheme.inter(
              fontSize: 13,
              color: AppColors.textDisabled,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


