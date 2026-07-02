import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/core/theme/theme_controller.dart';
import 'package:syncreal/core/services/sync_timer_controller.dart';
import 'package:syncreal/features/auth/login_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _supabase = Supabase.instance.client;

  // ── Preference State ────────────────────────────────────────────────────
  bool _isPrivate = false;
  bool _notificationsEnabled = true;
  bool _stealthMode = false;
  bool _isLoadingPrefs = true;
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchPreferences();
  }

  Future<void> _fetchPreferences() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await _supabase
          .from('profiles')
          .select('is_private, notifications_enabled, stealth_mode')
          .eq('id', userId)
          .single();

      if (mounted) {
        setState(() {
          _isPrivate = data['is_private'] as bool? ?? false;
          _notificationsEnabled = data['notifications_enabled'] as bool? ?? true;
          _stealthMode = data['stealth_mode'] as bool? ?? false;
          _isLoadingPrefs = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching preferences: $e');
      if (mounted) setState(() => _isLoadingPrefs = false);
    }
  }

  Future<void> _updatePreference(String column, bool value) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('profiles')
          .update({column: value})
          .eq('id', userId);
    } catch (e) {
      debugPrint('Error updating $column: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update setting: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleChangePassword() async {
    final user = _supabase.auth.currentUser;
    if (user?.email == null) return;

    try {
      await _supabase.auth.resetPasswordForEmail(user!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset link sent to ${user.email}!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending reset email: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reset email: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Are you sure you want to log out?',
            style: AppTheme.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTheme.inter(color: AppColors.textDisabled)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Yes', style: AppTheme.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _supabase.auth.signOut();
    
    // 🔥 PEMBERSIHAN STATE (Mencegah Ghost State)
    ref.invalidate(syncTimerProvider);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  void _showComingSoonSnackBar(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — Coming Soon! 🚀'),
        backgroundColor: AppColors.surfaceCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          'SETTINGS',
          style: AppTheme.orbitron(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 4,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _isLoadingPrefs
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                const SizedBox(height: 8),

                // ── ACCOUNT & SECURITY ─────────────────────────────────────
                _buildSectionHeader('ACCOUNT & SECURITY', Icons.security, primaryColor),
                _buildActionTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Change Password',
                  subtitle: 'Send a reset link to your email',
                  onTap: _handleChangePassword,
                  primaryColor: primaryColor,
                ),
                _buildActionTile(
                  icon: Icons.email_outlined,
                  title: 'Update Email',
                  subtitle: 'Change your registered email address',
                  onTap: () => _showComingSoonSnackBar('Update Email'),
                  primaryColor: primaryColor,
                ),

                _buildSectionDivider(primaryColor),

                // ── PRIVACY & STEALTH MODE ─────────────────────────────────
                _buildSectionHeader('PRIVACY & STEALTH', Icons.visibility_off_outlined, primaryColor),
                _buildSwitchTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Private Account',
                  subtitle: 'Only friends can see your moments',
                  value: _isPrivate,
                  primaryColor: primaryColor,
                  onChanged: (val) async {
                    final oldVal = _isPrivate;
                    setState(() => _isPrivate = val);
                    try {
                      await _updatePreference('is_private', val);
                    } catch (_) {
                      if (mounted) setState(() => _isPrivate = oldVal);
                    }
                  },
                ),
                _buildSwitchTile(
                  icon: Icons.visibility_off_rounded,
                  title: 'Stealth Mode',
                  subtitle: 'Browse without appearing online',
                  value: _stealthMode,
                  primaryColor: primaryColor,
                  onChanged: (val) async {
                    final oldVal = _stealthMode;
                    setState(() => _stealthMode = val);
                    try {
                      await _updatePreference('stealth_mode', val);
                    } catch (_) {
                      if (mounted) setState(() => _stealthMode = oldVal);
                    }
                  },
                ),

                _buildSectionDivider(primaryColor),

                // ── PERSONALIZATION ─────────────────────────────────────────
                _buildSectionHeader('PERSONALIZATION', Icons.palette_outlined, primaryColor),
                _buildThemeTile(primaryColor),

                _buildSectionDivider(primaryColor),

                // ── NOTIFICATIONS ──────────────────────────────────────────
                _buildSectionHeader('SYNC NOTIFICATIONS', Icons.notifications_active_outlined, primaryColor),
                _buildSwitchTile(
                  icon: Icons.notifications_rounded,
                  title: 'Push Notifications',
                  subtitle: 'Receive alerts for new moments & messages',
                  value: _notificationsEnabled,
                  primaryColor: primaryColor,
                  onChanged: (val) async {
                    final oldVal = _notificationsEnabled;
                    setState(() => _notificationsEnabled = val);
                    try {
                      await _updatePreference('notifications_enabled', val);
                    } catch (_) {
                      if (mounted) setState(() => _notificationsEnabled = oldVal);
                    }
                  },
                ),
                _buildActionTile(
                  icon: Icons.tune_rounded,
                  title: 'Notification Preferences',
                  subtitle: 'Manage FCM / push settings',
                  onTap: () => _showComingSoonSnackBar('Notification Preferences'),
                  primaryColor: primaryColor,
                ),

                _buildSectionDivider(primaryColor),

                // ── HELP & SUPPORT / ABOUT ─────────────────────────────────
                _buildSectionHeader('HELP & ABOUT', Icons.help_outline_rounded, primaryColor),
                _buildActionTile(
                  icon: Icons.quiz_outlined,
                  title: 'FAQ',
                  subtitle: 'Frequently asked questions',
                  onTap: () => _showComingSoonSnackBar('FAQ'),
                  primaryColor: primaryColor,
                ),
                _buildActionTile(
                  icon: Icons.gavel_rounded,
                  title: 'Terms of Service',
                  subtitle: 'Read our terms & conditions',
                  onTap: () => _showComingSoonSnackBar('Terms of Service'),
                  primaryColor: primaryColor,
                ),
                _buildActionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'How we handle your data',
                  onTap: () => _showComingSoonSnackBar('Privacy Policy'),
                  primaryColor: primaryColor,
                ),
                _buildActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About SyncReal',
                  subtitle: 'Version 1.0.0 — Built with ❤️',
                  primaryColor: primaryColor,
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'SyncReal',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2025 SyncReal. All rights reserved.',
                    );
                  },
                ),

                _buildSectionDivider(primaryColor),

                const SizedBox(height: 32),

                // ── DANGER ZONE: LOG OUT ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: InkWell(
                    onTap: _handleLogout,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: Colors.redAccent.withValues(alpha: 0.3),
                    highlightColor: Colors.redAccent.withValues(alpha: 0.1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.power_settings_new, color: Colors.redAccent),
                          const SizedBox(width: 12),
                          Text(
                            'DISCONNECT / LOG OUT',
                            style: AppTheme.orbitron(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
    );
  }

  // ── Builder helpers ──────────────────────────────────────────────────────

  Widget _buildThemeTile(Color primaryColor) {
    final colors = [cyberPurple, laserCyan, toxicGreen];

    return ListTile(
      title: Text(
        'Neon Accent Color',
        style: AppTheme.inter(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Customize the electric glow of SyncReal',
        style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: colors.map((color) {
          final isActive = color.toARGB32() == primaryColor.toARGB32();
          return GestureDetector(
            onTap: () {
              ref.read(themeProvider.notifier).setNeonColor(color);
            },
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: isActive ? Colors.white : Colors.transparent,
                  width: isActive ? 2 : 0,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: isActive
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppTheme.orbitron(
              fontSize: 11,
              color: primaryColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color primaryColor,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: primaryColor, size: 22),
      title: Text(
        title,
        style: AppTheme.inter(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: primaryColor,
      inactiveThumbColor: AppColors.textDisabled,
      inactiveTrackColor: AppColors.surfaceElevated,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color primaryColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: primaryColor, size: 22),
      title: Text(
        title,
        style: AppTheme.inter(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
      onTap: onTap,
    );
  }

  Widget _buildSectionDivider(Color primaryColor) {
    return Divider(
      color: primaryColor.withValues(alpha: 0.15),
      thickness: 1,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }
}
