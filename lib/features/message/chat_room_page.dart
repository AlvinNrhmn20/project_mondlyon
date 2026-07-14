import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';

class ChatRoomPage extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String friendUsername;
  final String friendAvatar;
  final String? postId;
  final String? postThumbnailUrl;
  // ── P3: Template teks awal (mis. dari Add Friend flow) ──────────────────
  final String? initialText;
  final bool triggerIcebreaker;
  // ─────────────────────────────────────────────────────────────────────────

  const ChatRoomPage({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.friendUsername,
    required this.friendAvatar,
    this.postId,
    this.postThumbnailUrl,
    this.initialText, // ← P3: template chat otomatis
    this.triggerIcebreaker = false, // ← HANYA trigger jika dari ProfilePage
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _messageController = TextEditingController();
  final _supabase = Supabase.instance.client;
  late final String myId;

  // ── Privacy Fix: StreamController + RealtimeChannel ─────────────────────
  final _messagesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get _messagesStream =>
      _messagesController.stream;
  RealtimeChannel? _realtimeChannel;
  // ─────────────────────────────────────────────────────────────────────────

  String? _activeReplyPostId;
  String? _activeReplyThumbnail;

  // ── Image & Voice State ──────────────────────────────────────────────────
  bool _isSendingImage = false;
  bool _isRecording = false;
  late final AudioRecorder _audioRecorder;
  String? _recordingPath;
  // ─────────────────────────────────────────────────────────────────────────

  // ── Icebreaker Guard ─────────────────────────────────────────────────────
  bool _icebreakerChecked = false; // Pastikan hanya berjalan sekali per sesi
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    _activeReplyPostId = widget.postId;
    _activeReplyThumbnail = widget.postThumbnailUrl;
    super.initState();
    myId = _supabase.auth.currentUser!.id;
    _audioRecorder = AudioRecorder();
    _initMessagesStream();
    _markMessagesAsRead();

    // P3: Gabungkan logika initialText & Icebreaker Hobi
    // Hanya jalankan jika triggerIcebreaker = true (dibuka dari Profile)
    if (widget.triggerIcebreaker) {
      _checkAndPrefillIcebreaker(); 
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('receiver_id', myId)
          .eq('sender_id', widget.friendId)
          .eq('is_read', false);
    } catch (e) {
      // Ignored in case is_read column doesn't exist yet
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _messagesController.close();
    _messageController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ── Server-side filtered stream setup ────────────────────────────────────
  void _initMessagesStream() {
    _fetchAndPushMessages();
    _realtimeChannel = _supabase
        .channel('chat_${myId}_${widget.friendId}')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _fetchAndPushMessages(),
        )
      ..subscribe();
  }

  Future<void> _fetchAndPushMessages() async {
    try {
      final data = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$myId,receiver_id.eq.${widget.friendId})'
              ',and(sender_id.eq.${widget.friendId},receiver_id.eq.$myId)')
          .order('created_at', ascending: false)
          .limit(50); // ✅ P3 Fix: Batasi 50 pesan terbaru
      if (!_messagesController.isClosed) {
        _messagesController.add(List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      debugPrint('[ChatRoom] Error fetching messages: $e');
      // ✅ Tambahkan fallback agar tidak stuck loading selamanya jika error
      if (!_messagesController.isClosed) {
        _messagesController.add([]);
      }
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  // ── Smart 'Start Conversation' (Icebreaker Auto-fill) ────────────────────
  Future<void> _checkAndPrefillIcebreaker() async {
    if (_icebreakerChecked) return;
    _icebreakerChecked = true; // Set dulu sebagai guard sebelum query async

    try {
      // Fetch hobi kedua user + jumlah pesan secara paralel
      final results = await Future.wait([
        _supabase.from('user_hobbies').select('hobby_id').eq('user_id', myId),
        _supabase.from('user_hobbies').select('hobby_id').eq('user_id', widget.friendId),
        _supabase
            .from('messages')
            .count()
            .or('and(sender_id.eq.$myId,receiver_id.eq.${widget.friendId})'
                ',and(sender_id.eq.${widget.friendId},receiver_id.eq.$myId)'),
      ]);

      final myHobbyIds =
          (results[0] as List).map((e) => e['hobby_id'].toString()).toSet();
      final friendHobbyIds =
          (results[1] as List).map((e) => e['hobby_id'].toString()).toSet();
      final messageCount = results[2] as int? ?? 0;

      // Kondisi 1: Harus chat baru (0 pesan)
      if (messageCount > 0) return;

      String prefill = '';

      // Kondisi 2: Cari hobi yang beririsan
      final sharedIds = myHobbyIds.intersection(friendHobbyIds);
      if (sharedIds.isNotEmpty) {
        // Resolve nama hobi pertama yang beririsan
        final hobbyData = await _supabase
            .from('hobbies')
            .select('name')
            .eq('id', sharedIds.first)
            .maybeSingle();

        final hobbyName = hobbyData?['name']?.toString() ?? '';
        if (hobbyName.isNotEmpty) {
          prefill = 'Wah, kita sama-sama suka $hobbyName nih! 🧊';
        }
      }

      // Fallback: Jika tidak ada hobi bersama, gunakan template default dari flow Add Friend
      if (prefill.isEmpty && widget.initialText != null && widget.initialText!.isNotEmpty) {
        prefill = widget.initialText!;
      }

      if (prefill.isNotEmpty && mounted) {
        setState(() {
          _messageController.text = prefill;
        });
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    } catch (e) {
      debugPrint('[Icebreaker] Error saat prefill: $e');
      // Fallback aman jika terjadi network error saat mencari hobi
      if (widget.initialText != null && widget.initialText!.isNotEmpty && mounted) {
        setState(() {
          _messageController.text = widget.initialText!;
        });
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': widget.friendId,
        'content': text,
        if (_activeReplyPostId != null) 'post_id': _activeReplyPostId,
      });

      if (mounted && _activeReplyPostId != null) {
        setState(() {
          _activeReplyPostId = null;
          _activeReplyThumbnail = null;
        });
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            // ✅ P2 Fix: User-friendly error message
            content: Text('Gagal mengirim pesan. Periksa koneksi Anda.'),
            backgroundColor: AppColors.surfaceCard,
          ),
        );
      }
    }
  }

  // ── Send Image Message ───────────────────────────────────────────────────
  Future<void> _sendImageMessage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1080,
    );
    if (picked == null || !mounted) return;

    setState(() => _isSendingImage = true);

    final file = File(picked.path);
    try {
      final ext = picked.path.split('.').last.toLowerCase();
      final fileName = 'chat_images/${myId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await _supabase.storage.from('chat_media').upload(
            fileName,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = _supabase.storage.from('chat_media').getPublicUrl(fileName);

      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': widget.friendId,
        'content': publicUrl,
        'message_type': 'image',
      });
    } catch (e) {
      debugPrint('Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            // ✅ P2 Fix: User-friendly error message
            content: Text('Gagal mengirim gambar. Periksa koneksi Anda.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
      // ✅ P2 Fix: Hapus file temp dari storage perangkat setelah upload
      try { file.deleteSync(); } catch (_) {}
    }
  }

  // ── Voice Note Recording ─────────────────────────────────────────────────
  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: _recordingPath!,
    );
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendVoice() async {
    if (!_isRecording) return;
    await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);

    final path = _recordingPath;
    if (path == null) return;

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 100) return;

    try {
      final fileName = 'chat_voice/${myId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _supabase.storage.from('chat_voice').upload(
            fileName,
            file,
            fileOptions: const FileOptions(upsert: true, contentType: 'audio/m4a'),
          );

      final publicUrl = _supabase.storage.from('chat_voice').getPublicUrl(fileName);

      await _supabase.from('messages').insert({
        'sender_id': myId,
        'receiver_id': widget.friendId,
        'content': publicUrl,
        'message_type': 'audio',
      });
    } catch (e) {
      debugPrint('Error sending voice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            // ✅ P2 Fix: User-friendly error message
            content: Text('Gagal mengirim pesan suara. Periksa koneksi Anda.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      // ✅ P2 Fix: Hapus file .m4a temp dari direktori lokal setelah upload
      try { file.deleteSync(); } catch (_) {}
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.surfaceElevated,
                backgroundImage: widget.friendAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(widget.friendAvatar) as ImageProvider
                    : null,
                child: widget.friendAvatar.isEmpty
                    ? const Icon(Icons.person_rounded, color: AppColors.textDisabled, size: 20)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.friendName,
                    style: AppTheme.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${widget.friendUsername}',
                    style: AppTheme.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          // ── Messages List ─────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }

                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
                }

                final messages = snapshot.data!.where((msg) {
                  final sender = msg['sender_id'];
                  final receiver = msg['receiver_id'];
                  return (sender == myId && receiver == widget.friendId) ||
                         (sender == widget.friendId && receiver == myId);
                }).toList();

                final hasUnreadFromFriend = messages.any((msg) =>
                    msg['sender_id'] == widget.friendId && msg['is_read'] == false);

                if (hasUnreadFromFriend) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markMessagesAsRead();
                  });
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'START A CONVERSATION',
                          style: AppTheme.orbitron(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Send a message to begin chatting',
                          style: AppTheme.inter(
                            fontSize: 12,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == myId;

                    bool showDate = false;
                    String dateString = '';
                    if (index == messages.length - 1) {
                      showDate = true;
                    } else {
                      final currDate = DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();
                      final prevDate = DateTime.tryParse(messages[index + 1]['created_at']?.toString() ?? '')?.toLocal();
                      if (currDate != null && prevDate != null) {
                        if (currDate.year != prevDate.year || currDate.month != prevDate.month || currDate.day != prevDate.day) {
                          showDate = true;
                        }
                      }
                    }

                    if (showDate) {
                      final date = DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();
                      if (date != null) {
                        final now = DateTime.now();
                        final yesterday = now.subtract(const Duration(days: 1));
                        if (date.year == now.year && date.month == now.month && date.day == now.day) {
                          dateString = 'Today';
                        } else if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
                          dateString = 'Yesterday';
                        } else {
                          dateString = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                        }
                      }
                    }

                    final bubble = ChatBubble(
                      message: msg,
                      isMe: isMe,
                      currentPostId: widget.postId,
                      currentThumbnail: widget.postThumbnailUrl,
                    );

                    if (showDate) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.divider, width: 1),
                              ),
                              child: Text(
                                dateString,
                                style: AppTheme.inter(color: AppColors.textDisabled, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          bubble,
                        ],
                      );
                    }
                    return bubble;
                  },
                );
              },
            ),
          ),

          // ── Recording Indicator ──────────────────────────────────────
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: Colors.redAccent.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Recording... Release to send',
                    style: AppTheme.inter(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
              ),
            ),

          // ── Bottom Input Bar ──
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_activeReplyThumbnail != null)
                    Container(
                      margin: const EdgeInsets.only(left: 48, bottom: 8),
                      height: 60,
                      width: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(_activeReplyThumbnail!),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeReplyPostId = null;
                              _activeReplyThumbnail = null;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      // ── Photo Library Button ──
                      _isSendingImage
                          ? const SizedBox(
                              width: 40, height: 40,
                              child: Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.photo_library_outlined, color: AppColors.textSecondary),
                              onPressed: _sendImageMessage,
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCard,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.divider, width: 1),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: AppTheme.inter(color: AppColors.textPrimary, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: _isRecording ? 'Recording...' : 'Message...',
                                    hintStyle: AppTheme.inter(
                                      color: _isRecording ? Colors.redAccent : AppColors.textDisabled,
                                      fontSize: 14,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  textCapitalization: TextCapitalization.sentences,
                                ),
                              ),
                              // ── Microphone Button (Hold to Record) ──
                              GestureDetector(
                                onLongPressStart: (_) => _startRecording(),
                                onLongPressEnd: (_) => _stopAndSendVoice(),
                                onTap: _isRecording ? _stopAndSendVoice : _startRecording,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    _isRecording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                                    color: _isRecording ? Colors.redAccent : AppColors.textDisabled,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: sendMessage,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                AppColors.neonPurpleDim,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatBubble — handles text, image, and audio message types
// ─────────────────────────────────────────────────────────────────────────────

class ChatBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String? currentPostId;
  final String? currentThumbnail;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.currentPostId,
    this.currentThumbnail,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  String? _thumbnailUrl;
  bool _isLoading = false;

  // ── Audio player state ───────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  // ─────────────────────────────────────────────────────────────────────────

  String _formatTimestamp(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr)?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();

    // Fetch post thumbnail if this is a post-reply message
    final msgPostId = widget.message['post_id']?.toString();
    if (msgPostId != null) {
      if (msgPostId == widget.currentPostId && widget.currentThumbnail != null) {
        _thumbnailUrl = widget.currentThumbnail;
      } else {
        _fetchThumbnail(msgPostId);
      }
    }

    // Set up audio player listeners if this is a voice note
    if (widget.message['message_type'] == 'audio') {
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      });
      _audioPlayer.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      _audioPlayer.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _fetchThumbnail(String postId) async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('posts')
          .select('back_video_url')
          .eq('id', postId)
          .maybeSingle();
      if (mounted && response != null) {
        setState(() {
          _thumbnailUrl = response['back_video_url'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error fetching thumbnail: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePlayPause(String url) async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(url));
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  // ── Hold-to-Delete (hanya untuk pesan milik current user) ───────────────
  Future<void> _deleteMessage(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text(
          'Delete Message',
          style: AppTheme.inter(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this message?',
          style: AppTheme.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: AppTheme.inter(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Delete', style: AppTheme.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final rawId = widget.message['id'];
      if (rawId == null) return;
      // ✅ FIX: messages.id is bigint — pass as int to avoid type mismatch
      final messageId = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (messageId == null) return;
      await Supabase.instance.client
          .from('messages')
          .delete()
          .eq('id', messageId);
    } catch (e) {
      debugPrint('[ChatRoom] Error deleting message: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal menghapus pesan. Coba lagi.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final messageType = widget.message['message_type']?.toString() ?? 'text';
    final content = widget.message['content']?.toString() ?? '';

    final bubbleWidget = Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: messageType == 'image'
            ? null
            : BoxDecoration(
                color: widget.isMe ? primary : AppColors.surfaceCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: widget.isMe ? const Radius.circular(18) : const Radius.circular(8),
                  bottomRight: widget.isMe ? const Radius.circular(8) : const Radius.circular(18),
                ),
                border: widget.isMe
                    ? null
                    : Border.all(
                        color: primary.withValues(alpha: 0.15),
                        width: 1,
                      ),
                boxShadow: widget.isMe
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
        child: _buildContent(messageType, content, primary),
      ),
    );

    // Hold-to-delete: hanya aktif jika pesan milik current user
    if (!widget.isMe) return bubbleWidget;

    return GestureDetector(
      onLongPress: () => _deleteMessage(context),
      child: bubbleWidget,
    );
  }

  Widget _buildContent(String messageType, String content, Color primary) {
    // ── IMAGE BUBBLE ──
    if (messageType == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: widget.isMe ? const Radius.circular(18) : const Radius.circular(4),
          bottomRight: widget.isMe ? const Radius.circular(4) : const Radius.circular(18),
        ),
        child: CachedNetworkImage(
          imageUrl: content,
          fit: BoxFit.cover,
          width: MediaQuery.of(context).size.width * 0.65,
          placeholder: (context, url) => SizedBox(
            height: 180,
            width: MediaQuery.of(context).size.width * 0.65,
            child: Center(
              child: CircularProgressIndicator(color: primary, strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(Icons.image_not_supported, color: Colors.white54, size: 40),
          ),
        ),
      );
    }

    // ── AUDIO BUBBLE ──
    if (messageType == 'audio') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _togglePlayPause(content),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.isMe ? Colors.white.withValues(alpha: 0.25) : primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: (_duration.inSeconds > 0)
                          ? _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble())
                          : 0,
                      max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
                      onChanged: (v) async {
                        await _audioPlayer.seek(Duration(seconds: v.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: AppTheme.inter(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.graphic_eq_rounded, color: Colors.white54, size: 18),
          ],
        ),
      );
    }

    // ── TEXT BUBBLE (default) ──
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message['post_id'] != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isLoading
                  ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                  : (_thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: _thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Center(child: Icon(Icons.image_not_supported, color: Colors.white54)),
                        )
                      : const Center(child: Icon(Icons.image_not_supported, color: Colors.white54))),
            ),
          ],
          Text(
            content,
            style: AppTheme.inter(fontSize: 14, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTimestamp(widget.message['created_at']?.toString()),
                style: AppTheme.inter(fontSize: 10, color: Colors.white70),
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  widget.message['is_read'] == true ? Icons.done_all_rounded : Icons.check_rounded,
                  size: 14,
                  color: widget.message['is_read'] == true ? Colors.lightBlueAccent : Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
