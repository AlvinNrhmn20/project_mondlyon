import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/main.dart'; // Untuk memanggil MainNavigationScreen
import 'package:syncreal/features/auth/login_page.dart';
import 'package:syncreal/features/auth/setup_profile_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    // Delay sebentar untuk memastikan widget sudah ter-mount dengan baik di Navigator
    await Future.delayed(Duration.zero);

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        if (profile != null &&
            profile['username'] != null &&
            profile['username'].toString().trim().isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => const MainNavigationScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SetupProfilePage()),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking user profile: $e');
      if (mounted) {
        // Fallback ke setup profile jika terjadi error yang tidak terduga
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SetupProfilePage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.black,
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.neonPurple,
        ),
      ),
    );
  }
}
