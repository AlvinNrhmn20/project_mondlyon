// lib/features/camera/preview_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';

class PreviewPage extends StatefulWidget {
  final File frontImage;
  final File backImage;

  /// Jika true, gambar frontImage akan di-mirror (selfie dari kamera depan).
  /// Jika false (misal: dari gallery), tidak di-mirror.
  final bool isFrontMirrored;

  const PreviewPage({
    super.key,
    required this.frontImage,
    required this.backImage,
    this.isFrontMirrored = true,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  // ── Music State ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedMusic;

  String get _musicChipLabel {
    if (_selectedMusic != null) {
      return '🎵 ${_selectedMusic!['title']} • ${_selectedMusic!['artist']}';
    }
    return '🎵 Music';
  }

  // ── Visibility State ─────────────────────────────────────────────────────
  /// Nilai yang disimpan ke DB harus huruf kecil: 'public', 'friends', 'private'
  String _visibility = 'friends';

  // ── Tag Friends State ─────────────────────────────────────────────────────
  List<String> _taggedUserIds = [];

  // ── Location / Weather Chip State ────────────────────────────────────────
  /// null = idle, true = loading, false = aktif (data sudah dimuat)
  bool? _weatherLoading;

  Map<String, String>? _weatherData;

  bool get _isWeatherActive => _weatherData != null;

  String get _locationChipLabel {
    if (_weatherLoading == true) return 'Loading...';
    if (_isWeatherActive) return '📍 ${_weatherData!['location']}, ${_weatherData!['temperature']}';
    return '📍 Location';
  }

  Future<void> _onLocationChipTapped() async {
    if (_isWeatherActive || _weatherLoading == true) return;
    setState(() => _weatherLoading = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      String cityName = 'Unknown';
      if (placemarks.isNotEmpty) {
        cityName = placemarks[0].locality ?? placemarks[0].subAdministrativeArea ?? 'Unknown';
      }

      // ✅ FIXED: API key dari .env + timeout 10s (P3 fix bonus)
      final apiKey = dotenv.env['OPENWEATHER_API_KEY'] ?? '';
      final url = Uri.parse('https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$apiKey&units=metric');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final temp = (data['main']['temp'] as num).round();
        final condition = data['weather'][0]['main'];

        if (!mounted) return;
        setState(() {
          _weatherData = {
            'location': cityName,
            'temperature': '$temp°C',
            'condition': condition.toString(),
          };
          _weatherLoading = false;
        });
      } else {
        throw Exception('Failed to load weather data');
      }
    } catch (e) {
      debugPrint('[PreviewPage] Location Error: $e');
      if (!mounted) return;
      setState(() => _weatherLoading = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to get location: $e'),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
    }
  }

  // ── Upload State ──────────────────────────────────────────────────────────
  bool isUploading = false;
  final TextEditingController _captionController = TextEditingController();
  bool isSwapped = false;

  File get currentMainImage => isSwapped ? widget.frontImage : widget.backImage;
  File get currentPipImage => isSwapped ? widget.backImage : widget.frontImage;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData get _visibilityIcon {
    switch (_visibility) {
      case 'public':
        return Icons.public;
      case 'friends':
        return Icons.group;
      case 'private':
        return Icons.lock_outline;
      default:
        return Icons.group;
    }
  }

  String get _visibilityLabel {
    switch (_visibility) {
      case 'public':
        return 'Public';
      case 'friends':
        return 'Friends';
      case 'private':
        return 'Private';
      default:
        return 'Friends';
    }
  }

  String get _tagChipLabel {
    if (_taggedUserIds.isEmpty) return 'Tag';
    return '${_taggedUserIds.length} tagged';
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadPost() async {
    try {
      setState(() => isUploading = true);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Upload Gambar Utama
      final backPath = '$userId/${timestamp}_main.jpg';
      await supabase.storage
          .from('post_media')
          .upload(backPath, currentMainImage);
      final backUrl =
          supabase.storage.from('post_media').getPublicUrl(backPath);

      // Upload Gambar PIP
      final frontPath = '$userId/${timestamp}_pip.jpg';
      await supabase.storage
          .from('post_media')
          .upload(frontPath, currentPipImage);
      final frontUrl =
          supabase.storage.from('post_media').getPublicUrl(frontPath);

      // Insert Data ke Database
      // Visibility disimpan dalam huruf kecil agar konsisten dengan query filter:
      //   .or('visibility.eq.public,visibility.eq.friends')
      await supabase.from('posts').insert({
        'user_id': userId,
        'back_video_url': backUrl,
        'front_video_url': frontUrl,
        'caption': _captionController.text.trim(),
        'visibility': _visibility, // 'public' | 'friends' | 'private'
        'tagged_users': _taggedUserIds.isEmpty ? null : _taggedUserIds,
        // Sertakan weather_data HANYA jika chip Location sudah aktif
        if (_isWeatherActive) 'weather_data': jsonEncode(_weatherData),
        // Sertakan spotify_data jika chip Music sudah aktif
        if (_selectedMusic != null) 'spotify_data': jsonEncode(_selectedMusic),
      });

      // ── Update user_stats: last_post_date & streak_count ─────────────────
      final now = DateTime.now().toUtc();
      final currentStats = await supabase
          .from('user_stats')
          .select('streak_count, last_post_date')
          .eq('user_id', userId)
          .maybeSingle();

      int newStreak = 1;
      if (currentStats != null && currentStats['last_post_date'] != null) {
        final lastPost = DateTime.parse(
          currentStats['last_post_date'] as String,
        ).toUtc();
        
        final localNow = DateTime.now();
        final localLastPost = lastPost.toLocal();
        final nowDay = DateTime(localNow.year, localNow.month, localNow.day);
        final lastPostDay = DateTime(localLastPost.year, localLastPost.month, localLastPost.day);
        
        final diff = nowDay.difference(lastPostDay).inDays;
        
        if (diff == 0) {
          newStreak = currentStats['streak_count'] as int? ?? 1;
        } else if (diff == 1) {
          newStreak = (currentStats['streak_count'] as int? ?? 0) + 1;
        }
      }
      await supabase.from('user_stats').upsert({
        'user_id': userId,
        'last_post_date': now.toIso8601String(),
        'streak_count': newStreak,
      }, onConflict: 'user_id');
      // ─────────────────────────────────────────────────────────────────────

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Post Uploaded Successfully! ⚡',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengupload post. Periksa koneksi Anda.'),
          backgroundColor: AppColors.surfaceCard,
        ),
      );
    } finally {
      if (mounted) setState(() => isUploading = false);
      // ✅ P2 Fix: Hapus file temp kamera/galeri dari storage perangkat
      try { widget.frontImage.deleteSync(); } catch (_) {}
      try { widget.backImage.deleteSync(); } catch (_) {}
    }
  }

