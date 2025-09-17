import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'pantry_recipe_screen.dart';

class PantryScreen extends StatefulWidget {
  const PantryScreen({super.key});

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  Map<String, String> _pantryItems = {};
  final _itemController = TextEditingController();
  final _quantityController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPantry();
  }

  Future<void> _loadPantry() async {
    setState(() => _isLoading = true);
    final items = await _firestoreService.getPantry();
    if (mounted) {
      setState(() {
        _pantryItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _addItem() async {
    if (_itemController.text.isNotEmpty) {
      final currentItems = _pantryItems;
      currentItems[_itemController.text.trim()] =
          _quantityController.text.trim().isEmpty
              ? 'Some'
              : _quantityController.text.trim();

      await _firestoreService.savePantry(currentItems);
      if (mounted) {
        setState(() {
          _pantryItems = currentItems;
          _itemController.clear();
          _quantityController.clear();
        });
        FocusScope.of(context).unfocus();
      }
    }
  }

  Future<void> _removeItem(String key) async {
    final currentItems = _pantryItems;
    currentItems.remove(key);
    await _firestoreService.savePantry(currentItems);
    if (mounted) {
      setState(() {
        _pantryItems = currentItems;
      });
    }
  }

  void _generateFromPantry() {
    if (_pantryItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Your pantry is empty. Add some ingredients first!")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantryRecipeScreen(pantryItems: _pantryItems),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Pantry"),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: _generateFromPantry,
            tooltip: "Generate Recipe from Pantry",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _itemController,
                          decoration: InputDecoration(
                            labelText: "Ingredient",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _quantityController,
                          decoration: InputDecoration(
                            labelText: "Quantity (e.g., 200g)",
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: IconButton.filled(
                          icon: const Icon(Icons.add),
                          onPressed: _addItem,
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _pantryItems.isEmpty
                      ? Center(
                          child: Text(
                            "Your pantry is empty.\nAdd some ingredients to get started!",
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _pantryItems.length,
                          itemBuilder: (context, index) {
                            final key = _pantryItems.keys.elementAt(index);
                            final value = _pantryItems[key]!;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(value),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _removeItem(key),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
