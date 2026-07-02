// lib/features/auth/login_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/constants.dart';
import '../../shared/widgets/lucide_icons.dart';
import '../../shared/widgets/neon_widgets.dart';
import 'auth_gate.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final StreamSubscription<AuthState> _authStateSubscription;

  @override
  void initState() {
    super.initState();
    // Mendengarkan perubahan status autentikasi dari Supabase (termasuk saat callback dari browser/Google OAuth)
    _authStateSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        if (mounted) {
          // Setelah login berhasil, arahkan kembali ke AuthGate.
          // AuthGate yang akan memutuskan apakah user ke Dashboard atau Setup Profile.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthGate()),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  // ── FUNGSI LOGIN GOOGLE REAL ──
  Future<void> _handleGoogleSignIn() async {
    try {
      // Menjalankan proses OAuth ke Google via Supabase
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        // Gunakan Callback URL yang sudah kita daftarkan tadi
        redirectTo: 'syncreal://login-callback/',
      );
    } catch (e) {
      // Jika ada error (misal: internet mati atau konfigurasi salah)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // ── Logo / App Title ──
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        shape: BoxShape.circle,
                        border: Border.all(color: primary, width: 2),
                        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.60), blurRadius: 15, spreadRadius: 2)],
                      ),
                      child: Center(
                        child: LucideIcon(
                          icon: LucideIcons.activity,
                          color: primary,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'SYNCREAL',
                      style: AppTheme.orbitron(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SYNC YOUR REALITY',
                      style: AppTheme.orbitron(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // ── Google Login Button (REAL) ──
              SizedBox(
                width: double.infinity,
                child: NeonOutlineButton(
                  label: 'SIGN IN WITH GOOGLE',
                  icon: LucideIcons.zap,
                  color: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  onTap: _handleGoogleSignIn,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
