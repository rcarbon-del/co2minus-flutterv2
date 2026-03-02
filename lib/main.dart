import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCJ8Xl1wEACNi9b-njB3k2uKY9Mk9aSH0U",
      appId: "1:935965368269:web:587620ae15ceb711676e84",
      messagingSenderId: "935965368269",
      projectId: "co2-abvlnt",
      authDomain: "co2-abvlnt.firebaseapp.com",
      storageBucket: "co2-abvlnt.firebasestorage.app",
      measurementId: "G-D2PGDK5M9J",
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget { 
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CO2Minus',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D3E50),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          displayMedium: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A5A5A),
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}
