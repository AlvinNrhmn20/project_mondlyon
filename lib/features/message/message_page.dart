// lib/features/message/message_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';
import 'chat_room_page.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  List<Map<String, dynamic>> friendsList = [];
  List<Map<String, dynamic>> _allMessages = [];
  bool isLoading = true;
  late final String myId;
  final _supabase = Supabase.instance.client;

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _connectionsChannel;

  @override
  void initState() {
    super.initState();
    myId = _supabase.auth.currentUser!.id;
    _initData();
    _setupRealtime();
  }

  Future<void> _initData() async {
    await Future.wait([
      fetchFriends(),
      _fetchMessages(),
    ]);
  }

  // ── Realtime: listen messages + connections ────────────────────────────────
  void _setupRealtime() {
    _messagesChannel = _supabase
        .channel('inbox_$myId')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _fetchMessages(),
        )
      ..subscribe();

    // ✅ Bug 1 Fix: Subscribe ke connections agar friendsList auto-refresh
    _connectionsChannel = _supabase
        .channel('connections_msg_$myId')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'connections',
          callback: (_) => fetchFriends(),
        )
      ..subscribe();
  }

  Future<void> fetchFriends() async {
    try {
      final currentUserId = myId;

      final connections = await _supabase
          .from('connections')
          .select('sender_id, receiver_id')
          .inFilter('status', ['friends', 'requested'])
          .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId');

      if (connections.isEmpty) {
        if (mounted) {
          setState(() {
            friendsList = [];
            isLoading = false;
          });
        }
        return;
      }

      final friendIds = connections.map((row) {
        return row['sender_id'] == currentUserId
            ? row['receiver_id']
            : row['sender_id'];
      }).toList();

      final profiles = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .inFilter('id', friendIds);

      if (mounted) {
        setState(() {
          friendsList = List<Map<String, dynamic>>.from(profiles);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching friends: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ✅ Bug 2 Fix: Simpan ke state variable, bukan broadcast stream
  Future<void> _fetchMessages() async {
    try {
      final data = await _supabase
          .from('messages')
          .select()
          .or('sender_id.eq.$myId,receiver_id.eq.$myId')
          .order('created_at', ascending: false)
          .limit(500);
      if (mounted) {
        setState(() {
          _allMessages = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('[MessagePage] Error fetching messages: $e');
    }
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _connectionsChannel?.unsubscribe();
    super.dispose();
  }

  void _showNewMessageBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Drag Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'NEW MESSAGE',
                  style: AppTheme.orbitron(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.divider, height: 1),
                Expanded(
                  child: isLoading
                      ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                      : friendsList.isEmpty
                          ? Center(child: Text('No friends yet', style: AppTheme.inter(color: AppColors.textDisabled)))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: friendsList.length,
                              itemBuilder: (context, index) {
                                final friend = friendsList[index];
                                final avatarUrl = friend['avatar_url'] as String?;
                                final fullName = friend['full_name'] as String? ?? friend['username'] as String? ?? 'User';
                                final username = friend['username'] as String? ?? 'User';

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.surfaceCard,
                                    backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) as ImageProvider : null,
                                    child: avatarUrl == null
                                        ? const Icon(Icons.person_rounded, color: AppColors.textDisabled, size: 22)
                                        : null,
                                  ),
                                  title: Text(
                                    fullName,
                                    style: AppTheme.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '@$username',
                                    style: AppTheme.inter(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatRoomPage(
                                          friendId: friend['id'] ?? '',
                                          friendName: fullName,
                                          friendUsername: username,
                                          friendAvatar: avatarUrl ?? '',
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Bug 2 Fix: Compute chat data langsung dari state, bukan stream
    final chatData = <String, Map<String, dynamic>>{};
    for (final msg in _allMessages) {
      final sender = msg['sender_id'];
      final receiver = msg['receiver_id'];
      if (sender != myId && receiver != myId) continue;

      final friendId = sender == myId ? receiver : sender;

      if (!chatData.containsKey(friendId)) {
        chatData[friendId] = {
          'last_message': msg['content'],
          'created_at': msg['created_at'],
          'unread_count': 0,
        };
      }

      final isRead = msg['is_read'] == true;
      if (receiver == myId && !isRead) {
        chatData[friendId]!['unread_count'] = (chatData[friendId]!['unread_count'] as int) + 1;
      }
    }

    // Sort friendsList based on latest message timestamp
    final sortedFriends = List<Map<String, dynamic>>.from(friendsList);
    sortedFriends.sort((a, b) {
      final dateA = chatData[a['id']]?['created_at'] as String?;
      final dateB = chatData[b['id']]?['created_at'] as String?;

      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      return DateTime.parse(dateB).compareTo(DateTime.parse(dateA)); // descending
    });

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(
          'MESSAGES',
          style: AppTheme.orbitron(
            fontSize: 13,
            color: AppColors.textPrimary,
            letterSpacing: 4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                Icons.edit_square,
                color: Theme.of(context).colorScheme.primary,
                size: 21,
              ),
              onPressed: () => _showNewMessageBottomSheet(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Active Now row ──
          SizedBox(
            height: 92,
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                : friendsList.isEmpty
                    ? Center(child: Text('No active friends', style: AppTheme.inter(color: AppColors.textDisabled)))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: friendsList.length,
                        itemBuilder: (_, i) => _ActiveAvatar(
                          index: i,
                          friend: friendsList[i],
                        ),
                      ),
          ),

          // ── Divider ──
          const Divider(color: AppColors.divider, height: 1),

          // ── Chat List ──
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                : friendsList.isEmpty
                    ? Center(child: Text('No friends yet.', style: AppTheme.inter(color: AppColors.textDisabled)))
                    : ListView.separated(
                        itemCount: sortedFriends.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (context, index) {
                           final friend = sortedFriends[index];
                           final friendId = friend['id'];
                           final data = chatData[friendId];
                           return _ChatTile(
                             friend: friend, 
                             lastMessage: data?['last_message'] as String?,
                             createdAt: data?['created_at'] as String?,
                             unreadCount: data?['unread_count'] as int? ?? 0,
                           );
                        }
                      ),
          ),
        ],
      ),
    );
  }
}


class _ActiveAvatar extends StatelessWidget {
  const _ActiveAvatar({required this.index, required this.friend});
  final int index;
  final Map<String, dynamic> friend;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isFirst = index == 0;
    final avatarUrl = friend['avatar_url'] as String?;
    final username = friend['username'] as String? ?? 'User';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final fullName = friend['full_name'] as String? ?? username;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(
              friendId: friend['id'] ?? '',
              friendName: fullName,
              friendUsername: username,
              friendAvatar: avatarUrl ?? '',
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          children: [
            Stack(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceCard,
                  border: Border.all(
                    color: primary,
                    width: isFirst ? 2 : 1.5,
                  ),
                  boxShadow: isFirst ? [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)] : null,
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) as ImageProvider : null,
                  child: avatarUrl == null
                      ? const Icon(
                          Icons.person_rounded,
                          color: AppColors.textDisabled,
                          size: 24,
                        )
                      : null,
                ),
              ),
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.black, width: 2),
                    boxShadow: AppColors.neonGreenGlowShadow,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            username.length > 8 ? '${username.substring(0, 8)}...' : username,
            style: AppTheme.inter(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.friend,
    this.lastMessage,
    this.createdAt,
    this.unreadCount = 0,
  });
  final Map<String, dynamic> friend;
  final String? lastMessage;
  final String? createdAt;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final avatarUrl = friend['avatar_url'] as String?;
    final fullName = friend['full_name'] as String? ?? friend['username'] as String? ?? 'User';
    
    final hasUnread = unreadCount > 0;
    
    String timeString = '';
    if (createdAt != null) {
      final date = DateTime.tryParse(createdAt!)?.toLocal();
      if (date != null) {
        final now = DateTime.now();
        if (date.year == now.year && date.month == now.month && date.day == now.day) {
           timeString = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        } else {
           timeString = '${date.day}/${date.month}';
        }
      }
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoomPage(
              friendId: friend['id'] ?? '',
              friendName: friend['full_name'] ?? friend['username'] ?? 'User',
              friendUsername: friend['username'] ?? '',
              friendAvatar: friend['avatar_url'] ?? '',
            ),
          ),
        );
      },
      child: ListTile(
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceCard,
            border: Border.all(
              color: hasUnread ? primary : AppColors.divider,
              width: hasUnread ? 1.5 : 1,
            ),
            boxShadow: hasUnread ? [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)] : null,
          ),
          child: CircleAvatar(
            backgroundColor: Colors.transparent,
            backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) as ImageProvider : null,
            child: avatarUrl == null
                ? const Icon(Icons.person_rounded, color: AppColors.textDisabled, size: 22)
                : null,
          ),
        ),
        title: Text(
          fullName,
          style: AppTheme.inter(
            fontSize: 14,
            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
            color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        subtitle: Text(
          lastMessage ?? 'Tap to chat',
          style: AppTheme.inter(
            fontSize: 12,
            color: hasUnread ? primary : AppColors.textDisabled,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              timeString,
              style: AppTheme.inter(
                fontSize: 11,
                color: hasUnread ? primary : AppColors.textDisabled,
              ),
            ),
            if (hasUnread) ...[
              const SizedBox(height: 4),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$unreadCount',
                  style: AppTheme.orbitron(
                    fontSize: 9,
                    color: AppColors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}