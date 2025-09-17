// lib/widgets/recipe_card.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:math';

class RecipeCard extends StatelessWidget {
  final String title;
  final List<String>? ingredients;
  final int? timeMinutes;
  final int? calories;
  final String? imageUrl;

  const RecipeCard(
      {super.key,
      required this.title,
      this.ingredients,
      this.timeMinutes,
      this.calories,
      this.imageUrl});

  /// Create a RecipeCard from raw LLM text.
  factory RecipeCard.fromRawText(String raw) {
    // 1) Try to find JSON block and parse
    final jsonStart = raw.indexOf('{');
    final jsonEnd = raw.lastIndexOf('}');
    if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
      try {
        final jsonText = raw.substring(jsonStart, jsonEnd + 1);
        final parsed = jsonDecode(jsonText);
        final t = (parsed['title'] ?? parsed['name'] ?? "Generated Recipe")
            .toString();
        final ingredients =
            (parsed['ingredients'] as List?)?.map((e) => e.toString()).toList();
        final time = parsed['cooking_time_minutes'] is int
            ? parsed['cooking_time_minutes'] as int
            : (parsed['cooking_time_minutes'] != null
                ? int.tryParse(parsed['cooking_time_minutes'].toString())
                : null);
        final cal = parsed['calories_per_serving'] is int
            ? parsed['calories_per_serving'] as int
            : (parsed['calories_per_serving'] != null
                ? int.tryParse(parsed['calories_per_serving'].toString())
                : null);
        final image = parsed['image']?.toString();
        return RecipeCard(
            title: t,
            ingredients: ingredients,
            timeMinutes: time,
            calories: cal,
            imageUrl: image ?? _imageForTitle(t));
      } catch (_) {
        // fall through to other heuristics
      }
    }

    // 2) Try to find Markdown image pattern: ![alt](url)
    final mdImage =
        RegExp(r'!\[.*?\]\((.*?)\)', multiLine: true).firstMatch(raw);
    if (mdImage != null && mdImage.groupCount >= 1) {
      final url = mdImage.group(1);
      // For title pick first heading or first non-empty line
      final firstLine = raw.split('\n').firstWhere((l) => l.trim().isNotEmpty,
          orElse: () => "Generated Recipe");
      final title = _extractFirstHeading(raw) ?? firstLine.trim();
      return RecipeCard(
          title: title,
          ingredients: null,
          timeMinutes: null,
          calories: null,
          imageUrl: url);
    }

    // 3) Fallback: first non-empty line as title and picsum image
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final fallbackTitle =
        lines.isNotEmpty ? lines.first.trim() : "Generated Recipe";
    return RecipeCard(
        title: fallbackTitle, imageUrl: _imageForTitle(fallbackTitle));
  }

  static String? _extractFirstHeading(String raw) {
    final lines = raw.split('\n');
    for (final l in lines) {
      final m = RegExp(r'^\s*#{1,6}\s*(.+)').firstMatch(l);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }

  static String _imageForTitle(String title) {
    // Use picsum seed so same title -> same image
    final seed = title.hashCode.abs() % 1000;
    return "https://picsum.photos/seed/$seed/800/420";
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.hardEdge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imageUrl != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[100],
                child: const Center(
                    child: Icon(Icons.image_not_supported,
                        size: 48, color: Colors.grey)),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[50],
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (timeMinutes != null || calories != null)
              Row(children: [
                if (timeMinutes != null)
                  Text("⏱ ${timeMinutes} min",
                      style: const TextStyle(fontSize: 13)),
                if (timeMinutes != null && calories != null)
                  const SizedBox(width: 12),
                if (calories != null)
                  Text("🔥 ${calories} kcal",
                      style: const TextStyle(fontSize: 13)),
              ]),
            if (ingredients != null && ingredients!.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text("Ingredients:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...ingredients!.take(5).map((i) => Text("• $i")),
              if (ingredients!.length > 5)
                Text("...and ${ingredients!.length - 5} more"),
            ],
          ]),
        )
      ]),
    );
  }
}
