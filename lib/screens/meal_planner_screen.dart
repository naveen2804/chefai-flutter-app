import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/firestore_service.dart';
import '../services/chefai_api_service.dart';

class MealPlannerScreen extends StatefulWidget {
  const MealPlannerScreen({super.key});
  @override
  State<MealPlannerScreen> createState() => _MealPlannerScreenState();
}

class _MealPlannerScreenState extends State<MealPlannerScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  // --- THIS NOW USES THE SINGLETON INSTANCE ---
  final ChefAIAPIService _apiService = ChefAIAPIService();

  double _calories = 2000;
  bool _loading = false;
  String _plan = "";

  final TextEditingController _cuisineController = TextEditingController();
  final TextEditingController _preferencesController = TextEditingController();

  @override
  void dispose() {
    _cuisineController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    setState(() {
      _loading = true;
      _plan = "";
    });

    try {
      final substitutions = {
        'calories': _calories.round().toString(),
        'cuisine': _cuisineController.text.isNotEmpty
            ? _cuisineController.text
            : 'Any',
        'preferences': _preferencesController.text.isNotEmpty
            ? _preferencesController.text
            : 'None',
      };

      final stream = _apiService.generateStream(
        templateType: 'meal_plan',
        substitutions: substitutions,
      );

      String tempPlan = "";
      await for (final textChunk in stream) {
        if (mounted) {
          setState(() {
            tempPlan += textChunk;
            _plan = tempPlan;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _plan = "Error: Failed to generate plan. Please try again.");
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _savePlan() async {
    if (_plan.isEmpty || _plan.startsWith("Error:")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No valid plan to save.")),
      );
      return;
    }
    try {
      final savedPlans = await _firestoreService.getMealPlans();

      if (!savedPlans.contains(_plan)) {
        savedPlans.insert(0, _plan);
        await _firestoreService.saveMealPlans(savedPlans);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Meal plan saved successfully!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This meal plan is already saved.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save plan: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text("AI Meal Planner"),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        elevation: 1,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildControls(context),
                const SizedBox(height: 24),
                _buildPlanDisplay(context),
                if (_plan.isNotEmpty &&
                    !_loading &&
                    !_plan.startsWith("Error:"))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: ElevatedButton.icon(
                      onPressed: _savePlan,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text("Save Plan"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              "Daily Calorie Target",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              "${_calories.round()} kcal",
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Slider(
              value: _calories,
              min: 1200,
              max: 3500,
              divisions: 23,
              label: "${_calories.round()}",
              onChanged: (v) => setState(() => _calories = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cuisineController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Cuisine (Optional)',
                hintText: 'e.g., Italian, Mexican, Indian',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _preferencesController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Preferences (Optional)',
                hintText: 'e.g., low-carb, no seafood, vegetarian',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loading ? null : _generatePlan,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: Theme.of(context).textTheme.titleMedium,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.0),
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_loading ? "Generating..." : "Create My Plan"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanDisplay(BuildContext context) {
    if (!_loading && _plan.isEmpty) {
      return Center(
        key: const ValueKey('placeholder'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu_outlined,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              "Set your calories and generate a plan!",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_plan.startsWith("Error:")) {
      return Center(
        key: const ValueKey('error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 60, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 20),
            Text("Oops, something went wrong.",
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _plan,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Card(
      key: const ValueKey('plan'),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[300]!)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            if (_loading && _plan.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text("Crafting your personalized meal plan...",
                        style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            if (_plan.isNotEmpty)
              MarkdownBody(
                data: _plan,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  h2: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  p: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.5),
                  listBullet: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.5),
                  strong: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
