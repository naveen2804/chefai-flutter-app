import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Import the platform check
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _backgroundColorAnimation;
  late Animation<Color?> _textColorAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _backgroundColorAnimation = ColorTween(
      begin: Colors.black,
      end: Colors.white,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _textColorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.blue.shade700,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    _controller.forward();
    await Future.delayed(const Duration(milliseconds: 3500));
    _navigateToNextScreen();
  }

  Future<void> _requestPermissions() async {
    // --- THIS IS THE FIX ---
    // We only request permissions if the app is NOT running on the web.
    if (!kIsWeb) {
      await Permission.photos.request();
    }
  }

  void _navigateToNextScreen() async {
    if (mounted) {
      await _requestPermissions();

      final user = FirebaseAuth.instance.currentUser;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              user != null ? const MainAppLayout() : const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 700),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: _backgroundColorAnimation.value,
          body: Center(
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Welcome to ChefAI",
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: _textColorAnimation.value,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Made with love by Naveen Narayan",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: _textColorAnimation.value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
