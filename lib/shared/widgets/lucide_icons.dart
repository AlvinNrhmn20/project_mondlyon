// lib/shared/widgets/lucide_icons.dart
//
// Self-contained Lucide icon system for SyncReal.
// All classes are PUBLIC (no leading _) so they can be imported from any file.
//
// Usage:
//   import 'package:syncreal/shared/widgets/lucide_icons.dart';
//   LucideIcon(icon: LucideIcons.flame, color: AppColors.neonPurple, size: 24)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:syncreal/core/constants/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LucideIconData
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the raw SVG `d` path string for one Lucide icon (24×24 viewBox).
class LucideIconData {
  const LucideIconData(this.pathData);
  final String pathData;
}

// ─────────────────────────────────────────────────────────────────────────────
// LucideIcons  — static icon registry (all public)
// ─────────────────────────────────────────────────────────────────────────────

abstract final class LucideIcons {
  // ── Navigation ──────────────────────────────────────────────────────────────
  static const LucideIconData settings = LucideIconData(
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'
    'M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06'
    'a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09'
    'A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83'
    'l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09'
    'A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83'
    'l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09'
    'a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83'
    'l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09'
    'a1.65 1.65 0 0 0-1.51 1z',
  );

  static const LucideIconData share = LucideIconData(
    'M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8'
    'M16 6l-4-4-4 4'
    'M12 2v13',
  );

  static const LucideIconData search = LucideIconData(
    'M21 21l-4.35-4.35'
    'M17 11A6 6 0 1 1 5 11a6 6 0 0 1 12 0z',
  );

  static const LucideIconData bell = LucideIconData(
    'M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9'
    'M13.73 21a2 2 0 0 1-3.46 0',
  );

  static const LucideIconData home = LucideIconData(
    'M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'
    'M9 22V12h6v10',
  );

