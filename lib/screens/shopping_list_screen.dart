import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class ShoppingListScreen extends StatefulWidget {
  // We need a GlobalKey to access the state from main.dart
  static final GlobalKey<_ShoppingListScreenState> shoppingListKey =
      GlobalKey();

  ShoppingListScreen() : super(key: shoppingListKey);

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

// The State class is now public so its methods can be called
class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  Map<String, List<String>> _shoppingLists = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshLists();
  }

  // This method is now public and can be called to refresh the data
  Future<void> refreshLists() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final lists = await _firestoreService.getShoppingLists();
    if (mounted) {
      setState(() {
        _shoppingLists = lists;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearList(String key) async {
    _shoppingLists.remove(key);
    await _firestoreService.saveShoppingLists(_shoppingLists);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Shopping Lists"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shoppingLists.isEmpty
              ? Center(
                  child: Text("No shopping lists generated yet.",
                      style: Theme.of(context).textTheme.titleMedium),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _shoppingLists.length,
                  itemBuilder: (context, index) {
                    final title = _shoppingLists.keys.elementAt(index);
                    final items = _shoppingLists[title]!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ExpansionTile(
                        title: Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.shopping_bag_outlined),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          onPressed: () => _clearList(title),
                        ),
                        children: items
                            .map((item) => ListTile(
                                  title: Text(item),
                                  dense: true,
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),
    );
  }
}
