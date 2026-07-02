// lib/shared/widgets/neon_widgets.dart
//
// Reusable neon-themed widgets for SyncReal.
//
// Public exports:
//   NeonOutlineButton  — ghost button with neon border + Lucide icon
//   NeonChip           — pill tag with glowing neon dot
//   SectionLabel       — icon + all-caps label + gradient rule
//   NeonDivider        — centred gradient horizontal rule
//   NeonCard           — dark surface card with optional neon glow border
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NeonCard
// ─────────────────────────────────────────────────────────────────────────────

/// Dark surface card built on [AppColors.surfaceCard].
///
/// When [accentColor] is provided the border and outer glow use that colour,
/// making the card feel "electrified".  Without it the border falls back to
/// the neutral [AppColors.divider].
///
/// ```dart
/// NeonCard(
///   accentColor: Theme.of(context).colorScheme.primary,
///   padding: EdgeInsets.all(18),
///   child: Text('Content'),
/// )
/// ```
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16.0,
    this.borderOpacity = 0.45,
    this.glowOpacity = 0.08,
    this.width,
    this.height,
  });

  final Widget child;

  /// Optional neon accent for border + outer glow.
  final Color? accentColor;

  final EdgeInsets padding;
  final double borderRadius;

  /// Opacity of the accent border (0.0–1.0). Ignored when [accentColor] is null.
  final double borderOpacity;

  /// Opacity of the outer glow [BoxShadow] (0.0–1.0).
  final double glowOpacity;

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final borderColor = accentColor != null
        ? accentColor!.withValues(alpha: borderOpacity)
        : AppColors.divider;

    return Container(
      width: width,
      height: height,
      // Tambahkan clipBehavior di sini
      clipBehavior: Clip.antiAlias, 
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: accentColor != null
            ? [
                BoxShadow(
                  color: accentColor!.withValues(alpha: glowOpacity),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeonOutlineButton
// ─────────────────────────────────────────────────────────────────────────────

/// Ghost button: neon border + tinted fill + leading [LucideIcon].
///
/// ```dart
/// NeonOutlineButton(
///   label: 'EDIT PROFILE',
///   icon: LucideIcons.pencil,
///   onTap: () {},                         // defaults to Theme primary
/// )
/// NeonOutlineButton(
///   label: 'ADD HOBBIES',
///   icon: LucideIcons.plus,
///   onTap: () {},
///   color: AppColors.neonCyan,
/// )
/// ```
class NeonOutlineButton extends StatelessWidget {
  const NeonOutlineButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
    this.iconSize = 14.0,
    this.fontSize = 9.0,
    this.letterSpacing = 2.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final String label;
  final LucideIconData icon;
  final VoidCallback onTap;
  final Color? color;
  final double iconSize;
  final double fontSize;
  final double letterSpacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.50), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LucideIcon(icon: icon, color: effectiveColor, size: iconSize),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.orbitron(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
                letterSpacing: letterSpacing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeonChip
// ─────────────────────────────────────────────────────────────────────────────

/// Pill-shaped tag: glowing neon dot + Orbitron all-caps label.
///
/// ```dart
/// NeonChip(label: 'Skateboarding')
/// NeonChip(label: 'Photography',   color: AppColors.neonCyan,   onTap: () {})
/// ```
class NeonChip extends StatelessWidget {
  const NeonChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
    this.fontSize = 9.0,
    this.dotSize = 6.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final double fontSize;
  final double dotSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap != null
          ? () { HapticFeedback.selectionClick(); onTap!(); }
          : null,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.60), width: 1),
          boxShadow: [
            BoxShadow(color: effectiveColor.withValues(alpha: 0.15), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: effectiveColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: effectiveColor.withValues(alpha: 0.70), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label.toUpperCase(),
              style: AppTheme.orbitron(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionLabel
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal section header: [icon] + all-caps [label] + gradient rule.
///
/// ```dart
/// SectionLabel(
///   label: 'YOUR IMPACT',
///   icon: LucideIcons.barChart2,
/// )
/// ```
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.label,
    required this.icon,
    this.accentColor,
    this.iconSize = 16.0,
    this.fontSize = 10.0,
    this.letterSpacing = 3.0,
  });

  final String label;
  final LucideIconData icon;
  final Color? accentColor;
  final double iconSize;
  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = accentColor ?? Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        LucideIcon(icon: icon, color: effectiveColor, size: iconSize),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.orbitron(
            fontSize: fontSize,
            color: AppColors.textSecondary,
            letterSpacing: letterSpacing,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                effectiveColor.withValues(alpha: 0.40),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeonDivider
// ─────────────────────────────────────────────────────────────────────────────

/// 1 px full-width horizontal rule with a centred neon purple bloom.
class NeonDivider extends StatelessWidget {
  const NeonDivider({super.key, this.margin});
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final primaryDim = primary.withValues(alpha: 0.5);

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.transparent,
          primaryDim,
          primary,
          primaryDim,
          Colors.transparent,
        ]),
      ),
    );
  }
}
