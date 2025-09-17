import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../services/firestore_service.dart';
import 'cook_now_screen.dart';
import '../services/chefai_api_service.dart';

class RecipeDetailsScreen extends StatefulWidget {
  final String recipeMarkdown;
  final String recipeId;

  const RecipeDetailsScreen({
    super.key,
    required this.recipeMarkdown,
    required this.recipeId,
  });

  @override
  State<RecipeDetailsScreen> createState() => _RecipeDetailsScreenState();
}

class _RecipeDetailsScreenState extends State<RecipeDetailsScreen> {
  double _rating = 0.0;
  String? _userImagePath;
  String? _nutritionInfo;
  // --- THIS NOW USES THE SINGLETON INSTANCE ---
  final ChefAIAPIService _apiService = ChefAIAPIService();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoadingReview = true;

  @override
  void initState() {
    super.initState();
    _loadReviewData();
  }

  Future<void> _loadReviewData() async {
    setState(() => _isLoadingReview = true);
    final reviewData = await _firestoreService.getReview(widget.recipeId);
    if (mounted) {
      setState(() {
        _rating = reviewData['rating'] ?? 0.0;
        _userImagePath = reviewData['imagePath'];
        _nutritionInfo = reviewData['nutritionInfo'];
        _isLoadingReview = false;
      });
    }
  }

  Future<void> _saveRating(double rating) async {
    await _firestoreService.saveReview(widget.recipeId, rating: rating);
    if (mounted) {
      setState(() {
        _rating = rating;
      });
    }
  }

  Future<void> _pickImage() async {
    var status = await Permission.photos.status;
    if (status.isDenied) {
      status = await Permission.photos.request();
    }

    if (status.isPermanentlyDenied) {
      openAppSettings();
      return;
    }

    if (status.isGranted) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        await _firestoreService.saveReview(widget.recipeId,
            imagePath: pickedFile.path);
        if (mounted) {
          setState(() {
            _userImagePath = pickedFile.path;
          });
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Photo permission is required to upload an image.")),
      );
    }
  }

  void _showNutritionInfo() {
    showDialog(
      context: context,
      builder: (context) {
        if (_nutritionInfo != null) {
          return AlertDialog(
            title: const Text("Nutritional Information"),
            content: SingleChildScrollView(
                child: MarkdownBody(data: _nutritionInfo!)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"))
            ],
          );
        }

        return AlertDialog(
          title: const Text("Nutritional Information"),
          content: StreamBuilder<String>(
            stream: _apiService.generateStream(
              templateType: 'nutrition_info',
              substitutions: {'recipeMarkdown': widget.recipeMarkdown},
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData) {
                final newNutritionInfo = snapshot.data!;
                _firestoreService
                    .saveReview(widget.recipeId,
                        nutritionInfo: newNutritionInfo)
                    .then((_) {
                  if (mounted) {
                    setState(() {
                      _nutritionInfo = newNutritionInfo;
                    });
                  }
                });
              }

              if (snapshot.hasData) {
                return SingleChildScrollView(
                  child: MarkdownBody(data: snapshot.data!),
                );
              }

              return const Center(child: CircularProgressIndicator());
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Close"))
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_extractTitle(widget.recipeMarkdown)),
        actions: [
          // TextButton.icon(
          //   onPressed: _showNutritionInfo,
          //   icon: const Icon(Icons.info_outline),
          //   label: const Text("Nutrition"),
          //   style: TextButton.styleFrom(
          //     foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          //   ),
          // ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(widget.recipeMarkdown),
            tooltip: "Share Recipe",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: MarkdownBody(
                  data: widget.recipeMarkdown,
                ),
              ),
            ),
            const Divider(height: 32),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _isLoadingReview
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Your Review",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          RatingBar.builder(
                            initialRating: _rating,
                            minRating: 1,
                            direction: Axis.horizontal,
                            allowHalfRating: true,
                            itemCount: 5,
                            itemBuilder: (context, _) =>
                                const Icon(Icons.star, color: Colors.amber),
                            onRatingUpdate: _saveRating,
                          ),
                          const SizedBox(height: 24),
                          const Text("Upload a photo of your meal:",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade400),
                                image: _userImagePath != null
                                    ? DecorationImage(
                                        image: FileImage(File(_userImagePath!)),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _userImagePath == null
                                  ? const Center(
                                      child: Icon(Icons.camera_alt,
                                          size: 50, color: Colors.grey))
                                  : null,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CookNowScreen(recipeMarkdown: widget.recipeMarkdown),
            ),
          );
        },
        label: const Text("Cook Now"),
        icon: const Icon(Icons.play_arrow),
      ),
    );
  }

  String _extractTitle(String markdown) {
    final lines = markdown.split('\n');
    for (var line in lines) {
      if (line.startsWith('# ')) {
        return line.substring(2).trim();
      }
    }
    return "Recipe";
  }
}
