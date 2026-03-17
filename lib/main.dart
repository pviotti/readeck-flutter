import 'package:flutter/material.dart';

import 'models/auth_session.dart';
import 'services/auth_service.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ReadeckApp(authService: AuthService()));
}

class ReadeckApp extends StatefulWidget {
  final AuthService authService;

  const ReadeckApp({super.key, required this.authService});

  @override
  State<ReadeckApp> createState() => _ReadeckAppState();
}

class _ReadeckAppState extends State<ReadeckApp> {
  AuthSession? _session;
  bool _loading = true;
  String? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _bootstrapError = null;
    });

    try {
      final session = await widget.authService.restoreSession();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _bootstrapError = 'Failed to restore the saved login.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() => _session = session);
  }

  Future<void> _handleSignedOut() async {
    await widget.authService.signOut(session: _session);
    if (!mounted) return;
    setState(() => _session = null);
  }

  Future<void> _handleSessionExpired() async {
    await widget.authService.clearSession();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
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
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_bootstrapError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_bootstrapError!),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _restoreSession,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_session == null) {
      return LoginScreen(
        authService: widget.authService,
        onAuthenticated: _handleAuthenticated,
      );
    }

    return BookmarksScreen(
      session: _session!,
      onSignedOut: _handleSignedOut,
      onSessionExpired: _handleSessionExpired,
    );
  }
}
