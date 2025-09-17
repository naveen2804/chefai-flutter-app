import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/firestore_service.dart';
import '../services/chefai_api_service.dart';
import '../widgets/chat_message_bubble.dart';
import 'home_screen.dart';

class PantryRecipeScreen extends StatefulWidget {
  final Map<String, String> pantryItems;
  const PantryRecipeScreen({super.key, required this.pantryItems});

  @override
  State<PantryRecipeScreen> createState() => _PantryRecipeScreenState();
}

class _PantryRecipeScreenState extends State<PantryRecipeScreen> {
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  // --- THIS NOW USES THE SINGLETON INSTANCE ---
  final ChefAIAPIService _apiService = ChefAIAPIService();

  String _output = "";
  String _originalOutput = "";
  String _lastModifiedOutput = "";
  bool get _isModified =>
      _originalOutput.isNotEmpty && _output != _originalOutput;
  bool _loading = false;
  List<String> _videoUrls = [];

  @override
  void initState() {
    super.initState();
    _generateFromPantry();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String? _extractRecipeTitle(String markdownText) {
    final lines = markdownText.split('\n');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('# ')) {
        return trimmedLine.substring(2).trim();
      }
    }
    return null;
  }

  Future<void> _generateFromPantry() async {
    setState(() {
      _loading = true;
      _output = "";
      _originalOutput = "";
      _lastModifiedOutput = "";
      _videoUrls = [];
    });

    final ingredients =
        widget.pantryItems.entries.map((e) => "${e.value} ${e.key}").join(', ');
    final userInput = "A recipe using only these ingredients: $ingredients";

    try {
      final substitutions = {
        'userInput': userInput,
        'dietaryPreference': 'Any',
        'cuisine': 'Any',
        'difficulty': 'Any',
        'cookingTime': 'Any',
        'servings': '2', // Default servings for pantry recipes
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
    final redoneTitle = _extractRecipeTitle(_output);
    if (redoneTitle != null) {
      _fetchYoutubeVideos(redoneTitle);
    }
  }

  Future<void> _fetchYoutubeVideos(String query) async {
    const apiKey = 'YOUR_YOUTUBE_API_KEY'; // Replace this
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
      // Handle error silently or show a snackbar
    }
  }

  Future<void> _saveToFavorites() async {
    if (_output.isEmpty || _output.startsWith("⚠️")) return;
    try {
      final favs = await _firestoreService.getFavorites();
      final favoriteData = {'recipe': _output, 'videos': _videoUrls};
      final favoriteString = json.encode(favoriteData);

      if (!favs.contains(favoriteString)) {
        favs.insert(0, favoriteString);
        await _firestoreService.saveFavorites(favs);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Recipe saved to favorites!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Recipe already in favorites")),
        );
      }
    } catch (e) {
      // Handle error
    }
  }

  Widget _buildRecipeOutput() {
    if (_output.isEmpty && !_loading) {
      return const Center(child: Text("No recipe generated yet."));
    }
    if (_loading && _output.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
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
                    const Text("Your Recipe",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_isModified)
                      IconButton(
                        icon:
                            const Icon(Icons.undo_rounded, color: Colors.blue),
                        onPressed: _revertToOriginal,
                      ),
                    if (_lastModifiedOutput.isNotEmpty &&
                        _output != _lastModifiedOutput)
                      IconButton(
                        icon:
                            const Icon(Icons.redo_rounded, color: Colors.blue),
                        onPressed: _redoModification,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                MarkdownBody(data: _output),
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveToFavorites,
                  icon: const Icon(Icons.favorite_rounded),
                  label: const Text("Save"),
                ),
              ),
            ],
          ),
        ],
        if (_videoUrls.isNotEmpty) _buildVideoSuggestions(),
      ],
    );
  }

  Widget _buildVideoSuggestions() {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Video Suggestions",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._videoUrls.map((url) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.red),
                  title:
                      Text(url, style: TextStyle(color: Colors.blue.shade800)),
                  onTap: () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
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
      appBar: AppBar(title: const Text("Pantry Recipe Suggestion")),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: _buildRecipeOutput(),
      ),
    );
  }
}
