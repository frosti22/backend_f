import 'package:flutter/material.dart';

import 'screens/test_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LogCkdTestApp());
}

class LogCkdTestApp extends StatelessWidget {
  const LogCkdTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'log.CKD Backend Tests',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A4CE0),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const TestHomeScreen(),
    );
  }
}