  static const LucideIconData user = LucideIconData(
    'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2'
    'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  );

  static const LucideIconData messageCircle = LucideIconData(
    'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z',
  );

  // ── Actions ──────────────────────────────────────────────────────────────────
  static const LucideIconData plus = LucideIconData('M12 5v14M5 12h14');

  static const LucideIconData pencil = LucideIconData(
    'M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z',
  );

  static const LucideIconData trash2 = LucideIconData(
    'M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6'
    'M10 11v6M14 11v6'
    'M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2',
  );

  static const LucideIconData send = LucideIconData(
    'M22 2L11 13'
    'M22 2L15 22l-4-9-9-4 20-7z',
  );

  static const LucideIconData upload = LucideIconData(
    'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'
    'M17 8l-5-5-5 5'
    'M12 3v12',
  );

  static const LucideIconData camera = LucideIconData(
    'M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8'
    'a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'
    'M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  );

  static const LucideIconData x = LucideIconData('M18 6L6 18M6 6l12 12');

  static const LucideIconData moreHorizontal = LucideIconData(
    'M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z'
    'M19 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z'
    'M5 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',
  );

  static const LucideIconData chevronRight = LucideIconData('M9 18l6-6-6-6');
  static const LucideIconData chevronDown  = LucideIconData('M6 9l6 6 6-6');
  static const LucideIconData check = LucideIconData('M20 6L9 17l-5-5');
  static const LucideIconData info = LucideIconData('M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10zM12 16v-4M12 8h.01');

  // ── Media ────────────────────────────────────────────────────────────────────
  static const LucideIconData play = LucideIconData('M5 3l14 9-14 9V3z');

  static const LucideIconData bookmark = LucideIconData(
    'M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z',
  );

  static const LucideIconData image = LucideIconData(
    'M21 19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z'
    'M8.5 13.5l2.5-3 2.5 3M14 13l2 2.5M8.5 8.5h.01',
  );

  // ── Analytics / Status ───────────────────────────────────────────────────────
  static const LucideIconData barChart2 = LucideIconData(
    'M18 20V10M12 20V4M6 20v-6',
  );

  static const LucideIconData trendingUp = LucideIconData(
    'M23 6l-9.5 9.5-5-5L1 18'
    'M17 6h6v6',
  );

  static const LucideIconData activity = LucideIconData(
    'M22 12h-4l-3 9L9 3l-3 9H2',
  );

  static const LucideIconData zap = LucideIconData(
    'M13 2L3 14h9l-1 8 10-12h-9l1-8z',
  );

  static const LucideIconData flame = LucideIconData(
    'M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3'
    '-1.072-2.143-.224-4.054 2-6'
    ' .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0'
    'c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z',
  );

  static const LucideIconData trophy = LucideIconData(
    'M6 9H3.5a2.5 2.5 0 0 1 0-5H6'
    'M18 9h2.5a2.5 2.5 0 0 0 0-5H18'
    'M4 22h16'
    'M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22'
    'M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22'
    'M18 2H6v7a6 6 0 0 0 12 0V2z',
  );

  static const LucideIconData sparkles = LucideIconData(
    'M12 3L9.5 9.5 3 12l6.5 2.5L12 21l2.5-6.5L21 12l-6.5-2.5L12 3z'
    'M5 3v4M3 5h4M19 17v4M17 19h4',
  );

  static const LucideIconData heart = LucideIconData(
    'M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06'
    'a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06'
    'a5.5 5.5 0 0 0 0-7.78z',
  );

  static const LucideIconData star = LucideIconData(
    'M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77'
    'l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z',
  );

  // ── Layout ───────────────────────────────────────────────────────────────────
  static const LucideIconData grid = LucideIconData(
    'M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z',
  );

  /// 3×3 grid layout icon (used in MemoriesPage toggle)
  static const LucideIconData grid3x3 = LucideIconData(
    'M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18',
  );

  static const LucideIconData sliders = LucideIconData(
    'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3'
    'M1 14h6M9 8h6M17 16h6',
  );

  static const LucideIconData timer = LucideIconData(
    'M12 20a8 8 0 1 0 0-16 8 8 0 0 0 0 16z'
    'M12 12V8'
    'M12 2v2M4.93 4.93l1.41 1.41',
  );

  /// Calendar with days indicator (used in Profile AppBar & MemoriesPage toggle)
  static const LucideIconData calendarDays = LucideIconData(
    'M8 2v4M16 2v4'
    'M3 10h18'
    'M3 6a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6z'
    'M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01',
  );

  /// User plus — add friend icon (used in Profile AppBar)
  static const LucideIconData userPlus = LucideIconData(
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'
    'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z'
    'M19 8v6M22 11h-6',
  );

  /// Map pin — location icon (used in Edit Profile)
  static const LucideIconData mapPin = LucideIconData(
    'M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z'
    'M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  );

  /// Briefcase — work icon (used in Edit Profile)
  static const LucideIconData briefcase = LucideIconData(
    'M20 7H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2z'
    'M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2'
    'M12 12v4M8 12v4M16 12v4',
  );

  /// Book open — education icon (used in Edit Profile)
  static const LucideIconData bookOpen = LucideIconData(
    'M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z'
    'M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z',
  );

  /// Link — hyperlink icon (used in Edit Profile)
  static const LucideIconData link = LucideIconData(
    'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71'
    'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LucideIcon  — the renderable widget
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a [LucideIconData] path via [CustomPaint].
/// Scales the canonical 24×24 Lucide viewBox to [size]×[size] pixels.
class LucideIcon extends StatelessWidget {
  const LucideIcon({
    super.key,
    required this.icon,
    this.color = AppColors.textSecondary,
    this.size = 22,
    this.strokeWidth = 2.0,
  });

  final LucideIconData icon;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: LucideIconPainter(
          pathData: icon.pathData,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LucideIconPainter  — public CustomPainter (no leading _)
// ─────────────────────────────────────────────────────────────────────────────

class LucideIconPainter extends CustomPainter {
  const LucideIconPainter({
    required this.pathData,
    required this.color,
    this.strokeWidth = 2.0,
  });

  final String pathData;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_parseSvgPath(pathData), paint);
  }

  Path _parseSvgPath(String d) {
    final path = Path();
    final re = RegExp(r'([MLHVCSQTAZmlhvcsqtaz])([^MLHVCSQTAZmlhvcsqtaz]*)');

    double cx = 0, cy = 0;
    double? lastCPx, lastCPy;

    for (final m in re.allMatches(d)) {
      final cmd = m.group(1)!;
      final raw = m.group(2)!.trim();
      final args = RegExp(r'-?\d*\.?\d+')
          .allMatches(raw)
          .map((match) => double.parse(match.group(0)!))
          .toList(); 

      switch (cmd) {
        case 'M':
          for (var i = 0; i < args.length; i += 2) {
            cx = args[i]; cy = args[i + 1];
            i == 0 ? path.moveTo(cx, cy) : path.lineTo(cx, cy);
          }
        case 'm':
          for (var i = 0; i < args.length; i += 2) {
            cx += args[i]; cy += args[i + 1];
            i == 0 ? path.moveTo(cx, cy) : path.lineTo(cx, cy);
          }
        case 'L':
          for (var i = 0; i < args.length; i += 2) { cx = args[i]; cy = args[i + 1]; path.lineTo(cx, cy); }
        case 'l':
          for (var i = 0; i < args.length; i += 2) { cx += args[i]; cy += args[i + 1]; path.lineTo(cx, cy); }
        case 'H':
          for (final x in args) { cx = x; path.lineTo(cx, cy); }
        case 'h':
          for (final dx in args) { cx += dx; path.lineTo(cx, cy); }
        case 'V':
          for (final y in args) { cy = y; path.lineTo(cx, cy); }
        case 'v':
          for (final dy in args) { cy += dy; path.lineTo(cx, cy); }
        case 'C':
          for (var i = 0; i < args.length; i += 6) {
            final cpx2 = args[i + 2], cpy2 = args[i + 3];
            path.cubicTo(args[i], args[i + 1], cpx2, cpy2, args[i + 4], args[i + 5]);
            lastCPx = cpx2; lastCPy = cpy2; cx = args[i + 4]; cy = args[i + 5];
          }
        case 'c':
          for (var i = 0; i < args.length; i += 6) {
            final x1 = cx + args[i], y1 = cy + args[i + 1];
            final x2 = cx + args[i + 2], y2 = cy + args[i + 3];
            final x = cx + args[i + 4], y = cy + args[i + 5];
            path.cubicTo(x1, y1, x2, y2, x, y);
            lastCPx = x2; lastCPy = y2; cx = x; cy = y;
          }
        case 'S':
          for (var i = 0; i < args.length; i += 4) {
            final rx = lastCPx != null ? 2 * cx - lastCPx : cx;
            final ry = lastCPy != null ? 2 * cy - lastCPy : cy;
            final x2 = args[i], y2 = args[i + 1], x = args[i + 2], y = args[i + 3];
            path.cubicTo(rx, ry, x2, y2, x, y);
            lastCPx = x2; lastCPy = y2; cx = x; cy = y;
          }
        case 's':
          for (var i = 0; i < args.length; i += 4) {
            final rx = lastCPx != null ? 2 * cx - lastCPx : cx;
            final ry = lastCPy != null ? 2 * cy - lastCPy : cy;
            final x2 = cx + args[i], y2 = cy + args[i + 1];
            final x = cx + args[i + 2], y = cy + args[i + 3];
            path.cubicTo(rx, ry, x2, y2, x, y);
            lastCPx = x2; lastCPy = y2; cx = x; cy = y;
          }
        case 'Q':
          for (var i = 0; i < args.length; i += 4) {
            path.quadraticBezierTo(args[i], args[i + 1], args[i + 2], args[i + 3]);
            cx = args[i + 2]; cy = args[i + 3];
          }
        case 'q':
          for (var i = 0; i < args.length; i += 4) {
            path.quadraticBezierTo(cx + args[i], cy + args[i + 1], cx + args[i + 2], cy + args[i + 3]);
            cx += args[i + 2]; cy += args[i + 3];
          }
        case 'A':
          for (var i = 0; i < args.length; i += 7) {
            _addArc(path, cx, cy, args[i], args[i + 1], args[i + 2], args[i + 3] == 1, args[i + 4] == 1, args[i + 5], args[i + 6]);
            cx = args[i + 5]; cy = args[i + 6];
          }
        case 'a':
          for (var i = 0; i < args.length; i += 7) {
            final ex = cx + args[i + 5], ey = cy + args[i + 6];
            _addArc(path, cx, cy, args[i], args[i + 1], args[i + 2], args[i + 3] == 1, args[i + 4] == 1, ex, ey);
            cx = ex; cy = ey;
          }
        case 'Z':
        case 'z':
          path.close();
      }
      if (!{'C', 'c', 'S', 's'}.contains(cmd)) { lastCPx = null; lastCPy = null; }
    }
    return path;
  }

  void _addArc(Path path, double x1, double y1, double rx, double ry,
      double xRotation, bool largeArc, bool sweep, double x2, double y2) {
    if (rx == 0 || ry == 0) { path.lineTo(x2, y2); return; }
    final phi = xRotation * math.pi / 180;
    final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
    final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;
    var rxSq = rx * rx, rySq = ry * ry;
    final x1pSq = x1p * x1p, y1pSq = y1p * y1p;
    final lambda = x1pSq / rxSq + y1pSq / rySq;
    if (lambda > 1) { final s = math.sqrt(lambda); rx *= s; ry *= s; rxSq = rx * rx; rySq = ry * ry; }
    final num = math.max(0.0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq);
    final den = rxSq * y1pSq + rySq * x1pSq;
    final sq = den == 0 ? 0.0 : math.sqrt(num / den);
    final sign = (largeArc == sweep) ? -1.0 : 1.0;
    final cxp = sign * sq * (rx * y1p / ry);
    final cyp = sign * sq * -(ry * x1p / rx);
    final cx0 = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
    final cy0 = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;
    double angle(double ux, double uy, double vx, double vy) {
      final d = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      if (d == 0) return 0;
      final a = math.acos(((ux * vx + uy * vy) / d).clamp(-1.0, 1.0));
      return (ux * vy - uy * vx < 0) ? -a : a;
    }
    final startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var dAngle = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if (!sweep && dAngle > 0) dAngle -= 2 * math.pi;
    if (sweep && dAngle < 0) dAngle += 2 * math.pi;
    path.addArc(Rect.fromCenter(center: Offset(cx0, cy0), width: rx * 2, height: ry * 2), startAngle, dAngle);
  }

  @override
  bool shouldRepaint(LucideIconPainter old) =>
      old.pathData != pathData || old.color != color || old.strokeWidth != strokeWidth;
}