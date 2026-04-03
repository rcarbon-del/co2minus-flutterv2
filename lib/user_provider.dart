import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class UserProvider with ChangeNotifier {
  String? _name;
  String? _profilePicture;
  DateTime? _dob;
  int _xp = 0;
  int _streak = 0;
  int _aquaPoints = 0;
  String? _selectedTaskId;
  int _currentTabIndex = 0;
  
  // Impact Data
  double _dailyImpact = 0.0;
  double _previousDayImpact = 0.0;
  double _monthlyImpact = 0.0;
  double _energyImpact = 0.0;
  double _shoppingImpact = 0.0;
  double _transportImpact = 0.0;
  double _foodImpact = 0.0;

  bool _isLoading = true;
  bool _isLoadingChallenges = false;
  
  // Daily Tasks Data from Firestore
  List<Map<String, dynamic>> _dailyTasks = [];
  Map<String, dynamic>? _selectedTask;
  
  // Step Tracking
  int _currentSteps = 0;
  final int _stepGoal = 10000;
  bool _hasHealthPermission = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Health _health = Health();

  String get displayName => (_name?.split(' ').first) ?? "Guest";
  String? get photoUrl => _profilePicture;
  DateTime? get dob => _dob;
  int get xp => _xp;
  int get streak => _streak;
  int get points => _aquaPoints;
  int get aquaPoints => _aquaPoints;
  int get currentTabIndex => _currentTabIndex;
  
  double get dailyImpact => _dailyImpact;
  double get previousDayImpact => _previousDayImpact;
  double get monthlyImpact => _monthlyImpact;
  double get energyImpact => _energyImpact;
  double get shoppingImpact => _shoppingImpact;
  double get transportImpact => _transportImpact;
  double get foodImpact => _foodImpact;

  bool get isLoading => _isLoading;
  bool get isLoadingChallenges => _isLoadingChallenges;
  List<Map<String, dynamic>> get dailyTasks => _dailyTasks;
  Map<String, dynamic>? get selectedTask => _selectedTask;
  int get currentSteps => _currentSteps;
  int get stepGoal => _stepGoal;

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

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void _initUser() {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            await fetchUserData(user.uid);
            await fetchDailyChallenges();
            _checkHealthPermissions();
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
    _name = null;
    _profilePicture = null;
    _dob = null;
    _xp = 0;
    _streak = 0;
    _aquaPoints = 0;
    _selectedTaskId = null;
    _currentTabIndex = 0;
    _dailyImpact = 0.0;
    _previousDayImpact = 0.0;
    _monthlyImpact = 0.0;
    _energyImpact = 0.0;
    _shoppingImpact = 0.0;
    _transportImpact = 0.0;
    _foodImpact = 0.0;
    _isLoading = false;
    _selectedTask = null;
    _dailyTasks = [];
    _currentSteps = 0;
    notifyListeners();
  }

  // --- CHALLENGE LOGIC ---

  Future<void> fetchDailyChallenges() async {
    _isLoadingChallenges = true;
    notifyListeners();
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('challenge_data').get();
      List<Map<String, dynamic>> allChallenges = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        IconData icon = FontAwesomeIcons.leaf;
        String title = (data['title'] ?? "").toLowerCase();
        if (title.contains("waste") || title.contains("trash")) icon = FontAwesomeIcons.recycle;
        if (title.contains("energy") || title.contains("light") || title.contains("power")) icon = FontAwesomeIcons.bolt;
        if (title.contains("water") || title.contains("wash")) icon = FontAwesomeIcons.droplet;
        if (title.contains("plastic") || title.contains("bottle")) icon = FontAwesomeIcons.bottleWater;
        if (title.contains("walk") || title.contains("step") || title.contains("footprint")) icon = FontAwesomeIcons.shoePrints;

        return {
          ...data,
          "id": doc.id,
          "icon": icon,
          "progress": 0.0,
        };
      }).toList();

      if (allChallenges.isEmpty) {
        _dailyTasks = [];
      } else {
        DateTime now = DateTime.now();
        int seed = now.year * 10000 + now.month * 100 + now.day;
        allChallenges.shuffle(Random(seed));
        _dailyTasks = allChallenges.take(5).toList();

        // Restore selected task from ID
        if (_selectedTaskId != null) {
          try {
            _selectedTask = allChallenges.firstWhere((t) => t['id'] == _selectedTaskId);
            if (_selectedTask != null && _selectedTask!['hasStepCount'] == true) {
              fetchStepData();
            }
          } catch (_) {
            _selectedTask = null;
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching challenges: $e");
    } finally {
      _isLoadingChallenges = false;
      notifyListeners();
    }
  }

  void selectTask(Map<String, dynamic>? task) async {
    _selectedTask = task;
    _selectedTaskId = task?['id'];
    
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'selected_task_id': _selectedTaskId,
        });
      } catch (e) {
        debugPrint("Error persisting task selection: $e");
      }
    }

    if (task != null && task['hasStepCount'] == true) {
      fetchStepData();
    }
  }

  // --- IMPACT LOGIC ---

  Future<void> addCarbonFootprint(double amount, String category) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _dailyImpact += amount;
    _monthlyImpact += amount;
    
    if (category == 'transport') {
      _transportImpact += amount;
    } else if (category == 'energy') _energyImpact += amount;
    else if (category == 'shopping') _shoppingImpact += amount;
    else if (category == 'food') _foodImpact += amount;
    
    _xp += 10;
    _aquaPoints += 5;

    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'daily_impact': _dailyImpact,
        'monthly_impact': _monthlyImpact,
        'transport_impact': _transportImpact,
        'energy_impact': _energyImpact,
        'shopping_impact': _shoppingImpact,
        'food_impact': _foodImpact,
        'xp': _xp,
        'aqua_points': _aquaPoints,
      });
    } catch (e) {
      debugPrint("Error updating impact: $e");
    }
  }

  // --- HEALTH / STEP LOGIC ---

  Future<void> _checkHealthPermissions() async {
    if (await Permission.activityRecognition.isGranted) {
      final types = [HealthDataType.STEPS];
      bool? hasPermission = await _health.hasPermissions(types);
      _hasHealthPermission = hasPermission ?? false;
      if (_hasHealthPermission) {
        fetchStepData();
      }
    }
  }

  Future<void> requestHealthPermission() async {
    if (await Permission.activityRecognition.request().isGranted) {
      final types = [HealthDataType.STEPS];
      final permissions = [HealthDataAccess.READ];
      
      bool requested = await _health.requestAuthorization(types, permissions: permissions);
      _hasHealthPermission = requested;
      if (_hasHealthPermission) {
        fetchStepData();
      }
      notifyListeners();
    }
  }

  Future<void> fetchStepData() async {
    if (!_hasHealthPermission) return;

    DateTime now = DateTime.now();
    DateTime midnight = DateTime(now.year, now.month, now.day);

    try {
      int? steps = await _health.getTotalStepsInInterval(midnight, now);
      if (steps != null) {
        _currentSteps = steps;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching steps: $e");
    }
  }

  // --- AUTH METHODS ---

  Future<void> signUpWithEmail(String email, String password, String name, DateTime? dob) async {
    _isLoading = true;
    notifyListeners();
    try {
      UserCredential result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': name,
          'email': email,
          'date_of_birth': dob != null ? "${dob.month}/${dob.day}/${dob.year}" : null,
          'profile_picture': null,
          'xp': 0,
          'streak': 0,
          'aqua_points': 0,
          'daily_impact': 0.0,
          'previous_day_impact': 0.0,
          'monthly_impact': 0.0,
          'energy_impact': 0.0,
          'shopping_impact': 0.0,
          'transport_impact': 0.0,
          'food_impact': 0.0,
          'selected_task_id': null,
          'last_monthly_reset': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        await user.updateDisplayName(name);
      }
    } catch (e) {
      throw e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return; 
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential result = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = result.user;
      if (user != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'name': user.displayName,
            'email': user.email,
            'profile_picture': user.photoURL,
            'xp': 0,
            'streak': 0,
            'aqua_points': 0,
            'daily_impact': 0.0,
            'previous_day_impact': 0.0,
            'monthly_impact': 0.0,
            'energy_impact': 0.0,
            'shopping_impact': 0.0,
            'transport_impact': 0.0,
            'food_impact': 0.0,
            'last_monthly_reset': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      throw e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw e.toString();
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await _googleSignIn.signOut();
  }

  Future<void> fetchUserData(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (Firebase.apps.isNotEmpty) {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          _name = data['name'] ?? data['displayName'];
          _profilePicture = data['profile_picture'] ?? data['photoUrl'];
          
          if (data['date_of_birth'] != null && data['date_of_birth'] is String) {
             try {
               List<String> parts = (data['date_of_birth'] as String).split('/');
               if (parts.length == 3) {
                 _dob = DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
               }
             } catch (_) {}
          } else if (data['dob'] != null && data['dob'] is Timestamp) {
            _dob = (data['dob'] as Timestamp).toDate();
          }

          _xp = data['xp'] ?? 0;
          _streak = data['streak'] ?? 0;
          _aquaPoints = data['aqua_points'] ?? data['points'] ?? 0;
          _selectedTaskId = data['selected_task_id'];
          
          _dailyImpact = (data['daily_impact'] ?? 0.0).toDouble();
          _previousDayImpact = (data['previous_day_impact'] ?? 0.0).toDouble();
          _monthlyImpact = (data['monthly_impact'] ?? 0.0).toDouble();
          _energyImpact = (data['energy_impact'] ?? 0.0).toDouble();
          _shoppingImpact = (data['shopping_impact'] ?? 0.0).toDouble();
          _transportImpact = (data['transport_impact'] ?? 0.0).toDouble();
          _foodImpact = (data['food_impact'] ?? 0.0).toDouble();

          DateTime now = DateTime.now();
          bool shouldResetMonthly = false;
          if (data['last_monthly_reset'] != null) {
            DateTime lastReset = (data['last_monthly_reset'] as Timestamp).toDate();
            if (now.month != lastReset.month || now.year != lastReset.year) {
              shouldResetMonthly = true;
            }
          } else {
            shouldResetMonthly = true;
          }

          if (shouldResetMonthly) {
            _monthlyImpact = 0.0;
            await FirebaseFirestore.instance.collection('users').doc(uid).update({
              'monthly_impact': 0.0,
              'last_monthly_reset': FieldValue.serverTimestamp(),
            });
          }

          bool needsUpdate = false;
          Map<String, dynamic> updates = {};
          if (data['xp'] == null) { updates['xp'] = 0; needsUpdate = true; }
          if (data['streak'] == null) { updates['streak'] = 0; needsUpdate = true; }
          if (data['aqua_points'] == null) { updates['aqua_points'] = _aquaPoints; needsUpdate = true; }
          if (data['daily_impact'] == null) { updates['daily_impact'] = 0.0; needsUpdate = true; }
          if (data['previous_day_impact'] == null) { updates['previous_day_impact'] = 0.0; needsUpdate = true; }
          if (data['monthly_impact'] == null) { updates['monthly_impact'] = 0.0; needsUpdate = true; }
          if (data['energy_impact'] == null) { updates['energy_impact'] = 0.0; needsUpdate = true; }
          if (data['shopping_impact'] == null) { updates['shopping_impact'] = 0.0; needsUpdate = true; }
          if (data['transport_impact'] == null) { updates['transport_impact'] = 0.0; needsUpdate = true; }
          if (data['food_impact'] == null) { updates['food_impact'] = 0.0; needsUpdate = true; }
          if (!data.containsKey('selected_task_id')) { updates['selected_task_id'] = null; needsUpdate = true; }
          if (data['last_monthly_reset'] == null) { updates['last_monthly_reset'] = FieldValue.serverTimestamp(); needsUpdate = true; }
          
          if (needsUpdate) {
            await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);
          }
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
