import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  // --- User Profile ---
  Future<void> saveUserProfileImage(String imagePath) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).set({
      'profileImagePath': imagePath,
    }, SetOptions(merge: true));
  }

  Future<String?> getUserProfileImage() async {
    if (_user == null) return null;
    final doc = await _db.collection('users').doc(_user!.uid).get();
    return doc.data()?['profileImagePath'];
  }

  // --- Pantry ---
  Future<void> savePantry(Map<String, String> pantryItems) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).set({
      'pantryItems': pantryItems,
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> getPantry() async {
    if (_user == null) return {};
    final doc = await _db.collection('users').doc(_user!.uid).get();
    final data = doc.data();
    if (data != null && data.containsKey('pantryItems')) {
      return Map<String, String>.from(data['pantryItems']);
    }
    return {};
  }

  // --- Favorites (Recipes) ---
  Future<void> saveFavorites(List<String> favorites) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).set({
      'favorites': favorites,
    }, SetOptions(merge: true));
  }

  Future<List<String>> getFavorites() async {
    if (_user == null) return [];
    final doc = await _db.collection('users').doc(_user!.uid).get();
    final data = doc.data();
    if (data != null && data.containsKey('favorites')) {
      return List<String>.from(data['favorites']);
    }
    return [];
  }

  // --- Saved Meal Plans ---
  Future<void> saveMealPlans(List<String> plans) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).set({
      'saved_plans': plans,
    }, SetOptions(merge: true));
  }

  Future<List<String>> getMealPlans() async {
    if (_user == null) return [];
    final doc = await _db.collection('users').doc(_user!.uid).get();
    final data = doc.data();
    if (data != null && data.containsKey('saved_plans')) {
      return List<String>.from(data['saved_plans']);
    }
    return [];
  }

  // --- Shopping Lists ---
  Future<void> saveShoppingLists(Map<String, List<String>> lists) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).set({
      'shopping_lists': lists,
    }, SetOptions(merge: true));
  }

  Future<Map<String, List<String>>> getShoppingLists() async {
    if (_user == null) return {};
    final doc = await _db.collection('users').doc(_user!.uid).get();
    final data = doc.data();
    if (data != null && data.containsKey('shopping_lists')) {
      final decoded = Map<String, dynamic>.from(data['shopping_lists']);
      return decoded
          .map((key, value) => MapEntry(key, List<String>.from(value)));
    }
    return {};
  }

  // --- Reviews (Ratings & Images) ---
  // --- THIS IS THE UPDATED METHOD ---
  Future<void> saveReview(String recipeId,
      {double? rating, String? imagePath, String? nutritionInfo}) async {
    if (_user == null) return;

    final reviewData = <String, dynamic>{};
    if (rating != null) reviewData['rating'] = rating;
    if (imagePath != null) reviewData['imagePath'] = imagePath;
    if (nutritionInfo != null) reviewData['nutritionInfo'] = nutritionInfo;

    if (reviewData.isNotEmpty) {
      await _db
          .collection('users')
          .doc(_user!.uid)
          .collection('reviews')
          .doc(recipeId)
          .set(reviewData, SetOptions(merge: true));
    }
  }

  Future<Map<String, dynamic>> getReview(String recipeId) async {
    if (_user == null) return {};
    final doc = await _db
        .collection('users')
        .doc(_user!.uid)
        .collection('reviews')
        .doc(recipeId)
        .get();
    return doc.data() ?? {};
  }
}
