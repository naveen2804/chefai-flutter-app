import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/meal_planner_screen.dart';
import 'screens/pantry_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'services/chefai_api_service.dart';
import 'services/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await ChefAIAPIService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChefAI — Meal Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 162, 234, 252)),
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class MainAppLayout extends StatefulWidget {
  const MainAppLayout({super.key});

  @override
  State<MainAppLayout> createState() => _MainAppLayoutState();
}

class _MainAppLayoutState extends State<MainAppLayout> {
  int _selectedIndex = 0;
  String? _profileImageUrl; // Changed to handle both path and URL
  final FirestoreService _firestoreService = FirestoreService();

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _loadProfileImage();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onProfileUpdated() {
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    final imageUrl = await _firestoreService.getUserProfileImage();
    if (mounted) {
      setState(() {
        _profileImageUrl = imageUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const HomeScreen(),
      const MealPlannerScreen(),
      const PantryScreen(),
      ShoppingListScreen(),
      const FavoritesScreen(),
      ProfileScreen(onProfileUpdated: _onProfileUpdated),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          // Auto-refresh logic for Shopping List
          if (index == 3) { // Index 3 is ShoppingListScreen
            ShoppingListScreen.shoppingListKey.currentState?.refreshLists();
          }
          setState(() {
            _selectedIndex = index;
            _pageController.jumpToPage(index);
          });
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.calendar_month), label: 'Meal Plan'),
          const NavigationDestination(
              icon: Icon(Icons.kitchen_outlined), label: 'Pantry'),
          const NavigationDestination(
              icon: Icon(Icons.list_alt_rounded), label: 'Shopping'),
          const NavigationDestination(
              icon: Icon(Icons.favorite_border), label: 'Favorites'),
          NavigationDestination(
            icon: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey.shade200,
              // --- THE FIX: Use a platform check for the image ---
              backgroundImage: _profileImageUrl != null
                  ? (kIsWeb
                      ? NetworkImage(_profileImageUrl!)
                      : FileImage(File(_profileImageUrl!)) as ImageProvider)
                  : null,
              child: _profileImageUrl == null
                  ? const Icon(Icons.person_outline, size: 16)
                  : null,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
