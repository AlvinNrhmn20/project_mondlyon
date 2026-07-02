// lib/features/profile/memories_page.dart
//
// MemoriesPage — Menampilkan SEMUA postingan user dalam dua tampilan:
//   • Calendar View  (isCalendarView == true):  table_calendar dengan thumbnail
//     pada tanggal yang ada postingan, diurutkan terbaru.
//   • Grid View      (isCalendarView == false): GridView.builder 3 kolom penuh.
//
// Floating capsule toggle di bawah layar untuk berpindah tampilan.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';
import 'post_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MemoriesPage
// ─────────────────────────────────────────────────────────────────────────────

class MemoriesPage extends StatefulWidget {
  final String userId;
  const MemoriesPage({super.key, required this.userId});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage>
    with TickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  bool isCalendarView = true;
  bool _isLoading = true;

  List<Map<String, dynamic>> _allPosts = [];

  /// Map tanggal (tanpa jam) → daftar postingan pada tanggal tsb
  Map<DateTime, List<Map<String, dynamic>>> _postsByDay = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _toggleController;

  @override
  void initState() {
    super.initState();
    _toggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _selectedDay = _normalizeDate(DateTime.now());
    _fetchAllPosts();
  }

  @override
  void dispose() {
    _toggleController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  DateTime _normalizeDate(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day);

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchAllPosts() async {
    try {
      final data = await Supabase.instance.client
          .from('posts')
          .select('*')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);

      final posts = List<Map<String, dynamic>>.from(data as List<dynamic>);

      // Kelompokkan per-hari (UTC key agar konsisten dengan table_calendar)
      final Map<DateTime, List<Map<String, dynamic>>> byDay = {};
      for (final post in posts) {
        final raw = post['created_at']?.toString();
        if (raw == null) continue;
        final dt = DateTime.tryParse(raw);
        if (dt == null) continue;
        final key = _normalizeDate(dt.toLocal());
        byDay.putIfAbsent(key, () => []).add(post);
      }

      if (mounted) {
        setState(() {
          _allPosts = posts;
          _postsByDay = byDay;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MemoriesPage fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Events provider (untuk table_calendar) ────────────────────────────────

  List<Map<String, dynamic>> _getPostsForDay(DateTime day) {
    return _postsByDay[_normalizeDate(day)] ?? [];
  }

  // ── Toggle view ───────────────────────────────────────────────────────────

  void _switchView(bool toCalendar) {
    if (isCalendarView == toCalendar) return;
    setState(() => isCalendarView = toCalendar);
    if (toCalendar) {
      _toggleController.reverse();
    } else {
      _toggleController.forward();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'MEMORIES',
          style: AppTheme.orbitron(
              fontSize: 13, color: AppColors.textPrimary, letterSpacing: 4),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary))
          : Stack(
              children: [
                // ── Main content ───────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: isCalendarView
                      ? _CalendarView(
                          key: const ValueKey('calendar'),
                          postsByDay: _postsByDay,
                          focusedDay: _focusedDay,
                          selectedDay: _selectedDay,
                          getPostsForDay: _getPostsForDay,
                          onDaySelected: (selected, focused) {
                            setState(() {
                              _selectedDay = selected;
                              _focusedDay = focused;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            setState(() => _focusedDay = focusedDay);
                          },
                        )
                      : _GridView(
                          key: const ValueKey('grid'),
                          posts: _allPosts,
                        ),
                ),

                // ── Floating toggle capsule ─────────────────────────────────
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _FloatingToggle(
                      isCalendarView: isCalendarView,
                      neonColor: neon,
                      onCalendarTap: () => _switchView(true),
                      onGridTap: () => _switchView(false),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CalendarView
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    super.key,
    required this.postsByDay,
    required this.focusedDay,
    required this.selectedDay,
    required this.getPostsForDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final Map<DateTime, List<Map<String, dynamic>>> postsByDay;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<Map<String, dynamic>> Function(DateTime) getPostsForDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final neon = Theme.of(context).colorScheme.primary;

    // Posts untuk hari yang dipilih — ditampilkan di bawah kalender
    final selectedPosts = selectedDay != null
        ? (postsByDay[selectedDay] ?? [])
        : <Map<String, dynamic>>[];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Calendar ─────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: neon.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: neon.withValues(alpha: 0.08),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: TableCalendar<Map<String, dynamic>>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: focusedDay,
                selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                eventLoader: getPostsForDay,
                onDaySelected: onDaySelected,
                onPageChanged: onPageChanged,

                // ── Calendar Style ──
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  todayDecoration: BoxDecoration(
                    color: neon.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: neon, width: 1.5),
                  ),
                  todayTextStyle: AppTheme.orbitron(
                      fontSize: 12,
                      color: neon,
                      fontWeight: FontWeight.w700),
                  selectedDecoration: BoxDecoration(
                    color: neon.withValues(alpha: 0.30),
                    shape: BoxShape.circle,
                    border: Border.all(color: neon, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: neon.withValues(alpha: 0.55),
                          blurRadius: 10,
                          spreadRadius: 1),
                    ],
                  ),
                  selectedTextStyle: AppTheme.orbitron(
                      fontSize: 12,
                      color: neon,
                      fontWeight: FontWeight.w900),
                  defaultTextStyle: AppTheme.inter(
                      fontSize: 12, color: AppColors.textSecondary),
                  weekendTextStyle: AppTheme.inter(
                      fontSize: 12, color: AppColors.textSecondary),
                  disabledTextStyle: AppTheme.inter(
                      fontSize: 12,
                      color: AppColors.textDisabled.withValues(alpha: 0.4)),
                  // Sembunyikan marker dot default (kita pakai calendarBuilders)
                  markerDecoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                ),

                // ── Header style ──
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: AppTheme.orbitron(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2),
                  leftChevronIcon: Icon(Icons.chevron_left_rounded,
                      color: neon, size: 24),
                  rightChevronIcon: Icon(Icons.chevron_right_rounded,
                      color: neon, size: 24),
                  headerPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),

                // ── Days of week style ──
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: AppTheme.orbitron(
                      fontSize: 9,
                      color: AppColors.textDisabled,
                      letterSpacing: 1),
                  weekendStyle: AppTheme.orbitron(
                      fontSize: 9,
                      color: AppColors.textDisabled,
                      letterSpacing: 1),
                ),

                // ── Custom day builder: ganti angka tanggal dengan thumbnail ──
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    return _buildDayCell(
                        context, day, neon, isSelected: false, isToday: false);
                  },
                  todayBuilder: (context, day, focusedDay) {
                    return _buildDayCell(
                        context, day, neon, isSelected: false, isToday: true);
                  },
                  selectedBuilder: (context, day, focusedDay) {
                    return _buildDayCell(
                        context, day, neon, isSelected: true, isToday: false);
                  },
                  outsideBuilder: (context, day, focusedDay) {
                    return Center(
                      child: Text(
                        '${day.day}',
                        style: AppTheme.inter(
                            fontSize: 12,
                            color: AppColors.textDisabled
                                .withValues(alpha: 0.3)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // ── Gap ─────────────────────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Selected day posts header ────────────────────────────────────────
        if (selectedDay != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: neon,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                            color: neon.withValues(alpha: 0.6),
                            blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    selectedPosts.isEmpty
                        ? 'NO MOMENTS THIS DAY'
                        : '${selectedPosts.length} MOMENT${selectedPosts.length > 1 ? 'S' : ''}',
                    style: AppTheme.orbitron(
                        fontSize: 10,
                        color: selectedPosts.isEmpty
                            ? AppColors.textDisabled
                            : AppColors.textPrimary,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── Selected day grid ───────────────────────────────────────────────
        if (selectedPosts.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _MemoryThumbnail(post: selectedPosts[i]),
                childCount: selectedPosts.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
            ),
          ),

        // ── Bottom safe-area padding for floating toggle ─────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  // ── Custom day cell builder ────────────────────────────────────────────────

  Widget _buildDayCell(
    BuildContext context,
    DateTime day,
    Color neon, {
    required bool isSelected,
    required bool isToday,
  }) {
    final posts = getPostsForDay(day);
    final hasPosts = posts.isNotEmpty;
    final thumbUrl = hasPosts
        ? (posts.first['back_video_url']?.toString() ??
            posts.first['front_video_url']?.toString())
        : null;

    Widget content;

    if (hasPosts && thumbUrl != null && thumbUrl.isNotEmpty) {
      // ── Thumbnail kotak kecil menggantikan angka tanggal ──
      content = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: thumbUrl,
              fit: BoxFit.cover,
              placeholder: (ctx, url) => Container(
                  color: AppColors.surfaceElevated),
              errorWidget: (ctx, url, err) => Container(
                color: AppColors.surfaceCard,
                child: Center(
                  child: Text('${day.day}',
                      style: AppTheme.orbitron(
                          fontSize: 10, color: AppColors.textDisabled)),
                ),
              ),
            ),
            // overlay gelap tipis agar nomor hari terbaca
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            // Nomor hari di atas gambar
            Positioned(
              bottom: 2,
              right: 4,
              child: Text(
                '${day.day}',
                style: AppTheme.orbitron(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // Border highlight jika selected / today
            if (isSelected || isToday)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? neon
                        : neon.withValues(alpha: 0.5),
                    width: isSelected ? 2 : 1.5,
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // ── Angka tanggal biasa ──
      content = Center(
        child: Text(
          '${day.day}',
          style: AppTheme.orbitron(
            fontSize: 12,
            color: isSelected
                ? neon
                : isToday
                    ? neon.withValues(alpha: 0.85)
                    : AppColors.textSecondary,
            fontWeight: isSelected || isToday
                ? FontWeight.w700
                : FontWeight.w400,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isSelected
              ? neon.withValues(alpha: 0.10)
              : isToday
                  ? neon.withValues(alpha: 0.05)
                  : Colors.transparent,
          border: (!hasPosts && isSelected)
              ? Border.all(color: neon, width: 1.5)
              : (!hasPosts && isToday)
                  ? Border.all(
                      color: neon.withValues(alpha: 0.40), width: 1)
                  : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: neon.withValues(alpha: 0.30),
                      blurRadius: 8,
                      spreadRadius: 1),
                ]
              : null,
        ),
        child: content,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GridView   — GridView.builder seluruh postingan (3 kolom)
// ─────────────────────────────────────────────────────────────────────────────

class _GridView extends StatelessWidget {
  const _GridView({super.key, required this.posts});
  final List<Map<String, dynamic>> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'NO MOMENTS IN THE VOID',
          style: AppTheme.orbitron(
              fontSize: 13,
              color: AppColors.textDisabled.withValues(alpha: 0.5),
              letterSpacing: 2,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 120),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: posts.length,
      itemBuilder: (context, i) => _MemoryThumbnail(post: posts[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemoryThumbnail   — satu tile foto persegi
// ─────────────────────────────────────────────────────────────────────────────

class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final url = post['back_video_url']?.toString() ??
        post['front_video_url']?.toString() ??
        '';
    final neon = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => PostDetailPage(post: post)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          border: Border.all(
            color: neon.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (ctx, _) =>
                    Container(color: AppColors.surfaceElevated),
                errorWidget: (ctx, _, __) => Container(
                  color: AppColors.surfaceCard,
                  child: const Center(
                    child: Icon(Icons.broken_image,
                        color: AppColors.textDisabled, size: 20),
                  ),
                ),
              )
            : Container(
                color: AppColors.surfaceCard,
                child: const Center(
                  child: Icon(Icons.image_not_supported,
                      color: AppColors.textDisabled, size: 20),
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FloatingToggle   — kapsul floating di bawah layar
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingToggle extends StatelessWidget {
  const _FloatingToggle({
    required this.isCalendarView,
    required this.neonColor,
    required this.onCalendarTap,
    required this.onGridTap,
  });

  final bool isCalendarView;
  final Color neonColor;
  final VoidCallback onCalendarTap;
  final VoidCallback onGridTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: neonColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: neonColor.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.60),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Calendar tab ──
          _ToggleTab(
            icon: LucideIcons.calendarDays,
            label: 'CALENDAR',
            isActive: isCalendarView,
            neonColor: neonColor,
            onTap: onCalendarTap,
          ),
          const SizedBox(width: 4),
          // ── Grid tab ──
          _ToggleTab(
            icon: LucideIcons.grid3x3,
            label: 'GRID',
            isActive: !isCalendarView,
            neonColor: neonColor,
            onTap: onGridTap,
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.neonColor,
    required this.onTap,
  });

  final LucideIconData icon;
  final String label;
  final bool isActive;
  final Color neonColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? neonColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          border: isActive
              ? Border.all(
                  color: neonColor.withValues(alpha: 0.70),
                  width: 1.5,
                )
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: neonColor.withValues(alpha: 0.40),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LucideIcon(
              icon: icon,
              color: isActive ? neonColor : AppColors.textDisabled,
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppTheme.orbitron(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isActive ? neonColor : AppColors.textDisabled,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
