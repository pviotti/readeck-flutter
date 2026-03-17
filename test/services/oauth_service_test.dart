import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/services/oauth_service.dart';

void main() {
  group('OAuthService', () {
    test('builds an RFC-compliant PKCE S256 challenge', () {
      final service = OAuthService();

      final challenge = service.buildCodeChallenge(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      );

      expect(challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('creates a URL-safe PKCE verifier without padding', () {
      final service = OAuthService(random: Random(1));

      final pkce = service.createPkcePair();

      expect(pkce.verifier, hasLength(64));
      expect(pkce.verifier, matches(RegExp(r'^[A-Za-z0-9]{64}$')));
      expect(pkce.challenge, isNot(contains('=')));
      expect(pkce.challenge, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('builds the authorization URL with PKCE and requested scope', () {
      final service = OAuthService();

      final uri = service.buildAuthorizationUri(
        baseUrl: 'https://readeck.example.com',
        clientId: 'client-123',
        codeChallenge: 'challenge-456',
        state: 'state-789',
      );

      expect(uri.toString(), startsWith('https://readeck.example.com/authorize'));
      expect(uri.queryParameters['client_id'], 'client-123');
      expect(uri.queryParameters['redirect_uri'], OAuthService.redirectUri);
      expect(uri.queryParameters['scope'], OAuthService.requestedScope);
      expect(uri.queryParameters['code_challenge'], 'challenge-456');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['state'], 'state-789');
    });

    test('registers a short-lived OAuth client with expected payload', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'client_id': 'client-123'}), 201);
      });
      final service = OAuthService(client: client);

      final registration = await service.registerClient(
        baseUrl: 'https://readeck.example.com',
      );

      expect(registration.clientId, 'client-123');
      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://readeck.example.com/api/oauth/client',
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['client_name'], 'Readeck Flutter');
      expect(body['client_uri'], 'https://example.com/readeck-flutter');
      expect(body['software_id'], 'it.pviotti.readeck');
      expect(body['software_version'], '0.1.0');
      expect(body['redirect_uris'], [OAuthService.redirectUri]);
      expect(body['grant_types'], ['authorization_code']);
      expect(body['response_types'], ['code']);
      expect(body['token_endpoint_auth_method'], 'none');
    });

    test('exchanges the authorization code for an access token', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'access_token': 'token-123',
            'scope': OAuthService.requestedScope,
          }),
          201,
        );
      });
      final service = OAuthService(client: client);

      final token = await service.exchangeAuthorizationCode(
        baseUrl: 'https://readeck.example.com',
        code: 'code-123',
        codeVerifier: 'verifier-456',
      );

      expect(token.accessToken, 'token-123');
      expect(token.scope, OAuthService.requestedScope);
      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://readeck.example.com/api/oauth/token',
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body, {
        'grant_type': 'authorization_code',
        'code': 'code-123',
        'code_verifier': 'verifier-456',
      });
    });
  });
}