  // ── Privacy Bottom Sheet ──────────────────────────────────────────────────

  void _showPrivacyBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.white),
                title: const Text('Public',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Anyone can see this moment',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  setState(() => _visibility = 'public');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.group, color: Colors.white),
                title: const Text('Friends',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Only your mutual friends',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  setState(() => _visibility = 'friends');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.lock_outline, color: Colors.white),
                title: const Text('Private',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Only you can see this',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  setState(() => _visibility = 'private');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Music Bottom Sheet ────────────────────────────────────────────────────
  Future<void> _showMusicBottomSheet() async {
    Timer? debounce;
    List<dynamic> searchResults = [];
    bool isSearching = false;
    String selectedMood = 'Hits';
    final TextEditingController searchController = TextEditingController();
    bool initialSearchDone = false;

    final AudioPlayer audioPlayer = AudioPlayer();
    String? currentlyPlayingUrl;
    bool isPlaying = false;
    StateSetter? sheetSetState;
    // ✅ FIX P2: StreamSubscription dideklarasikan di sini, di-cancel di .then()
    // Listener dipasang INSIDE StatefulBuilder agar sheetSetState sudah ready.
    StreamSubscription? playerStateSub;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // ✅ FIX P2: Attach listener SEKALI pada build pertama,
            // setelah sheetSetState tersedia — hindari null pointer crash.
            // ✅ FIX P2: ??= hanya assign sekali (prefer_conditional_assignment)
            playerStateSub ??= audioPlayer.onPlayerStateChanged.listen((state) {
              if (state == PlayerState.completed) {
                // ✅ FIX P2: Null-safe call operator mencegah NPE setelah sheet ditutup
                sheetSetState?.call(() {
                  isPlaying = false;
                  currentlyPlayingUrl = null;
                });
              }
            });
            sheetSetState = setSheetState;

            void performSearch(String query) {
              if (debounce?.isActive ?? false) debounce!.cancel();
              debounce = Timer(const Duration(milliseconds: 500), () async {
                if (query.trim().isEmpty) {
                  setSheetState(() {
                    searchResults = [];
                    isSearching = false;
                  });
                  return;
                }
                setSheetState(() => isSearching = true);
                try {
                  final url = Uri.parse('https://itunes.apple.com/search?term=$query&entity=song&limit=10');
                  final response = await http.get(url);
                  if (response.statusCode == 200) {
                    final data = jsonDecode(response.body);
                    setSheetState(() {
                      searchResults = data['results'] ?? [];
                      isSearching = false;
                    });
                  } else {
                    setSheetState(() => isSearching = false);
                  }
                } catch (e) {
                  debugPrint('Music search error: $e');
                  setSheetState(() => isSearching = false);
                }
              });
            }

            if (!initialSearchDone) {
              initialSearchDone = true;
              performSearch('Hits');
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Handle bar
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title
                    Text(
                      'Add Music',
                      style: AppTheme.orbitron(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search for a song...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: AppColors.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                        onChanged: (val) {
                          setSheetState(() => selectedMood = '');
                          performSearch(val);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Mood Chips
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          {'label': '🔥 Hits', 'value': 'Hits'},
                          {'label': '☕ Chill', 'value': 'Chill'},
                          {'label': '🎸 Pop', 'value': 'Pop'},
                          {'label': '🕺 Viral', 'value': 'Viral'},
                          {'label': '🎧 R&B', 'value': 'R&B'},
                        ].map((mood) {
                          final isSelected = selectedMood == mood['value'];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(mood['label']!),
                              selected: isSelected,
                              showCheckmark: false,
                              selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                              backgroundColor: AppColors.surfaceCard,
                              labelStyle: AppTheme.inter(
                                color: isSelected ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              side: BorderSide(
                                color: isSelected ? Theme.of(context).colorScheme.primary : AppColors.divider,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  searchController.clear();
                                  setSheetState(() => selectedMood = mood['value']!);
                                  performSearch(mood['value']!);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12, height: 1),
                    // Results
                    Expanded(
                      child: isSearching
                          ? Center(
                              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                            )
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    'Search your favorite songs',
                                    style: AppTheme.inter(color: AppColors.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, index) {
                                    final track = searchResults[index];
                                    final title = track['trackName'] ?? 'Unknown';
                                    final artist = track['artistName'] ?? 'Unknown Artist';
                                    final coverUrl = track['artworkUrl100'];
                                    final previewUrl = track['previewUrl'];

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: coverUrl != null
                                            ? Image.network(coverUrl, width: 48, height: 48, fit: BoxFit.cover)
                                            : Container(
                                                width: 48,
                                                height: 48,
                                                color: Colors.white12,
                                                child: const Icon(Icons.music_note, color: Colors.white54),
                                              ),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        artist,
                                        style: const TextStyle(color: Colors.white54),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: previewUrl != null
                                          ? IconButton(
                                              icon: Icon(
                                                currentlyPlayingUrl == previewUrl.toString() && isPlaying
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_fill,
                                                color: Theme.of(context).colorScheme.primary,
                                                size: 36,
                                              ),
                                              onPressed: () async {
                                                // ✅ FIX P2: Cast eksplisit — null-guarded oleh ternary luar
                                                final url = previewUrl as String;
                                                if (currentlyPlayingUrl == url && isPlaying) {
                                                  await audioPlayer.pause();
                                                  setSheetState(() => isPlaying = false);
                                                } else {
                                                  if (isPlaying) {
                                                    await audioPlayer.stop();
                                                  }
                                                  await audioPlayer.play(UrlSource(url));
                                                  setSheetState(() {
                                                    currentlyPlayingUrl = url;
                                                    isPlaying = true;
                                                  });
                                                }
                                              },
                                            )
                                          : null,
                                      onTap: () {
                                        // ✅ FIX P2: Guard mounted agar tidak crash
                                        // jika page sudah di-dispose saat sheet ditutup
                                        if (mounted) {
                                          setState(() {
                                            _selectedMusic = {
                                              'title': title,
                                              'artist': artist,
                                              'cover_url': coverUrl,
                                              'preview_url': previewUrl,
                                            };
                                          });
                                        }
                                        Navigator.pop(sheetContext);
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
      },
    ).then((_) {
      sheetSetState = null;      // ✅ FIX P2: Invalidate setter — cegah setState setelah sheet tutup
      playerStateSub?.cancel();  // ✅ FIX P2: Cancel listener SEBELUM player di-dispose
      if (debounce?.isActive ?? false) debounce!.cancel();
      audioPlayer.stop();
      audioPlayer.dispose();
      searchController.dispose();
    });
  }

  // ── Tag Friends Bottom Sheet ──────────────────────────────────────────────

  Future<void> _showTagFriendsBottomSheet() async {
    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser!.id;

    // Tampilkan loading spinner sementara fetch data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      ),
    );

    List<Map<String, dynamic>> friends = [];
    try {
      // Ambil semua koneksi di kedua arah dengan status 'friends'
      final res1 = await supabase
          .from('connections')
          .select('receiver_id, profiles!connections_receiver_id_fkey(id, username, avatar_url)')
          .eq('sender_id', myId)
          .eq('status', 'friends');

      final res2 = await supabase
          .from('connections')
          .select('sender_id, profiles!connections_sender_id_fkey(id, username, avatar_url)')
          .eq('receiver_id', myId)
          .eq('status', 'friends');

      for (var row in res1 as List) {
        final profile = row['profiles'];
        if (profile != null) {
          friends.add({
            'id': profile['id'] as String,
            'username': profile['username'] as String? ?? 'unknown',
            'avatar_url': profile['avatar_url'] as String?,
          });
        }
      }
      for (var row in res2 as List) {
        final profile = row['profiles'];
        if (profile != null) {
          friends.add({
            'id': profile['id'] as String,
            'username': profile['username'] as String? ?? 'unknown',
            'avatar_url': profile['avatar_url'] as String?,
          });
        }
      }
    } catch (e) {
      debugPrint('[PreviewPage] Error fetching friends: $e');
    }

    if (!mounted) return;
    Navigator.pop(context); // Tutup loading dialog

    // Copy state saat ini agar bisa di-cancel
    final Set<String> tempSelected = Set.from(_taggedUserIds);

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // ── Header ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tag Friends',
                                style: AppTheme.orbitron(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${tempSelected.length} selected',
                                style: AppTheme.inter(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),

                    // ── Friends List ────────────────────────────────────
                    Expanded(
                      child: friends.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.group_off_rounded,
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                        size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No friends to tag yet',
                                      style: AppTheme.inter(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: friends.length,
                              itemBuilder: (context, index) {
                                final friend = friends[index];
                                final id = friend['id'] as String;
                                final username =
                                    friend['username'] as String;
                                final avatarUrl =
                                    friend['avatar_url'] as String?;
                                final isChecked =
                                    tempSelected.contains(id);

                                return CheckboxListTile(
                                  value: isChecked,
                                  onChanged: (val) {
                                    setSheetState(() {
                                      if (val == true) {
                                        tempSelected.add(id);
                                      } else {
                                        tempSelected.remove(id);
                                      }
                                    });
                                  },
                                  activeColor: Theme.of(context).colorScheme.primary,
                                  checkColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                  secondary: CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        AppColors.surfaceCard,
                                    backgroundImage: avatarUrl != null &&
                                            avatarUrl.isNotEmpty
                                        // ✅ P3 Fix: Ganti NetworkImage → CachedNetworkImageProvider
                                        ? CachedNetworkImageProvider(avatarUrl)
                                        : null,
                                    child: (avatarUrl == null ||
                                            avatarUrl.isEmpty)
                                        ? Icon(Icons.person,
                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                            size: 20)
                                        : null,
                                  ),
                                  title: Text(
                                    '@$username',
                                    style: AppTheme.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600),
                                  ),
                                );
                              },
                            ),
                    ),

                    // ── Done Button ─────────────────────────────────────
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _taggedUserIds = tempSelected.toList();
                            });
                            Navigator.pop(sheetContext);
                          },
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow:
                                  [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tempSelected.isEmpty
                                  ? 'Done'
                                  : 'Tag ${tempSelected.length} friend${tempSelected.length > 1 ? 's' : ''}',
                              style: AppTheme.orbitron(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final primaryGlowShadow = [
      BoxShadow(color: primaryColor.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Layer — Main Image
          // IgnorePointer agar tidak menyerap tap yang seharusnya ke chip di atasnya
          Positioned.fill(
            child: IgnorePointer(
              child: Image.file(currentMainImage, fit: BoxFit.cover),
            ),
          ),

          // 2. Front Image PiP (kiri atas)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isSwapped = !isSwapped;
                });
              },
              child: Container(
                width: 110,
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primaryColor,
                    width: 2,
                  ),
                  boxShadow: primaryGlowShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.isFrontMirrored && (!isSwapped)
                          ? Transform.scale(
                              scaleX: -1,
                              child:
                                  Image.file(currentPipImage, fit: BoxFit.cover),
                            )
                          : Image.file(currentPipImage, fit: BoxFit.cover),
                ),
              ),
            ),
          ),

          // 3. Tombol X (Batal / Retake) — kanan atas
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // 4. Bottom Zone: Gradient + Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 80,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Smart Chips Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSmartChip(
                          text: _musicChipLabel,
                          onTap: _showMusicBottomSheet,
                          isActive: _selectedMusic != null,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 8),
                        // Location Chip — GPS + API
                        _weatherLoading == true
                            ? _buildSmartChip(
                                text: '📍 Loading...',
                                isActive: false,
                                showLoader: true,
                                primaryColor: primaryColor,
                              )
                            : _buildSmartChip(
                                text: _locationChipLabel,
                                onTap: _isWeatherActive ? null : _onLocationChipTapped,
                                isActive: _isWeatherActive,
                                primaryColor: primaryColor,
                              ),
                        const SizedBox(width: 8),
                        // Visibility Chip — simpan lowercase ke DB
                        _buildSmartChip(
                          text: _visibilityLabel,
                          icon: _visibilityIcon,
                          onTap: _showPrivacyBottomSheet,
                          isActive: true,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 8),
                        // Tag Friends Chip — fungsional
                        _buildSmartChip(
                          text: _tagChipLabel,
                          icon: Icons.person_add_alt_1,
                          onTap: _showTagFriendsBottomSheet,
                          isActive: _taggedUserIds.isNotEmpty,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Caption Input
                  TextField(
                    controller: _captionController,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: 'Add a caption...',
                      hintStyle: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 24),

                  // Tombol POST
                  GestureDetector(
                    onTap: isUploading ? null : _uploadPost,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: primaryColor,
                          width: 2,
                        ),
                        boxShadow: primaryGlowShadow,
                      ),
                      alignment: Alignment.center,
                      child: isUploading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: primaryColor,
                                strokeWidth: 3,
                              ),
                            )
                          : Text(
                              'POST',
                              style: AppTheme.orbitron(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartChip({
    required String text,
    IconData? icon,
    VoidCallback? onTap,
    bool isActive = false,
    bool showLoader = false,
    required Color primaryColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: primaryColor.withValues(alpha: 0.3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? primaryColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? primaryColor.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLoader) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon,
                    color: isActive ? primaryColor : Colors.white,
                    size: 14),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  color: isActive ? primaryColor : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


