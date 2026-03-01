import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class UserProvider with ChangeNotifier {
  String? _displayName;
  String? _photoUrl;
  bool _isLoading = true;

  String get displayName => _displayName ?? "Guest";
  String? get photoUrl => _photoUrl;
  bool get isLoading => _isLoading;

  UserProvider() {
    _initUser();
  }

  void _initUser() {
    try {
      // Check if Firebase is initialized before accessing instances
      if (Firebase.apps.isNotEmpty) {
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            await fetchUserData(user.uid);
          } else {
            _displayName = null;
            _photoUrl = null;
            _isLoading = false;
            notifyListeners();
          }
        });
      } else {
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint("Firebase not initialized: $e");
    }
  }

  Future<void> fetchUserData(String uid) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (Firebase.apps.isNotEmpty) {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          _displayName = data['displayName'];
          _photoUrl = data['photoUrl'];
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
