import '../models/auth_session.dart';
import 'app_preferences.dart';
import 'auth_storage.dart';
import 'oauth_service.dart';
import 'readeck_api.dart';

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

class AuthService {
  final AuthStorage _storage;
  final OAuthService _oauthService;

  AuthService({AuthStorage? storage, OAuthService? oauthService})
      : _storage = storage ?? const AuthStorage(),
        _oauthService = oauthService ?? OAuthService();

  Future<AuthSession?> restoreSession() async {
    final session = await _storage.readSession();
    if (session != null) {
      await AppPreferences.saveCredentials(
        baseUrl: session.baseUrl,
        accessToken: session.accessToken,
      );
    }
    return session;
  }

  Future<PendingOAuthFlow> startAuthorization(String rawBaseUrl) async {
    final baseUrl = normalizeBaseUrl(rawBaseUrl);
    final pkce = _oauthService.createPkcePair();
    final state = _oauthService.createState();

    final registration = await _oauthService.registerClient(baseUrl: baseUrl);
    final pending = PendingOAuthFlow(
      baseUrl: baseUrl,
      clientId: registration.clientId,
      redirectUri: OAuthService.redirectUri,
      codeVerifier: pkce.verifier,
      state: state,
      scope: OAuthService.requestedScope,
      createdAt: DateTime.now(),
    );

    await _storage.writePendingFlow(pending);
    return pending;
  }

  Uri buildAuthorizationUri(PendingOAuthFlow pendingFlow) {
    return _oauthService.buildAuthorizationUri(
      baseUrl: pendingFlow.baseUrl,
      clientId: pendingFlow.clientId,
      codeChallenge: _oauthService.buildCodeChallenge(
        pendingFlow.codeVerifier,
      ),
      state: pendingFlow.state,
      redirectUri: pendingFlow.redirectUri,
      scope: pendingFlow.scope,
    );
  }

  Future<AuthSession> completeAuthorization(Uri callbackUri) async {
    final pending = await _storage.readPendingFlow();
    if (pending == null) {
      throw const AuthException('No OAuth sign-in is in progress. Start again.');
    }

    if (pending.isExpired) {
      await _storage.clearPendingFlow();
      throw const AuthException('The sign-in window expired. Start again.');
    }

    final returnedState = callbackUri.queryParameters['state'];
    if (returnedState != pending.state) {
      await _storage.clearPendingFlow();
      throw const AuthException('The OAuth state did not match the login request.');
    }

    final error = callbackUri.queryParameters['error'];
    if (error != null) {
      final description = callbackUri.queryParameters['error_description'];
      await _storage.clearPendingFlow();
      throw AuthException(description ?? error);
    }

    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      await _storage.clearPendingFlow();
      throw const AuthException('The OAuth callback did not include an authorization code.');
    }

    try {
      final tokenResponse = await _oauthService.exchangeAuthorizationCode(
        baseUrl: pending.baseUrl,
        code: code,
        codeVerifier: pending.codeVerifier,
      );

      final session = AuthSession(
        baseUrl: pending.baseUrl,
        accessToken: tokenResponse.accessToken,
        scope: tokenResponse.scope,
      );

      final api = ReadeckApi.fromSession(session);
      try {
        await api.getProfile();
      } on ReadeckApiException catch (error) {
        throw AuthException(
          'OAuth sign-in succeeded, but profile validation failed (${error.statusCode}).',
        );
      } finally {
        api.dispose();
      }

      await _storage.writeSession(session);
      await AppPreferences.saveCredentials(
        baseUrl: session.baseUrl,
        accessToken: session.accessToken,
      );
      await _storage.clearPendingFlow();
      return session;
    } on OAuthServiceException catch (error) {
      await _storage.clearPendingFlow();
      throw AuthException(error.message);
    } on AuthException {
      await _storage.clearPendingFlow();
      rethrow;
    }
  }

  Future<void> signOut({AuthSession? session}) async {
    final currentSession = session ?? await _storage.readSession();
    if (currentSession != null) {
      try {
        await _oauthService.revokeToken(
          baseUrl: currentSession.baseUrl,
          accessToken: currentSession.accessToken,
        );
      } on OAuthServiceException {
        // Always clear the local session, even if remote revoke fails.
      }
    }

    await clearSession();
  }

  Future<void> clearSession() async {
    await _storage.clearSession();
    await _storage.clearPendingFlow();
    await AppPreferences.clearCredentials();
  }

  Future<void> cancelPendingAuthorization() {
    return _storage.clearPendingFlow();
  }

  bool isRedirectUri(Uri uri) {
    return uri.scheme == 'readeck' &&
        uri.host == 'oauth' &&
        uri.path == '/callback';
  }

  static String normalizeBaseUrl(String rawBaseUrl) {
    return rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }
}