import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/constants.dart';
import '../../core/services/global_audio_player.dart';
import 'profile_page.dart';

class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailPage({super.key, required this.post});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  bool isFrontMain = false;

  final _commentController = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> _commentsStream;
  late final String myId;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _reactions = [];
  List<Map<String, dynamic>> _taggedProfiles = [];

  @override
  void initState() {
    super.initState();
    myId = Supabase.instance.client.auth.currentUser!.id;
    _commentsStream = Supabase.instance.client
        .from('post_comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', widget.post['id'])
        .order('created_at', ascending: true);
    _fetchReactions();
    _fetchTaggedProfiles();
    _autoPlayMusic();
  }

  void _autoPlayMusic() {
    try {
      final rawMusic = widget.post['spotify_data'];
      if (rawMusic != null) {
        final Map<String, dynamic> music = rawMusic is String 
            ? jsonDecode(rawMusic) 
            : Map<String, dynamic>.from(rawMusic as Map);
        final previewUrl = music['preview_url'];
        if (previewUrl != null && previewUrl.toString().isNotEmpty) {
          GlobalAudioPlayer().play(previewUrl.toString());
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchTaggedProfiles() async {
    final taggedIds = widget.post['tagged_users'] as List?;
    if (taggedIds == null || taggedIds.isEmpty) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username')
          .inFilter('id', taggedIds);
      
      if (mounted) {
        setState(() {
          _taggedProfiles = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching tags: $e');
    }
  }

  Future<void> _fetchReactions() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('post_reactions')
          .select('*, profiles(username, avatar_url)')
          .eq('post_id', widget.post['id']);
      
      if (mounted) {
        setState(() {
          _reactions = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching reactions: $e');
    }
  }

  String _getEmojiIcon(String type) {
    switch (type) {
      case 'like': return '👍';
      case 'happy': return '😃';
      case 'surprised': return '😯';
      case 'laughing': return '😂';
      case 'instant': return '⚡';
      default: return type;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _deleteComment(String commentId) async {
    try {
      await Supabase.instance.client
          .from('post_comments')
          .delete()
          .eq('id', commentId);
    } catch (e) {
      debugPrint('Error deleting comment: $e');
    }
  }

  void _showDeleteConfirmation(String commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Hapus Komentar?', style: AppTheme.orbitron(color: Colors.white, fontSize: 16)),
        content: Text('Yakin hapus komentar ini?', style: AppTheme.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: AppTheme.inter(color: AppColors.textDisabled)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteComment(commentId);
            },
            child: Text('Hapus', style: AppTheme.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('post_comments').insert({
        'post_id': widget.post['id'],
        'user_id': userId,
        'comment_text': text,
      });

      _commentController.clear();
    } catch (e) {
      debugPrint('Error submitting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koneksi terputus, gagal menyimpan data.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Report Post', style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Report this post for inappropriate content?', style: AppTheme.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: AppTheme.inter(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _reportPost(postId);
            },
            child: Text('Report', style: AppTheme.inter(color: Colors.redAccent)),
          ),
        ],
      ),
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
                Navigator.pop(context); // Go back after deleting
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

  void _showMoreOptions() {
    final postId = widget.post['id'].toString();
    final isMyPost = widget.post['user_id'] == myId;

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

  Widget _buildImage(String? url, {BoxFit fit = BoxFit.cover}) {
    if (url == null || url.isEmpty) {
      return Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.image_not_supported, color: AppColors.textDisabled, size: 40),
        ),
      );
    }
    // ✅ P3B: CachedNetworkImage untuk performa & konsistensi
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (context, url) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textDisabled),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.broken_image, color: AppColors.textDisabled, size: 40),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Extract Image URLs
    final frontUrl = widget.post['front_video_url']?.toString();
    final backUrl = widget.post['back_video_url']?.toString();

    final mainUrl = isFrontMain ? frontUrl : backUrl;
    final pipUrl = isFrontMain ? backUrl : frontUrl;

    // Extract other post data (with fallbacks)
    final caption = widget.post['caption'] as String? ?? '';
    final timeAgo = _formatTimeAgo(widget.post['created_at']?.toString());

    final profile = widget.post['profiles'] ?? {};
    final username = profile['username'] ?? 'User';
    final avatarUrl = profile['avatar_url'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8), // Jarak antara tombol back dan informasi
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // Rata kiri
                      children: [
                        Row(
                          children: [
                            // ✅ P3B: Avatar lebih besar, CachedNetworkImage
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              backgroundImage: avatarUrl != null
                                  ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
                                  : null,
                              child: avatarUrl == null
                                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              username,
                              style: AppTheme.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '•',
                              style: AppTheme.inter(
                                  color: AppColors.textSecondary,
                                  fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            // ✅ P3B: Hapus Late/On Time — tampilkan time ago
                            Text(
                              timeAgo,
                              style: AppTheme.inter(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      // Display Weather/Location in Detail Page
                      if (widget.post['weather_data'] != null)
                        Builder(
                          builder: (context) {
                            try {
                              final rawWeather = widget.post['weather_data'];
                              final Map<String, dynamic> weather = rawWeather is String 
                                  ? jsonDecode(rawWeather) 
                                  : Map<String, dynamic>.from(rawWeather as Map);
                                  
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${weather['location']} • ${weather['temperature']}',
                                  style: AppTheme.inter(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                ),
                              );
                            } catch (_) {
                              return const SizedBox.shrink();
                            }
                          },
                        ),
                      // Display Music if available
                      if (widget.post['spotify_data'] != null)
                        Builder(
                          builder: (context) {
                            try {
                              final rawMusic = widget.post['spotify_data'];
                              final Map<String, dynamic> music = rawMusic is String 
                                  ? jsonDecode(rawMusic) 
                                  : Map<String, dynamic>.from(rawMusic as Map);

                              final title = music['title'] ?? 'Unknown';
                              final artist = music['artist'] ?? 'Unknown Artist';
                              final previewUrl = music['preview_url'];

                              if (previewUrl == null) return const SizedBox.shrink();

                              return ValueListenableBuilder<bool>(
                                valueListenable: GlobalAudioPlayer().isPlaying,
                                builder: (context, isPlaying, child) {
                                  final isThisPlaying = GlobalAudioPlayer().currentUrl.value == previewUrl && isPlaying;

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: GestureDetector(
                                      onTap: () async {
                                        if (isThisPlaying) {
                                          await GlobalAudioPlayer().pause();
                                        } else {
                                          await GlobalAudioPlayer().play(previewUrl);
                                        }
                                      },
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 180),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.music_note, 
                                              size: 11, 
                                              color: isThisPlaying ? Theme.of(context).colorScheme.primary : AppColors.textDisabled,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '$title • $artist',
                                                style: AppTheme.inter(
                                                  color: isThisPlaying ? Theme.of(context).colorScheme.primary : AppColors.textDisabled,
                                                  fontSize: 11,
                                                  fontWeight: isThisPlaying ? FontWeight.w600 : FontWeight.normal,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                    ),
                  ),
                  // Right Icons
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.ios_share, color: Colors.white),
                        onPressed: () {
                          SharePlus.instance.share(
                            ShareParams(text: 'Check out this SyncReal post! [AppURL]'),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.white),
                        onPressed: _showMoreOptions,
                      ),
                    ],
                  )
                ],
              ),
            ),

            // ── Scrollable Content ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Image Stack (Main & PiP) ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          height: MediaQuery.of(context).size.height * 0.45,
                          width: double.infinity,
                          color: AppColors.surfaceCard,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Main Image
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: ClipRRect(
                                  key: ValueKey('main_$mainUrl'),
                                  borderRadius: BorderRadius.circular(24),
                                  child: SizedBox.expand(
                                    child: _buildImage(mainUrl, fit: BoxFit.cover),
                                  ),
                                ),
                              ),

                              // PiP Image
                              Positioned(
                                top: 16,
                                left: 16,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      isFrontMain = !isFrontMain;
                                    });
                                  },
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Container(
                                      key: ValueKey('pip_$isFrontMain'),
                                      width: 100,
                                      height: 130,
                                      decoration: BoxDecoration(
                                        color: AppColors.black,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Theme.of(context).colorScheme.primary, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox.expand(
                                          child: _buildImage(pipUrl, fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Caption ──
                    if (caption.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          caption,
                          style: AppTheme.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ),

                    // ── Tagged Users (Detail) ──
                    if (_taggedProfiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _taggedProfiles.map((p) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProfilePage(
                                      userId: p['id'],
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                '@${p['username']}',
                                style: AppTheme.inter(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ── RealMojis Section ──
                    if (_reactions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'RealMojis',
                            style: AppTheme.orbitron(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 70,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          itemCount: _reactions.length,
                          itemBuilder: (context, index) {
                            final reaction = _reactions[index];
                            final profile = reaction['profiles'] ?? {};
                            final reactionUrl = reaction['reaction_image_url'];
                            final avatarUrl = profile['avatar_url'];
                            final emojiType = reaction['emoji_type'] as String?;

                            return Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Avatar / Reaction Image
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                          width: 2),
                                      color: AppColors.surfaceElevated,
                                    ),
                                    child: ClipOval(
                                      child: reactionUrl != null
                                          ? Transform.scale(
                                              scaleX: -1,
                                              // ✅ P3B: CachedNetworkImage di RealMoji
                                              child: CachedNetworkImage(imageUrl: reactionUrl, fit: BoxFit.cover),
                                            )
                                          : (avatarUrl != null
                                              ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
                                              : const Icon(Icons.person, color: AppColors.textDisabled, size: 30)),
                                    ),
                                  ),
                                  // Emoji Badge
                                  if (emojiType != null)
                                    Positioned(
                                      bottom: -5,
                                      right: -5,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Theme.of(context).colorScheme.primary, width: 1.5),
                                        ),
                                        child: Text(
                                          _getEmojiIcon(emojiType),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Divider(color: AppColors.divider),
                    const SizedBox(height: 8),

                    // ── Comments Section ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Comments',
                          style: AppTheme.orbitron(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ListView for comments inside SingleChildScrollView
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _commentsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error loading comments', style: AppTheme.inter(color: Colors.redAccent)));
                        }
                        
                        final comments = snapshot.data ?? [];
                        if (comments.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: Text(
                                'No comments yet. Be the first!',
                                style: AppTheme.inter(color: AppColors.textDisabled, fontSize: 13),
                              ),
                            ),
                          );
                        }

                        final userIds = comments.map((c) => c['user_id'] as String).toSet().toList();

                        return FutureBuilder<List<Map<String, dynamic>>>(
                          future: Supabase.instance.client
                              .from('profiles')
                              .select('id, username, avatar_url')
                              .inFilter('id', userIds),
                          builder: (context, profileSnap) {
                            if (!profileSnap.hasData) {
                              return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
                            }
                            final profilesMap = {for (var p in profileSnap.data!) p['id'] as String: p};

                            return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                itemCount: comments.length,
                                itemBuilder: (context, index) {
                                  final comment = comments[index];
                                  final userId = comment['user_id'] as String;
                                  final profile = profilesMap[userId] ?? {};
                                  final username = profile['username'] ?? 'User';
                                  final avatarUrl = profile['avatar_url'];
                                  final text = comment['comment_text'] ?? '';
                                  final timeStr = _formatTimeAgo(comment['created_at']);
                                  final canDelete = userId == myId || widget.post['user_id'] == myId;

                                  return GestureDetector(
                                    onLongPress: canDelete ? () => _showDeleteConfirmation(comment['id'].toString()) : null,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16.0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: AppColors.surfaceElevated,
                                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                            child: avatarUrl == null ? const Icon(Icons.person, color: AppColors.textDisabled, size: 20) : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      username,
                                                      style: AppTheme.inter(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      timeStr,
                                                      style: AppTheme.inter(
                                                          color: AppColors.textSecondary,
                                                          fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  text,
                                                  style: AppTheme.inter(
                                                      color: Colors.white, fontSize: 14),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Bottom Input Field (Inside Column, Bottom) ──
            Container(
              color: Colors.black,
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 12.0,
                bottom: 12.0,
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: AppColors.divider),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: TextField(
                          controller: _commentController,
                          style: AppTheme.inter(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: AppTheme.inter(color: AppColors.textDisabled),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _isSubmitting
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary),
                            onPressed: _submitComment,
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


