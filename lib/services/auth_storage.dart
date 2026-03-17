import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_session.dart';

class AuthStorage {
  static const _baseUrlKey = 'base_url';
  static const _accessTokenKey = 'access_token';
  static const _scopeKey = 'scope';

  static const _pendingBaseUrlKey = 'pending_base_url';
  static const _pendingClientIdKey = 'pending_client_id';
  static const _pendingRedirectUriKey = 'pending_redirect_uri';
  static const _pendingCodeVerifierKey = 'pending_code_verifier';
  static const _pendingStateKey = 'pending_state';
  static const _pendingScopeKey = 'pending_scope';
  static const _pendingCreatedAtKey = 'pending_created_at';

  final FlutterSecureStorage _secureStorage;

  const AuthStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<AuthSession?> readSession() async {
    final baseUrl = await _secureStorage.read(key: _baseUrlKey);
    final accessToken = await _secureStorage.read(key: _accessTokenKey);

    if (baseUrl == null || accessToken == null) {
      return null;
    }

    final scope = await _secureStorage.read(key: _scopeKey) ?? '';
    return AuthSession(
      baseUrl: baseUrl,
      accessToken: accessToken,
      scope: scope,
    );
  }

  Future<void> writeSession(AuthSession session) async {
    await _secureStorage.write(key: _baseUrlKey, value: session.baseUrl);
    await _secureStorage.write(
      key: _accessTokenKey,
      value: session.accessToken,
    );
    await _secureStorage.write(key: _scopeKey, value: session.scope);
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _baseUrlKey);
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _scopeKey);
    await _secureStorage.delete(key: 'token');
  }

  Future<PendingOAuthFlow?> readPendingFlow() async {
    final baseUrl = await _secureStorage.read(key: _pendingBaseUrlKey);
    final clientId = await _secureStorage.read(key: _pendingClientIdKey);
    final redirectUri = await _secureStorage.read(key: _pendingRedirectUriKey);
    final codeVerifier = await _secureStorage.read(
      key: _pendingCodeVerifierKey,
    );
    final state = await _secureStorage.read(key: _pendingStateKey);
    final scope = await _secureStorage.read(key: _pendingScopeKey);
    final createdAtRaw = await _secureStorage.read(key: _pendingCreatedAtKey);

    if (baseUrl == null ||
        clientId == null ||
        redirectUri == null ||
        codeVerifier == null ||
        state == null ||
        scope == null ||
        createdAtRaw == null) {
      return null;
    }

    final createdAtMillis = int.tryParse(createdAtRaw);
    if (createdAtMillis == null) {
      await clearPendingFlow();
      return null;
    }

    return PendingOAuthFlow(
      baseUrl: baseUrl,
      clientId: clientId,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
      state: state,
      scope: scope,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }

  Future<void> writePendingFlow(PendingOAuthFlow flow) async {
    await _secureStorage.write(key: _pendingBaseUrlKey, value: flow.baseUrl);
    await _secureStorage.write(key: _pendingClientIdKey, value: flow.clientId);
    await _secureStorage.write(
      key: _pendingRedirectUriKey,
      value: flow.redirectUri,
    );
    await _secureStorage.write(
      key: _pendingCodeVerifierKey,
      value: flow.codeVerifier,
    );
    await _secureStorage.write(key: _pendingStateKey, value: flow.state);
    await _secureStorage.write(key: _pendingScopeKey, value: flow.scope);
    await _secureStorage.write(
      key: _pendingCreatedAtKey,
      value: flow.createdAt.millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> clearPendingFlow() async {
    await _secureStorage.delete(key: _pendingBaseUrlKey);
    await _secureStorage.delete(key: _pendingClientIdKey);
    await _secureStorage.delete(key: _pendingRedirectUriKey);
    await _secureStorage.delete(key: _pendingCodeVerifierKey);
    await _secureStorage.delete(key: _pendingStateKey);
    await _secureStorage.delete(key: _pendingScopeKey);
    await _secureStorage.delete(key: _pendingCreatedAtKey);
  }
}