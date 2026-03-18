import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/services/readeck_api.dart';

void main() {
  group('ReadeckApi.createBookmark', () {
    test('posts a bookmark URL and optional title', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 202, headers: {'bookmark-id': 'bookmark-123'});
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      final response = await api.createBookmark(
        url: 'https://example.com/articles/1',
        title: 'Example article',
      );

      expect(response.bookmarkId, 'bookmark-123');
      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://readeck.example.com/api/bookmarks',
      );
      expect(capturedRequest.headers['Authorization'], 'Bearer token-123');
      expect(capturedRequest.headers['Content-Type'], 'application/json');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body, {
        'url': 'https://example.com/articles/1',
        'title': 'Example article',
      });
    });

    test('throws when bookmark creation is rejected', () async {
      final client = MockClient((_) async => http.Response('bad request', 400));

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      expect(
        () => api.createBookmark(url: 'https://example.com/articles/1'),
        throwsA(
          isA<ReadeckApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });
  });
}
