import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/firestore_service.dart';
import '../services/chefai_api_service.dart';
import 'cook_now_screen.dart';
import 'recipe_details_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final ChefAIAPIService _apiService = ChefAIAPIService();
  List<String> _savedRecipes = [];
  List<String> _savedPlans = [];
  bool _isLoading = true;

  late TabController _tabController;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadFavorites();
      }
    });
    _loadFavorites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final recipes = await _firestoreService.getFavorites();
      final plans = await _firestoreService.getMealPlans();
      if (mounted) {
        setState(() {
          _savedRecipes = recipes;
          _savedPlans = plans;
          _isLoading = false;
        });
        _animationController.forward(from: 0.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Error loading favorites: $e");
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "My Favorites",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        // actions: [
        //   if (!_isLoading)
        //     IconButton(
        //       icon: const Icon(Icons.refresh_rounded),
        //       onPressed: _loadFavorites,
        //       tooltip: "Refresh",
        //     ),
        // ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.fastfood_rounded), text: "Recipes"),
            Tab(icon: Icon(Icons.calendar_month_rounded), text: "Meal Plans"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
              opacity: _animationController,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRecipesList(),
                  _buildPlansList(),
                ],
              ),
            ),
    );
  }

  Widget _buildRecipesList() {
    if (_savedRecipes.isEmpty) {
      return _buildEmptyState("Recipes", "Add some recipes to get started!");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedRecipes.length,
      itemBuilder: (context, index) => _buildRecipeItem(index),
    );
  }

  Widget _buildPlansList() {
    if (_savedPlans.isEmpty) {
      return _buildEmptyState(
          "Meal Plans", "Generate and save a plan to see it here.");
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedPlans.length,
      itemBuilder: (context, index) => _buildPlanItem(index),
    );
  }

  Widget _buildRecipeItem(int index) {
    final favoriteData = json.decode(_savedRecipes[index]);
    final String recipeText = favoriteData['recipe'] ?? '';
    final List<String> videoUrls =
        List<String>.from(favoriteData['videos'] ?? []);
    final String recipeId = recipeText.hashCode.toString();
    final title = _extractRecipeTitle(recipeText);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.restaurant_menu_rounded,
                    color: Colors.orange.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Saved Recipe #${index + 1}",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _showDeleteConfirmation(index, isRecipe: true);
                    }
                  },
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.grey.shade600,
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: Colors.red.shade400),
                          const SizedBox(width: 12),
                          const Text('Remove from favorites'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecipeDetailsScreen(
                        recipeMarkdown: recipeText, recipeId: recipeId),
                  ),
                ).then((_) => setState(() {}));
              },
              child: Text(
                _extractRecipePreview(recipeText),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FutureBuilder<double>(
                  future: _getRating(recipeId),
                  builder: (context, snapshot) {
                    return RatingBarIndicator(
                      rating: snapshot.data ?? 0,
                      itemBuilder: (context, index) =>
                          const Icon(Icons.star, color: Colors.amber),
                      itemCount: 5,
                      itemSize: 20.0,
                      direction: Axis.horizontal,
                    );
                  },
                ),
                Row(
                  children: [
                    // Column(
                    //   children: [
                    //     IconButton(
                    //       icon: const Icon(Icons.list_alt_rounded,
                    //           color: Colors.blueGrey),
                    //       onPressed: () => _generateShoppingList(recipeText),
                    //       tooltip: "Generate Shopping List",
                    //     ),
                    //     Text("List",
                    //         style: TextStyle(
                    //             fontSize: 10, color: Colors.grey.shade600)),
                    //   ],
                    // ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill,
                              color: Colors.green),
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => CookNowScreen(
                                        recipeMarkdown: recipeText)));
                          },
                          tooltip: "Cook Now",
                        ),
                        Text("Cook",
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // --- NEW, FULL-WIDTH BUTTON ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _generateShoppingList(recipeText),
                icon:
                    const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: const Text("Generate Shopping List"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade50,
                  foregroundColor: Colors.blueGrey.shade800,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            if (videoUrls.isNotEmpty) ...[
              const Divider(height: 24),
              Text("Video Suggestions",
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...videoUrls.map((url) => ListTile(
                    leading: const Icon(Icons.play_circle_outline,
                        color: Colors.red),
                    title: Text(url,
                        style: TextStyle(
                            color: Colors.blue.shade800, fontSize: 12)),
                    dense: true,
                    onTap: () async {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  )),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPlanItem(int index) {
    final planText = _savedPlans[index];
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showPlanDialog(planText),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.calendar_today_rounded,
                    color: Colors.blue.shade600, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  "7-Day Meal Plan #${index + 1}",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteConfirmation(index, isRecipe: false);
                  }
                },
                icon:
                    Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            color: Colors.red.shade400),
                        const SizedBox(width: 12),
                        const Text('Remove Plan'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              title == "Recipes"
                  ? Icons.fastfood_rounded
                  : Icons.calendar_month_rounded,
              size: 80,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            "No Saved $title",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
        ],
      ),
    );
  }

  void _showPlanDialog(String planText) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Saved Meal Plan"),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: MarkdownBody(
                data: planText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(int index, {required bool isRecipe}) {
    final list = isRecipe ? _savedRecipes : _savedPlans;
    if (index >= list.length) return;

    final text = list[index];
    final title = isRecipe
        ? _extractRecipeTitle(json.decode(text)['recipe'])
        : "7-Day Meal Plan #${index + 1}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600),
            const SizedBox(width: 12),
            Expanded(child: Text("Remove ${isRecipe ? 'Recipe' : 'Plan'}")),
          ],
        ),
        content: Text(
          "Are you sure you want to remove \"$title\" from your favorites?",
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeAt(index, isRecipe: isRecipe);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  Future<void> _removeAt(int index, {required bool isRecipe}) async {
    final list = isRecipe ? _savedRecipes : _savedPlans;
    if (index < list.length) {
      list.removeAt(index);
    }

    if (isRecipe) {
      await _firestoreService.saveFavorites(list);
    } else {
      await _firestoreService.saveMealPlans(list);
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text("${isRecipe ? 'Recipe' : 'Plan'} removed from favorites"),
          backgroundColor: Colors.green.shade600,
        ),
      );
    }
  }

  Future<double> _getRating(String recipeId) async {
    final reviewData = await _firestoreService.getReview(recipeId);
    return reviewData['rating'] ?? 0.0;
  }

  Future<void> _generateShoppingList(String recipeMarkdown) async {
    final title = _extractRecipeTitle(recipeMarkdown);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Generating shopping list...")),
    );

    try {
      final stream = _apiService.generateStream(
        templateType: 'shopping_list',
        substitutions: {'recipeMarkdown': recipeMarkdown},
      );

      String rawList = await stream.join();
      final ingredients = rawList
          .split('\n')
          .where((line) => line.trim().startsWith('*'))
          .map((line) => line.trim().substring(2).trim())
          .toList();

      if (ingredients.isEmpty) {
        _showErrorSnackBar(
            "Could not extract ingredients for the shopping list.");
        return;
      }

      final currentLists = await _firestoreService.getShoppingLists();
      currentLists[title] = ingredients;
      await _firestoreService.saveShoppingLists(currentLists);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'$title' added to your shopping list!")),
      );
    } catch (e) {
      _showErrorSnackBar("Failed to generate shopping list: $e");
    }
  }

  String _extractRecipeTitle(String recipeText) {
    final lines = recipeText.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
    }
    return "Delicious Recipe";
  }

  String _extractRecipePreview(String recipeText) {
    final lines = recipeText.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty &&
          !trimmed.startsWith('*') &&
          !trimmed.startsWith('#')) {
        return trimmed.length > 100
            ? '${trimmed.substring(0, 100)}...'
            : trimmed;
      }
    }
    return "A wonderful recipe waiting to be discovered!";
  }
}
