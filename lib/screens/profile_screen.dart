import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart'; // Import FirestoreService
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onProfileUpdated;
  const ProfileScreen({super.key, required this.onProfileUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final FirestoreService _firestoreService = FirestoreService(); // Instance of FirestoreService
  User? _user;
  String? _profileImageUrl; // Changed to handle both path and URL
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = _authService.getCurrentUser();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    setState(() => _isLoading = true);
    // Load the image path/URL from Firestore
    final imageUrl = await _firestoreService.getUserProfileImage();
    if (mounted) {
      setState(() {
        _profileImageUrl = imageUrl;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    if (!kIsWeb) {
      var status = await Permission.photos.status;
      if (status.isDenied) {
        status = await Permission.photos.request();
      }
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Photo permission is permanently denied. Please enable it in settings.")),
        );
        await openAppSettings();
        return;
      }
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Photo permission is required to upload an image.")),
        );
        return;
      }
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      String imageValueToSave;
      if (kIsWeb) {
        // For web, image_picker returns a temporary URL that can be used directly.
        imageValueToSave = pickedFile.path;
      } else {
        // For mobile, we save the local file path.
        imageValueToSave = pickedFile.path;
      }
      
      // Save the path/URL to Firestore
      await _firestoreService.saveUserProfileImage(imageValueToSave);
      if (mounted) {
        setState(() {
          _profileImageUrl = imageValueToSave;
        });
        widget.onProfileUpdated();
      }
    }
  }

  Future<void> _logout() async {
    await _authService.signOut(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade200,
                        // --- UPDATED: Cross-platform image display ---
                        backgroundImage: _profileImageUrl != null
                            ? (kIsWeb
                                ? NetworkImage(_profileImageUrl!)
                                : FileImage(File(_profileImageUrl!)) as ImageProvider)
                            : (_user?.photoURL != null
                                ? NetworkImage(_user!.photoURL!)
                                : null),
                        child:
                            _profileImageUrl == null && _user?.photoURL == null
                                ? const Icon(Icons.person,
                                    size: 60, color: Colors.grey)
                                : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("Tap to change picture"),
                    const SizedBox(height: 32),
                    Text(
                      _user?.displayName ?? 'No Name',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _user?.email ?? 'No Email',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
