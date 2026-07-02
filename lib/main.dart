import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Import Constants & Theme
import 'core/constants/constants.dart';
import 'core/theme/theme_controller.dart';
import 'core/services/sync_timer_controller.dart';

// Import Fitur
import 'features/home/home_page.dart';
import 'features/search/search_page.dart';
import 'features/camera/camera_page.dart';
import 'features/message/message_page.dart';
import 'features/profile/profile_page.dart';
import 'features/auth/auth_gate.dart';

// Import Widgets
import 'shared/widgets/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox('theme_prefs');

  // ✅ FIXED: Load environment variables dari .env (tidak ter-commit ke Git)
  await dotenv.load(fileName: '.env');

  // Inisialisasi Supabase menggunakan kredensial dari .env
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: SyncRealApp()));
}

class SyncRealApp extends ConsumerWidget {
  const SyncRealApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(themeProvider);

    return MaterialApp(
      title: 'SyncReal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(primaryColor),
      home: const AuthGate(),
    );
  }
}

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;
  int _unreadMessageCount = 0;
  RealtimeChannel? _badgeChannel;
  late final String? _myId;
  final _supabase = Supabase.instance.client;

  final List<Widget> _pages = [
    const HomePage(),
    const SearchPage(),
    const SizedBox.shrink(), // Placeholder for camera button
    const MessagePage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    if (_myId != null) {
      _fetchUnreadCount();
      _badgeChannel = _supabase
          .channel('badge_unread_$_myId')
        ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            callback: (_) => _fetchUnreadCount(),
          )
        ..subscribe();
    }
  }

  // ── Badge: hitung unread HANYA dari friends ─────────────────────────────
  Future<void> _fetchUnreadCount() async {
    try {
      final myId = _myId;
      if (myId == null) return;

      // 1) Ambil daftar friend IDs dari connections
      final connections = await _supabase
          .from('connections')
          .select('sender_id, receiver_id')
          .eq('status', 'friends')
          .or('sender_id.eq.$myId,receiver_id.eq.$myId');

      final friendIds = connections
          .map((c) => c['sender_id'] == myId ? c['receiver_id'] : c['sender_id'])
          .toSet()
          .toList();

      if (friendIds.isEmpty) {
        if (mounted) setState(() => _unreadMessageCount = 0);
        return;
      }

      // 2) Hitung unread hanya dari friends
      final unread = await _supabase
          .from('messages')
          .select('id')
          .eq('receiver_id', myId)
          .eq('is_read', false)
          .inFilter('sender_id', friendIds);

      if (mounted) {
        setState(() => _unreadMessageCount = (unread as List).length);
      }
    } catch (e) {
      debugPrint('[Badge] Error fetching unread count: $e');
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _badgeChannel?.unsubscribe();
    super.dispose();
  }

  // ── FOMO Gatekeeper Logic ─────────────────────────────────────────────────

  Future<void> _onCameraButtonTapped() async {
    final timerState = ref.read(syncTimerProvider);

    switch (timerState.status) {
      // ── LOCKED: window sudah habis untuk hari ini ──
      case SyncWindowStatus.locked:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.lock_clock, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your window is closed for today. See you tomorrow! 🌙',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surfaceCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
        break;

      // ── READY: belum buka jendela hari ini → konfirmasi dulu ──
      case SyncWindowStatus.ready:
        if (!mounted) return;
        _showStartWindowDialog();
        break;

      // ── ACTIVE: jendela terbuka → langsung ke kamera ──
      case SyncWindowStatus.active:
        _navigateToCamera();
        break;
    }
  }

  void _showStartWindowDialog() {
    final primary = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: primary.withValues(alpha: 0.5), width: 1.2),
        ),
        title: Text(
          '⚡ START SYNC WINDOW?',
          style: AppTheme.orbitron(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: primary,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          'You have 1 hour to capture and post your moment.\n\nThe clock starts NOW and cannot be paused. Are you ready?',
          style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Not Yet', style: AppTheme.inter(color: AppColors.textDisabled)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Buka jendela baru di Supabase
              await ref.read(syncTimerProvider.notifier).openWindow();
              // Navigasi ke kamera
              if (mounted) _navigateToCamera();
            },
            child: Text(
              "LET'S GO ⚡",
              style: AppTheme.orbitron(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCamera() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (context) => const CameraPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SyncRealBottomNavBar(
        currentIndex: _currentIndex,
        unreadMessageCount: _unreadMessageCount,
        onTap: (index) {
          if (index == 2) {
            HapticFeedback.mediumImpact();
            _onCameraButtonTapped();
          } else {
            setState(() {
              _currentIndex = index;
            });
          }
        },
      ),
    );
  }
}
