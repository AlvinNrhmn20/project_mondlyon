import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'profile_page.dart';

class ConnectionsPage extends StatefulWidget {
  final String profileName;
  final String userId;

  const ConnectionsPage({super.key, required this.profileName, required this.userId});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  late final String myId;
  late final bool isCurrentUser;
  final _supabase = Supabase.instance.client;

  // ── Realtime state ──────────────────────────────────────────────────────
  RealtimeChannel? _realtimeChannel;
  List<Map<String, dynamic>> _userConns = [];
  Map<String, Map<String, dynamic>> _profilesMap = {};
  Set<String> _myFriendsIds = {};
  bool _isLoading = true;
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    myId = _supabase.auth.currentUser!.id;
    isCurrentUser = widget.userId == myId;
    _fetchConnections();
    _setupRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    _realtimeChannel = _supabase
        .channel('connections_${widget.userId}')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'connections',
          callback: (_) => _fetchConnections(),
        )
      ..subscribe();
  }

  Future<void> _fetchConnections() async {
    try {
      // 1) Fetch connections yang relevan dengan user ini
      final conns = await _supabase
          .from('connections')
          .select()
          .or('sender_id.eq.${widget.userId},receiver_id.eq.${widget.userId}');

      // 2) Kumpulkan semua ID profile yang perlu di-fetch
      final Set<String> otherIds = {};
      for (var c in conns) {
        otherIds.add(c['sender_id'] as String);
        otherIds.add(c['receiver_id'] as String);
      }
      otherIds.remove(widget.userId);

      // 3) Fetch profiles
      Map<String, Map<String, dynamic>> profiles = {};
      if (otherIds.isNotEmpty) {
        final data = await _supabase
            .from('profiles')
            .select('id, username, full_name, avatar_url')
            .inFilter('id', otherIds.toList());
        profiles = {for (var p in data) p['id'] as String: p};
      }

      // 4) Hitung mutual friends jika bukan current user
      Set<String> myFriends = {};
      if (!isCurrentUser) {
        final myConns = await _supabase
            .from('connections')
            .select('sender_id, receiver_id')
            .eq('status', 'friends')
            .or('sender_id.eq.$myId,receiver_id.eq.$myId');
        for (var c in myConns) {
          myFriends.add(c['sender_id'] == myId ? c['receiver_id'] : c['sender_id']);
        }
      } else {
        // Untuk current user, hitung dari data yang sudah ada
        for (var c in conns) {
          if (c['status'] == 'friends') {
            myFriends.add(c['sender_id'] == myId ? c['receiver_id'] : c['sender_id']);
          }
        }
      }

      if (mounted) {
        setState(() {
          _userConns = List<Map<String, dynamic>>.from(conns);
          _profilesMap = profiles;
          _myFriendsIds = myFriends;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ConnectionsPage] Error fetching: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showConfirmationSheet(String targetName, String? targetAvatar, String connectionId, String currentStatus, {required bool isSender}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isRequested = currentStatus == 'requested';
        final isFriendsAsReceiver = currentStatus == 'friends' && !isSender;
        final message = isRequested
            ? "$targetName will not see your friend request anymore and will not be notified."
            : isFriendsAsReceiver
                ? "$targetName will be moved to your followers list."
                : "You won't be able to see $targetName's public posts anymore.";
        final btnText = isRequested ? "Cancel Request" : "Unfollow";

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage: targetAvatar != null && targetAvatar.isNotEmpty ? NetworkImage(targetAvatar) : null,
                child: targetAvatar == null || targetAvatar.isEmpty
                    ? const Icon(Icons.person, size: 36, color: AppColors.textDisabled)
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      if (isFriendsAsReceiver) {
                        // Mereka yang add duluan → revert ke 'requested' (jadi follower)
                        await _supabase.from('connections').update({'status': 'requested'}).eq('id', connectionId);
                      } else {
                        // Kamu yang add duluan / cancel request → hapus total
                        await _supabase.from('connections').delete().eq('id', connectionId);
                      }
                      _fetchConnections();
                    } catch (e) {
                      debugPrint('Error updating connection: $e');
                    }
                  },
                  child: Text(
                    btnText,
                    style: AppTheme.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[700]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<Map<String, dynamic>> connections, Map<String, Map<String, dynamic>> profilesMap) {
    if (connections.isEmpty) {
      return Center(
        child: Text('No users found', style: AppTheme.inter(color: AppColors.textDisabled)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: connections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final conn = connections[index];
        final isSender = conn['sender_id'] == widget.userId;
        final otherId = isSender ? conn['receiver_id'] : conn['sender_id'];
        final profile = profilesMap[otherId] ?? {};
        final name = profile['full_name'] ?? profile['username'] ?? 'Unknown';
        final username = profile['username'] ?? 'unknown';
        final avatarUrl = profile['avatar_url'] as String?;
        final status = conn['status'] as String;

        Widget? trailing;
        if (isCurrentUser && isSender) {
          if (status == 'requested') {
            trailing = SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: () => _showConfirmationSheet(name, avatarUrl, conn['id'].toString(), status, isSender: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[850],
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Requested', style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          } else if (status == 'friends') {
            trailing = SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () => _showConfirmationSheet(name, avatarUrl, conn['id'].toString(), status, isSender: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[700]!),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Following', style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          }
        } else if (isCurrentUser && !isSender) {
          if (status == 'friends') {
            trailing = SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () => _showConfirmationSheet(name, avatarUrl, conn['id'].toString(), status, isSender: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey[700]!),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Following', style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          } else if (status == 'requested') {
            trailing = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppColors.neonGreen, size: 28),
                  onPressed: () async {
                    try {
                      // Trigger handle_new_connection otomatis:
                      // - Hapus notif friend_request
                      // - Buat notif accept_friend (dengan ON CONFLICT)
                      await _supabase.from('connections').update({'status': 'friends'}).eq('id', conn['id']);
                    } catch (e) {
                      debugPrint('Error accept: $e');
                    }
                    _fetchConnections();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 28),
                  onPressed: () async {
                    try {
                      await _supabase.from('connections').delete().eq('id', conn['id']);
                    } catch (e) {
                      debugPrint('Error reject: $e');
                    }
                    _fetchConnections();
                  },
                ),
              ],
            );
          }
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          onTap: otherId == myId
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePage(userId: otherId),
                    ),
                  ),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.surfaceElevated,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const Icon(Icons.person, color: AppColors.textDisabled)
                : null,
          ),
          title: Text(name, style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text('@$username', style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 14)),
          trailing: trailing,
        );
      },
    );
  }

  List<String> _buildTabLabels(List<Map<String, dynamic>> t1, List<Map<String, dynamic>> t2, List<Map<String, dynamic>> t3) {
    if (isCurrentUser) {
      return ['${t1.length} friend', '${t2.length} followers', '${t3.length} following'];
    } else {
      return ['${t1.length} mutuals', '${t2.length} friend', '${t3.length} followers'];
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Hitung tab data dari state ────────────────────────────────────────
    List<Map<String, dynamic>> tab1 = [];
    List<Map<String, dynamic>> tab2 = [];
    List<Map<String, dynamic>> tab3 = [];

    if (!_isLoading) {
      if (isCurrentUser) {
        tab1 = _userConns.where((c) => c['status'] == 'friends').toList();
        tab2 = _userConns.where((c) => c['receiver_id'] == widget.userId && c['status'] == 'requested').toList();
        tab3 = _userConns.where((c) => c['sender_id'] == widget.userId && c['status'] == 'requested').toList();
      } else {
        tab1 = _userConns.where((c) {
          if (c['status'] != 'friends') return false;
          final other = c['sender_id'] == widget.userId ? c['receiver_id'] : c['sender_id'];
          return _myFriendsIds.contains(other);
        }).toList();
        tab2 = _userConns.where((c) => c['status'] == 'friends').toList();
        tab3 = _userConns.where((c) => c['receiver_id'] == widget.userId && c['status'] == 'requested').toList();
      }
    }

    final tabLabels = _buildTabLabels(tab1, tab2, tab3);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.black,
        appBar: AppBar(
          backgroundColor: AppColors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.profileName,
            style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
            : Column(
                children: [
                  TabBar(
                    indicatorColor: Colors.white,
                    indicatorWeight: 3.0,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: tabLabels.map((t) => Tab(text: t)).toList(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildList(tab1, _profilesMap),
                        _buildList(tab2, _profilesMap),
                        _buildList(tab3, _profilesMap),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
