import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_session.dart';
import '../services/auth_service.dart';
import '../services/oauth_service.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final ValueChanged<AuthSession> onAuthenticated;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSubscription;
  bool _loading = false;
  bool _awaitingRedirect = false;
  bool _handlingRedirect = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeDeepLinks();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeDeepLinks() async {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleRedirectUri(uri)),
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _awaitingRedirect = false;
          _loading = false;
          _error = 'Could not read the OAuth callback. Start again.';
        });
      },
    );

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      await _handleRedirectUri(initialUri);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final url = AuthService.normalizeBaseUrl(_urlController.text);

    try {
      final pendingFlow = await widget.authService.startAuthorization(url);
      final authorizationUri = widget.authService.buildAuthorizationUri(
        pendingFlow,
      );

      final launched = await launchUrl(
        authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await widget.authService.cancelPendingAuthorization();
        throw const AuthException(
          'Could not open the browser to continue the OAuth sign-in.',
        );
      }

      if (!mounted) return;
      setState(() {
        _awaitingRedirect = true;
        _loading = false;
      });
    } on AuthException catch (error) {
      setState(() {
        _awaitingRedirect = false;
        _error = error.message;
      });
    } on OAuthServiceException catch (error) {
      setState(() {
        _awaitingRedirect = false;
        _error = error.message;
      });
    } catch (_) {
      setState(() {
        _awaitingRedirect = false;
        _error = 'Could not start OAuth sign-in. Check the URL and try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleRedirectUri(Uri uri) async {
    if (!widget.authService.isRedirectUri(uri) || _handlingRedirect) {
      return;
    }

    setState(() {
      _handlingRedirect = true;
      _loading = true;
      _error = null;
    });

    try {
      final session = await widget.authService.completeAuthorization(uri);
      if (!mounted) return;
      widget.onAuthenticated(session);
    } on OAuthServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not complete the OAuth sign-in. Start again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _handlingRedirect = false;
          _awaitingRedirect = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancelPendingLogin() async {
    await widget.authService.cancelPendingAuthorization();
    if (!mounted) return;
    setState(() {
      _awaitingRedirect = false;
      _loading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Readeck',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect your instance with OAuth',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://readeck.example.com',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your Readeck server URL';
                      }
                      final uri = Uri.tryParse(value.trim());
                      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                        return 'Please enter a valid URL';
                      }
                      return null;
                    },
                  ),
                  if (_awaitingRedirect) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Finish sign-in in the browser, then return to the app.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In with OAuth'),
                  ),
                  if (_awaitingRedirect) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _handlingRedirect ? null : _cancelPendingLogin,
                      child: const Text('Start over'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
