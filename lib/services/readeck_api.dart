import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bookmark.dart';

class BookmarksResponse {
  final List<Bookmark> bookmarks;
  final int totalCount;

  const BookmarksResponse({required this.bookmarks, required this.totalCount});
}

class ReadeckApiException implements Exception {
  final int statusCode;
  final String message;

  ReadeckApiException(this.statusCode, this.message);

  @override
  String toString() => 'ReadeckApiException($statusCode): $message';
}

class ReadeckApi {
  final String baseUrl;
  final String token;
  final http.Client _client;

  ReadeckApi({required this.baseUrl, required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Uri _uri(String path, [Map<String, dynamic>? queryParameters]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path}/api$path',
      queryParameters: queryParameters,
    );
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _client.get(_uri('/profile'), headers: _headers);
    if (response.statusCode != 200) {
      throw ReadeckApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<BookmarksResponse> getBookmarks({
    int limit = 30,
    int offset = 0,
    bool archived = false,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      'is_archived': archived.toString(),
      'sort': '-created',
    };

    final response = await _client.get(
      _uri('/bookmarks', params),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw ReadeckApiException(response.statusCode, response.body);
    }

    final totalCount =
        int.tryParse(response.headers['total-count'] ?? '') ?? 0;
    final List<dynamic> body = jsonDecode(response.body) as List<dynamic>;
    final bookmarks = body
        .map((item) => Bookmark.fromJson(item as Map<String, dynamic>))
        .toList();

    return BookmarksResponse(bookmarks: bookmarks, totalCount: totalCount);
  }

  void dispose() {
    _client.close();
  }
}
