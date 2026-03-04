import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class UserProvider with ChangeNotifier {
  String? _displayName;
  String? _photoUrl;
  int _xp = 0;
  int _streak = 0;
  int _points = 0;
  bool _isLoading = true;

  String get displayName => _displayName ?? "Guest";
  String? get photoUrl => _photoUrl;
  int get xp => _xp;
  int get streak => _streak;
  int get points => _points;
  bool get isLoading => _isLoading;

  int get level => (_xp / 100).floor() + 1;
  int get nextLevelXp => (level) * 100;
  int get currentLevelXp => _xp % 100;

  String get playerTitle {
    if (level < 5) return "Eco Novice";
    if (level < 15) return "Eco Warrior";
    if (level < 30) return "Sustainability Pro";
    return "Planet Guardian";
  }

  UserProvider() {
    _initUser();
  }

  void _initUser() {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            await fetchUserData(user.uid);
          } else {
            _resetUser();
          }
        });
      } else {
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _resetUser() {
    _displayName = null;
    _photoUrl = null;
    _xp = 0;
    _streak = 0;
    _points = 0;
    _isLoading = false;
    notifyListeners();
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
          _xp = data['xp'] ?? 0;
          _streak = data['streak'] ?? 0;
          _points = data['points'] ?? 0;
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
