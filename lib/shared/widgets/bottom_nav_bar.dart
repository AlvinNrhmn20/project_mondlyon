// lib/shared/widgets/bottom_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/constants.dart';

// ─── Nav Item Model ───────────────────────────────────────────────────────────
class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isCamera = false,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isCamera;
}

// ─── Nav Items Definition ────────────────────────────────────────────────────
const List<_NavItem> _navItems = [
  _NavItem(
    icon: Icons.grid_view_outlined,
    activeIcon: Icons.grid_view_rounded,
    label: 'Feed',
  ),
  _NavItem(
    icon: Icons.search_rounded,
    activeIcon: Icons.manage_search_rounded,
    label: 'Discover',
  ),
  _NavItem(
    icon: Icons.crop_square_rounded,
    activeIcon: Icons.crop_square_rounded,
    label: 'Capture',
    isCamera: true,
  ),
  _NavItem(
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    label: 'Messages',
  ),
  _NavItem(
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

// ─── Widget ───────────────────────────────────────────────────────────────────
class SyncRealBottomNavBar extends StatelessWidget {
  const SyncRealBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadMessageCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessageCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final isActive = index == currentIndex;

            if (item.isCamera) {
              return _CameraButton(
                isActive: isActive,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onTap(index);
                },
              );
            }

            return _NavTile(
              item: item,
              isActive: isActive,
              unreadCount: index == 3 ? unreadMessageCount : 0,
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(index);
              },
            );
          }),
        ),
      ),
    );
  }
}

// ─── Regular Nav Tile ─────────────────────────────────────────────────────────
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.isActive,
    required this.onTap,
    this.unreadCount = 0,
  });

  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    Widget iconWidget = _GlowIcon(
      icon: isActive ? item.activeIcon : item.icon,
      isActive: isActive,
      size: 22,
    );

    if (unreadCount > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(8),
            decoration: isActive
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: primary.withValues(alpha: 0.12),
                  )
                : null,
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}

// ─── Camera (Primary Action) Button ──────────────────────────────────────────
class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? primary : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? primary : primary.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)]
                  : [BoxShadow(color: primary.withValues(alpha: 0.20), blurRadius: 10, spreadRadius: 0)],
            ),
            child: Icon(
              Icons.crop_square_rounded,
              color: isActive ? AppColors.black : primary,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Glow Icon ────────────────────────────────────────────────────────────────
class _GlowIcon extends StatelessWidget {
  const _GlowIcon({
    required this.icon,
    required this.isActive,
    this.size = 22,
  });

  final IconData icon;
  final bool isActive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = isActive ? primary : AppColors.textDisabled;

    if (!isActive) {
      return Icon(icon, color: color, size: size);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow bloom layer
        Icon(icon, color: primary.withValues(alpha: 0.35), size: size + 6),
        // Crisp icon on top
        Icon(icon, color: primary, size: size),
      ],
    );
  }
}
