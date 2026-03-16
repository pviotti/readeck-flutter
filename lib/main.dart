import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'screens/bookmarks_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secureStorage = FlutterSecureStorage();
  final baseUrl = await secureStorage.read(key: 'base_url');
  final token = await secureStorage.read(key: 'token');

  runApp(ReadeckApp(baseUrl: baseUrl, token: token));
}

class ReadeckApp extends StatelessWidget {
  final String? baseUrl;
  final String? token;

  const ReadeckApp({super.key, this.baseUrl, this.token});

  @override
  Widget build(BuildContext context) {
    final loggedIn = baseUrl != null && token != null;

    return MaterialApp(
      title: 'Readeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B6ABF),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B6ABF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: loggedIn
          ? BookmarksScreen(baseUrl: baseUrl!, token: token!)
          : const LoginScreen(),
    );
  }
}
