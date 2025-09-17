import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class ChefAIAPIService {
  // --- SINGLETON SETUP START ---
  ChefAIAPIService._internal();
  static final ChefAIAPIService _instance = ChefAIAPIService._internal();
  factory ChefAIAPIService() {
    return _instance;
  }
  // --- SINGLETON SETUP END ---

  String? _recipePromptTemplate;
  String? _mealPlanPromptTemplate;
  String? _modificationPromptTemplate;
  String? _nutritionInfoPromptTemplate;
  String? _shoppingListPromptTemplate;

  Future<void> init() async {
    await _loadPromptTemplates();
  }

  Future<void> _loadPromptTemplates() async {
    try {
      _recipePromptTemplate = await rootBundle
          .loadString('assets/prompts/recipe_prompt_template.txt');
      _mealPlanPromptTemplate = await rootBundle
          .loadString('assets/prompts/meal_plan_prompt_template.txt');
      _modificationPromptTemplate = await rootBundle
          .loadString('assets/prompts/modification_prompt_template.txt');
      _nutritionInfoPromptTemplate = await rootBundle
          .loadString('assets/prompts/nutrition_info_prompt.txt');
      _shoppingListPromptTemplate = await rootBundle
          .loadString('assets/prompts/shopping_list_prompt.txt');
    } catch (e) {
      print("Error loading prompt templates: $e");
    }
  }

  Stream<String> generateStream({
    required String templateType,
    required Map<String, String> substitutions,
  }) async* {
    String? template;
    switch (templateType) {
      case 'recipe':
        template = _recipePromptTemplate;
        break;
      case 'meal_plan':
        template = _mealPlanPromptTemplate;
        break;
      case 'modification':
        template = _modificationPromptTemplate;
        break;
      case 'nutrition_info':
        template = _nutritionInfoPromptTemplate;
        break;
      case 'shopping_list':
        template = _shoppingListPromptTemplate;
        break;
    }

    if (template == null) {
      throw Exception(
          "Prompt template '$templateType' not loaded or does not exist!");
    }

    final parts =
        template.split('<|eot_id|><|start_header_id|>user<|end_header_id|>');
    String systemContent = parts[0]
        .replaceAll(
            '<|begin_of_text|><|start_header_id|>system<|end_header_id|>', '')
        .trim();
    String userPromptSection = parts.length > 1 ? parts[1] : '';

    String topic = userPromptSection;
    substitutions.forEach((key, value) {
      topic = topic.replaceAll('{{$key}}', value);
    });

    topic = topic
        .replaceAll(
            '<|eot_id|><|start_header_id|>assistant<|end_header_id|>', '')
        .trim();

    final baseUrl = 'http://chefai-api-817179098283.asia-southeast1.run.app/stream';
    final queryParameters = {
      'topic': topic,
      'system_content': systemContent,
    };

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParameters);
    final request = http.Request('GET', uri);
    request.headers['accept'] = 'application/json';

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception(
            "API error: ${response.statusCode} ${await response.stream.bytesToString()}");
      }

      // --- THIS IS THE FIX ---
      // The stream is decoded, split by lines, and each line is parsed as JSON.
      await for (var line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isNotEmpty) {
          try {
            final jsonObject = json.decode(line);
            if (jsonObject['content'] != null) {
              yield jsonObject['content'];
            }
          } catch (e) {
            // Ignore lines that are not valid JSON
            print("Could not parse stream chunk as JSON: $line");
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
