import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/firestore_service.dart';
import '../services/chefai_api_service.dart';
import 'admin_screen.dart';
import 'favorites_screen.dart';
import 'meal_planner_screen.dart';
import '../widgets/chat_message_bubble.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _requestController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final ChefAIAPIService _apiService = ChefAIAPIService();

  String _selectedCuisine = "";
  String _selectedDifficulty = "";
  String _selectedTime = "";
  String _output = "";
  String _originalOutput = "";
  String _lastModifiedOutput = "";
  bool get _isModified =>
      _originalOutput.isNotEmpty && _output != _originalOutput;
  bool _loading = false;
  double _servings = 4.0;
  List<String> _videoUrls = [];
  int _dietPreferenceIndex = 1;
  String _userName = "";

  // --- NEW STATE VARIABLE FOR THE CHECKBOX ---
  bool _usePantry = false;
  bool _pantryHasItems = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;

  final List<String> _cuisines = [
    "",
    "South Indian",
    "North Indian",
    "Italian",
    "Continental",
    "Chinese",
    "Mexican",
    "Thai",
    "Japanese",
    "Mediterranean",
    "French",
    "Korean",
  ];
  final List<String> _difficulties = [
    "",
    "Beginner",
    "Intermediate",
    "Advanced"
  ];
  final List<String> _cookingTimes = [
    "",
    "Under 15 minutes",
    "15-30 minutes",
    "30-60 minutes",
    "1+ hours",
  ];
  final List<Map<String, dynamic>> _quickSuggestions = [
    {
      'text': "Quick breakfast with eggs and spinach",
      'icon': Icons.breakfast_dining_rounded,
      'color': Colors.orange,
      'category': 'Breakfast'
    },
    {
      'text': "Healthy lunch with chicken and vegetables",
      'icon': Icons.lunch_dining_rounded,
      'color': Colors.green,
      'category': 'Lunch'
    },
    {
      'text': "Comfort dinner with pasta and cheese",
      'icon': Icons.dinner_dining_rounded,
      'color': Colors.purple,
      'category': 'Dinner'
    },
    {
      'text': "Sweet dessert with chocolate and berries",
      'icon': Icons.cake_rounded,
      'color': Colors.pink,
      'category': 'Dessert'
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController.forward();
    _loadUserName();
    _checkPantryStatus();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (mounted) {
      setState(() {
        _userName = user?.displayName?.split(' ').first ?? 'User';
      });
    }
  }

  // --- NEW: Check if pantry has items to enable the checkbox ---
  Future<void> _checkPantryStatus() async {
    final pantryItems = await _firestoreService.getPantry();
    if (mounted) {
      setState(() {
        _pantryHasItems = pantryItems.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _requestController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String? _extractRecipeTitle(String markdownText) {
    final lines = markdownText.split('\n');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('# ')) {
        return trimmedLine.substring(2).replaceAll('*', '').trim();
      }
    }
    return null;
  }

  // --- UPDATED: No more dialog, just checks the _usePantry boolean ---
  Future<void> _generate() async {
    final input = _requestController.text.trim();
    if (input.isEmpty && !_usePantry) {
      _showSnackBar("Please enter your recipe request or select 'Use Pantry'",
          isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _output = "";
      _originalOutput = "";
      _lastModifiedOutput = "";
      _videoUrls = [];
    });

    _slideController.forward(from: 0.0);

    try {
      String userInput = input;
      if (_usePantry) {
        final pantryItemsMap = await _firestoreService.getPantry();
        final pantryItems = pantryItemsMap.keys.toList();
        if (pantryItems.isNotEmpty) {
          userInput =
              "A recipe using only these ingredients: ${pantryItems.join(', ')}";
        } else {
          // Fallback if pantry is empty but checkbox was checked
          _showSnackBar(
              "Your pantry is empty. Please add ingredients or uncheck 'Use Pantry'.",
              isError: true);
          setState(() => _loading = false);
          return;
        }
      }

      String dietPrefString = 'Any';
      if (_dietPreferenceIndex == 0) dietPrefString = 'Vegetarian';
      if (_dietPreferenceIndex == 2) dietPrefString = 'Non-Vegetarian';

      final substitutions = {
        'userInput': userInput,
        'dietaryPreference': dietPrefString,
        'cuisine': _selectedCuisine.isNotEmpty ? _selectedCuisine : 'Any',
        'difficulty':
            _selectedDifficulty.isNotEmpty ? _selectedDifficulty : 'Any',
        'cookingTime': _selectedTime.isNotEmpty ? _selectedTime : 'Any',
        'servings': _servings.round().toString(),
      };

      final stream = _apiService.generateStream(
        templateType: 'recipe',
        substitutions: substitutions,
      );

      String tempOutput = "";
      await for (final textChunk in stream) {
        if (mounted) {
          tempOutput += textChunk;
          setState(() {
            _output = tempOutput;
          });
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      }

      if (mounted) {
        setState(() {
          _originalOutput = _output;
        });
        final recipeTitle = _extractRecipeTitle(_output);
        if (recipeTitle != null) {
          await _fetchYoutubeVideos(recipeTitle);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _output =
          "⚠️ **Error generating recipe**\n\nSomething went wrong: ${e.toString()}\n\nPlease check your connection and try again.");
      _showSnackBar("Failed to generate recipe: ${e.toString()}",
          isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openModificationChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ChatModificationSheet(
          originalRecipe: _output,
          onRecipeModified: (newRecipe) {
            setState(() {
              _lastModifiedOutput = _output;
              _output = newRecipe;
            });
            final newTitle = _extractRecipeTitle(newRecipe);
            if (newTitle != null) {
              _fetchYoutubeVideos(newTitle);
            }
          },
        );
      },
    );
  }

  void _revertToOriginal() {
    setState(() {
      _lastModifiedOutput = _output;
      _output = _originalOutput;
    });
    _showSnackBar("Reverted to the original recipe.", isError: false);
    final originalTitle = _extractRecipeTitle(_originalOutput);
    if (originalTitle != null) {
      _fetchYoutubeVideos(originalTitle);
    }
  }

  void _redoModification() {
    final temp = _output;
    setState(() {
      _output = _lastModifiedOutput;
      _lastModifiedOutput = temp;
    });
    _showSnackBar("Redone modification.", isError: false);
    final redoneTitle = _extractRecipeTitle(_output);
    if (redoneTitle != null) {
      _fetchYoutubeVideos(redoneTitle);
    }
  }

  Future<void> _fetchYoutubeVideos(String query) async {
    const apiKey = 'AIzaSyCUtJoudsIMqAjJUSn45kyb30KY6hKJGP8'; // Replace this
    if (apiKey == 'YOUR_YOUTUBE_API_KEY' || apiKey.isEmpty) return;

    final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults=3&q=$query recipe&key=$apiKey');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] is! List) {
          if (mounted) setState(() => _videoUrls = []);
          return;
        }
        final videoUrls = <String>[];
        for (var item in data['items']) {
          final videoId = item?['id']?['videoId'];
          if (videoId != null) {
            videoUrls.add('https://www.youtube.com/watch?v=$videoId');
          }
        }
        if (mounted) setState(() => _videoUrls = videoUrls);
      }
    } catch (e) {
      _showSnackBar("Could not fetch video suggestions", isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _saveToFavorites() async {
    if (_output.isEmpty || _output.startsWith("⚠️")) {
      _showSnackBar("No valid recipe to save", isError: true);
      return;
    }
    try {
      final favs = await _firestoreService.getFavorites();
      final favoriteData = {'recipe': _output, 'videos': _videoUrls};
      final favoriteString = json.encode(favoriteData);

      if (!favs.contains(favoriteString)) {
        favs.insert(0, favoriteString);
        await _firestoreService.saveFavorites(favs);
        _showSnackBar("Recipe saved to favorites!", isError: false);
      } else {
        _showSnackBar("Recipe already in favorites", isError: false);
      }
    } catch (e) {
      _showSnackBar("Failed to save: $e", isError: true);
    }
  }

  Future<void> _copyToClipboard() async {
    if (_output.isEmpty || _output.startsWith("⚠️")) {
      _showSnackBar("No valid recipe to copy", isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _output));
    _showSnackBar("Recipe copied to clipboard!", isError: false);
  }

  void _openAdmin() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Admin Access"),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Enter admin password"),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text == "Naveenkeeri2804!") {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AdminScreen()));
                } else {
                  Navigator.of(context).pop();
                  _showSnackBar("Incorrect password", isError: true);
                }
              },
              child: const Text("Enter"),
            ),
          ],
        );
      },
    );
  }

  void _openMealPlanner() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MealPlannerScreen()));
  }

  void _openFavorites() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FavoritesScreen()));
  }

  void _showFeaturesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("App Features"),
        content: const SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text("Welcome to ChefAI! Here's what you can do:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(
                  "• Generate Recipes: Describe a dish or list ingredients to get a custom recipe with preferences for cuisine, difficulty, servings and cooking time."),
              SizedBox(height: 10),
              Text(
                  "• Video Suggestions: Get YouTube video links for visual cooking guides."),
              SizedBox(height: 10),
              Text(
                  "• Modify on the Fly: Use the 'Modify Recipe' chat to substitute ingredients or change the recipe after it's generated."),
              SizedBox(height: 10),
              Text(
                  "• Create Meal Plans: Plan your week with an AI-generated 7-day meal plan tailored to your calorie goals."),
              SizedBox(height: 10),
              Text(
                  "• Save Favorites: Store your favorite recipes and meal plans in one place."),
              SizedBox(height: 10),
              Text(
                  "• Cook Now: Cook your favorite recipes with step-by-step instructions and timers."),
              SizedBox(height: 10),
              Text(
                  "• Generate Shopping Lists: Create a shopping list for any recipe or meal plan."),
              SizedBox(height: 10),
              Text(
                  "• Pantry Management: Keep track of your pantry items and get recipes based on what you have."),
              SizedBox(height: 10),
              Text(
                  "• Rate and Review: Rate recipes and share your cooking photos."),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Got it!'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Hi $_userName,",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                Text(
                  "Welcome to ChefAI",
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.info_outline, color: Colors.grey.shade500),
            onPressed: _showFeaturesDialog,
            tooltip: "App Features",
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: Colors.orange.shade600),
              const SizedBox(width: 8),
              const Text(
                "Quick Ideas",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _quickSuggestions.length,
            itemBuilder: (context, index) {
              final suggestion = _quickSuggestions[index];
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 12),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onTap: () => setState(
                        () => _requestController.text = suggestion['text']),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            suggestion['color'].withOpacity(0.1),
                            suggestion['color'].withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                suggestion['icon'],
                                color: suggestion['color'],
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  suggestion['category'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: suggestion['color'],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              suggestion['text'],
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.edit_rounded, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              const Text(
                "Tell us what you want",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              controller: _requestController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    "Describe your preferred recipe or list the ingredients you have...\n\ne.g., \"a simple chicken pasta with tomatoes and basil\"",
                hintStyle: TextStyle(color: Colors.grey.shade500, height: 1.5),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.description_rounded,
                      color: Colors.blue.shade600),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- UPDATED: Added the "Use Pantry" checkbox ---
  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.purple.shade600),
              const SizedBox(width: 8),
              const Text(
                "Preferences (Optional)",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _buildDropdown("Cuisine", _selectedCuisine, _cuisines,
                    (v) => setState(() => _selectedCuisine = v ?? ""))),
            const SizedBox(width: 12),
            Expanded(
                child: _buildDropdown(
                    "Difficulty",
                    _selectedDifficulty,
                    _difficulties,
                    (v) => setState(() => _selectedDifficulty = v ?? ""))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                  "Cooking Time",
                  _selectedTime,
                  _cookingTimes,
                  (v) => setState(() => _selectedTime = v ?? "")),
            ),
            const SizedBox(width: 12),
            // The new checkbox widget
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: CheckboxListTile(
                  title: const Text("Use Pantry"),
                  value: _usePantry,
                  onChanged: _pantryHasItems
                      ? (bool? value) {
                          setState(() {
                            _usePantry = value ?? false;
                          });
                        }
                      : null, // Disable if pantry is empty
                  subtitle: !_pantryHasItems
                      ? const Text("Pantry empty",
                          style: TextStyle(fontSize: 10))
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.only(left: 4.0),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.people_alt_rounded, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              const Text(
                "Servings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                Text(
                  _servings.round().toString(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Slider(
                  value: _servings,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _servings.round().toString(),
                  onChanged: (v) => setState(() => _servings = v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items,
      Function(String?) onChanged) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            hint: Text(label),
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: items
                .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.isEmpty ? "Any $label" : item),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _loading ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
            child: _loading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text("Generating your recipe...",
                          style: TextStyle(fontSize: 16)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 24),
                      const SizedBox(width: 8),
                      const Text("Generate Recipe",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFavorites,
                icon: const Icon(Icons.favorite_rounded),
                label: const Text("Favorites"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMealPlanner,
                icon: const Icon(Icons.calendar_today_rounded),
                label: const Text("Meal Planner"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecipeOutput() {
    if (_output.isEmpty && !_loading) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                "Your recipe will appear here",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Fill out the form above and click Generate Recipe",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _slideController,
      child: Column(
        children: [
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant_rounded,
                          color: Colors.green.shade600),
                      const SizedBox(width: 8),
                      const Text(
                        "Your Recipe",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_isModified)
                        IconButton(
                          icon: const Icon(Icons.undo_rounded,
                              color: Colors.blue),
                          tooltip: "Revert to Original Recipe",
                          onPressed: _revertToOriginal,
                        ),
                      if (_lastModifiedOutput.isNotEmpty &&
                          _output != _lastModifiedOutput)
                        IconButton(
                          icon: const Icon(Icons.redo_rounded,
                              color: Colors.blue),
                          tooltip: "Redo Modification",
                          onPressed: _redoModification,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _output.isEmpty && _loading
                      ? const Center(child: CircularProgressIndicator())
                      : MarkdownBody(
                          data: _output,
                          selectable: true,
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(Theme.of(context))
                                  .copyWith(
                            h1: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800),
                            h2: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700),
                            p: TextStyle(
                                fontSize: 16,
                                height: 1.6,
                                color: Colors.grey.shade700),
                            listBullet: TextStyle(color: Colors.blue.shade600),
                          ),
                        ),
                ],
              ),
            ),
          ),
          if (!_loading && !_output.startsWith("⚠️")) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openModificationChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text("Modify Recipe"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveToFavorites,
                    icon: const Icon(Icons.favorite_rounded),
                    label: const Text("Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_videoUrls.isNotEmpty) _buildVideoSuggestions(),
        ],
      ),
    );
  }

  Widget _buildVideoSuggestions() {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.video_library_rounded, color: Colors.red.shade600),
              const SizedBox(width: 8),
              const Text(
                "Video Suggestions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._videoUrls.map((url) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.red),
                  title: Text(
                    url,
                    style: TextStyle(color: Colors.blue.shade800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else {
                      _showSnackBar("Could not open video link", isError: true);
                    }
                  },
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "ChefAI",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.admin_panel_settings_rounded),
          //   onPressed: _openAdmin,
          //   tooltip: "Admin Settings",
          // ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildQuickSuggestions(),
              const SizedBox(height: 24),
              _buildInputSection(),
              const SizedBox(height: 20),
              _buildPreferencesSection(),
              const SizedBox(height: 20),
              DietaryPreferencePicker(
                selectedIndex: _dietPreferenceIndex,
                onChanged: (index) {
                  setState(() {
                    _dietPreferenceIndex = index;
                  });
                },
              ),
              const SizedBox(height: 20),
              _buildServingsSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
              const SizedBox(height: 24),
              _buildRecipeOutput(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class DietaryPreferencePicker extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const DietaryPreferencePicker({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildOption(context, "Veg", 0, Colors.green),
            _buildOption(context, "Any", 1, Colors.grey),
            _buildOption(context, "Non-Veg", 2, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
      BuildContext context, String text, int index, Color color) {
    final bool isSelected = selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? color : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

class ChatModificationSheet extends StatefulWidget {
  final String originalRecipe;
  final ValueChanged<String> onRecipeModified;

  const ChatModificationSheet({
    super.key,
    required this.originalRecipe,
    required this.onRecipeModified,
  });

  @override
  State<ChatModificationSheet> createState() => _ChatModificationSheetState();
}

class _ChatModificationSheetState extends State<ChatModificationSheet> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChefAIAPIService _apiService = ChefAIAPIService();

  List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  String _modifiedRecipe = "";

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
        isUser: false, text: "How would you like to modify this recipe?"));
  }

  void _sendMessage() async {
    final userRequest = _chatController.text.trim();
    if (userRequest.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(isUser: true, text: userRequest));
      _isGenerating = true;
    });
    _chatController.clear();
    FocusScope.of(context).unfocus();

    final substitutions = {
      'originalRecipe': widget.originalRecipe,
      'userRequest': userRequest,
    };

    String tempResponse = "";
    _messages.add(ChatMessage(isUser: false, text: ""));

    try {
      final stream = _apiService.generateStream(
        templateType: 'modification',
        substitutions: substitutions,
      );

      await for (final chunk in stream) {
        if (mounted) {
          setState(() {
            tempResponse += chunk;
            _messages.last = ChatMessage(isUser: false, text: tempResponse);
          });
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      }
      _modifiedRecipe = tempResponse;
    } catch (e) {
      if (mounted) {
        _messages.last = ChatMessage(
            isUser: false, text: "Sorry, I encountered an error: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ChatMessageBubble(
                        isUser: message.isUser,
                        text: message.text,
                      );
                    },
                  ),
                ),
                if (_modifiedRecipe.isNotEmpty && !_isGenerating)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            child: const Text("Discard"),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            child: const Text("Replace Recipe"),
                            onPressed: () {
                              widget.onRecipeModified(_modifiedRecipe);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          enabled: !_isGenerating,
                          decoration: InputDecoration(
                            hintText: "e.g., I don't have potatoes...",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _isGenerating ? null : _sendMessage,
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
