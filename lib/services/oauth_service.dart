import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class OAuthServiceException implements Exception {
  final String message;
  final int? statusCode;

  const OAuthServiceException(this.message, {this.statusCode});

  @override
  String toString() => 'OAuthServiceException($statusCode): $message';
}

class PkcePair {
  final String verifier;
  final String challenge;

  const PkcePair({required this.verifier, required this.challenge});
}

class OAuthClientRegistration {
  final String clientId;

  const OAuthClientRegistration({required this.clientId});
}

class OAuthTokenResponse {
  final String accessToken;
  final String scope;

  const OAuthTokenResponse({required this.accessToken, required this.scope});
}

class OAuthService {
  static const redirectUri = 'readeck://oauth/callback';
  static const requestedScope =
      'bookmarks:read bookmarks:write profile:read';

  static const _clientName = 'Readeck Flutter app';
  static const _clientUri = 'https://github.com/pviotti/readeck-flutter';
  static const _softwareId = 'it.pviotti.readeck';
  static const _softwareVersion = '0.1.0';
  static const _tokenEndpointAuthMethod = 'none';

  final http.Client _client;
  final Random _random;

  OAuthService({http.Client? client, Random? random})
      : _client = client ?? http.Client(),
        _random = random ?? Random.secure();

  Future<OAuthClientRegistration> registerClient({
    required String baseUrl,
    String redirectUri = OAuthService.redirectUri,
  }) async {
    final response = await _client.post(
      _apiUri(baseUrl, '/oauth/client'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'client_name': _clientName,
        'client_uri': _clientUri,
        'software_id': _softwareId,
        'software_version': _softwareVersion,
        'redirect_uris': [redirectUri],
        'grant_types': ['authorization_code'],
        'response_types': ['code'],
        'token_endpoint_auth_method': _tokenEndpointAuthMethod,
      }),
    );

    final body = _decodeJson(response);
    if (response.statusCode != 201) {
      throw OAuthServiceException(
        _extractErrorMessage(body, response.body),
        statusCode: response.statusCode,
      );
    }

    final clientId = body['client_id'] as String?;
    if (clientId == null || clientId.isEmpty) {
      throw const OAuthServiceException('OAuth client registration failed.');
    }

    return OAuthClientRegistration(clientId: clientId);
  }

  Uri buildAuthorizationUri({
    required String baseUrl,
    required String clientId,
    required String codeChallenge,
    required String state,
    String redirectUri = OAuthService.redirectUri,
    String scope = requestedScope,
  }) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: _appendPath(base.path, '/authorize'),
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
  }

  Future<OAuthTokenResponse> exchangeAuthorizationCode({
    required String baseUrl,
    required String code,
    required String codeVerifier,
  }) async {
    final response = await _client.post(
      _apiUri(baseUrl, '/oauth/token'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': codeVerifier,
      }),
    );

    final body = _decodeJson(response);
    if (response.statusCode != 201) {
      throw OAuthServiceException(
        _extractErrorMessage(body, response.body),
        statusCode: response.statusCode,
      );
    }

    final accessToken = body['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthServiceException('OAuth token exchange failed.');
    }

    return OAuthTokenResponse(
      accessToken: accessToken,
      scope: body['scope'] as String? ?? '',
    );
  }

  Future<void> revokeToken({
    required String baseUrl,
    required String accessToken,
  }) async {
    final response = await _client.post(
      _apiUri(baseUrl, '/oauth/revoke'),
      headers: {
        ..._jsonHeaders,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'token': accessToken}),
    );

    if (response.statusCode != 200) {
      final body = _decodeJson(response);
      throw OAuthServiceException(
        _extractErrorMessage(body, response.body),
        statusCode: response.statusCode,
      );
    }
  }

  PkcePair createPkcePair() {
    final verifier = _randomString(length: 64);
    final challenge = buildCodeChallenge(verifier);
    return PkcePair(verifier: verifier, challenge: challenge);
  }

  String createState() => _randomString(length: 32);

  String buildCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  void dispose() {
    _client.close();
  }

  Uri _apiUri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: _appendPath(base.path, '/api$path'));
  }

  String _appendPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/') && basePath.length > 1
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    if (normalizedBase.isEmpty || normalizedBase == '/') {
      return suffix;
    }

    return '$normalizedBase$suffix';
  }

  String _randomString({required int length}) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  Map<String, String> get _jsonHeaders => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return const <String, dynamic>{};
    }

    return const <String, dynamic>{};
  }

  String _extractErrorMessage(Map<String, dynamic> body, String fallback) {
    final description = body['error_description'] as String?;
    if (description != null && description.isNotEmpty) {
      return description;
    }

    final errorCode = body['error'] as String?;
    if (errorCode != null && errorCode.isNotEmpty) {
      return errorCode;
    }

    if (fallback.isEmpty) {
      return 'OAuth request failed.';
    }

    return fallback;
  }
}