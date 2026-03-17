class AuthSession {
  final String baseUrl;
  final String accessToken;
  final String scope;

  const AuthSession({
    required this.baseUrl,
    required this.accessToken,
    required this.scope,
  });

  List<String> get scopes => scope
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

class PendingOAuthFlow {
  final String baseUrl;
  final String clientId;
  final String redirectUri;
  final String codeVerifier;
  final String state;
  final String scope;
  final DateTime createdAt;

  const PendingOAuthFlow({
    required this.baseUrl,
    required this.clientId,
    required this.redirectUri,
    required this.codeVerifier,
    required this.state,
    required this.scope,
    required this.createdAt,
  });

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(minutes: 10);
}