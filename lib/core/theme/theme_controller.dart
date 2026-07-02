import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Presets
const Color cyberPurple = Color(0xFFBC13FE);
const Color laserCyan = Color(0xFF00F5FF);
const Color toxicGreen = Color(0xFF39FF14);

class ThemeController extends StateNotifier<Color> {
  ThemeController() : super(cyberPurple) {
    _loadTheme();
  }

  static const _boxName = 'theme_prefs';
  static const _colorKey = 'neon_color';

  Future<void> _loadTheme() async {
    final box = await Hive.openBox(_boxName);
    final colorValue = box.get(_colorKey);
    if (colorValue != null) {
      state = Color(colorValue);
    }
  }

  Future<void> setNeonColor(Color color) async {
    state = color;
    final box = await Hive.openBox(_boxName);
    await box.put(_colorKey, color.toARGB32());
  }
}

final themeProvider = StateNotifierProvider<ThemeController, Color>((ref) {
  return ThemeController();
});
