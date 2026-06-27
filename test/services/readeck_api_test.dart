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

    test('omits title when it is null', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 202, headers: {'bookmark-id': 'bm-1'});
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await api.createBookmark(url: 'https://example.com/articles/1');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body.containsKey('title'), isFalse);
    });

    test('omits title when it is blank or whitespace-only', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 202, headers: {'bookmark-id': 'bm-1'});
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await api.createBookmark(
        url: 'https://example.com/articles/1',
        title: '   ',
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body.containsKey('title'), isFalse);
    });

    test('sends labels when provided', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 202, headers: {'bookmark-id': 'bm-1'});
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await api.createBookmark(
        url: 'https://example.com/articles/1',
        labels: ['dart', 'flutter'],
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['labels'], ['dart', 'flutter']);
    });

    test('omits labels when the list is empty', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 202, headers: {'bookmark-id': 'bm-1'});
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await api.createBookmark(
        url: 'https://example.com/articles/1',
        labels: [],
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body.containsKey('labels'), isFalse);
    });

    test('throws when bookmark creation is rejected', () async {
      final client = MockClient((_) async => http.Response('bad request', 400));

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await expectLater(
        api.createBookmark(url: 'https://example.com/articles/1'),
        throwsA(
          isA<ReadeckApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('throws when bookmark-id header is missing', () async {
      final client = MockClient((_) async => http.Response('', 202));

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-123',
        client: client,
      );

      await expectLater(
        api.createBookmark(url: 'https://example.com/articles/1'),
        throwsA(isA<ReadeckApiException>()),
      );
    });
  });

  group('ReadeckApi.getBookmarkArticle', () {
    test('returns article HTML on success', () async {
      late http.Request capturedRequest;
      const html = '<p>Hello <strong>world</strong></p>';
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(html, 200);
      });

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-abc',
        client: client,
      );

      final result = await api.getBookmarkArticle('bm-42');

      expect(result, html);
      expect(capturedRequest.method, 'GET');
      expect(
        capturedRequest.url.toString(),
        'https://readeck.example.com/api/bookmarks/bm-42/article',
      );
      expect(capturedRequest.headers['Authorization'], 'Bearer token-abc');
      expect(capturedRequest.headers['Accept'], 'text/html');
    });

    test('throws ReadeckApiException on 404', () async {
      final client = MockClient((_) async => http.Response('not found', 404));

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-abc',
        client: client,
      );

      await expectLater(
        api.getBookmarkArticle('bm-99'),
        throwsA(
          isA<ReadeckApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('throws ReadeckApiException on non-200 status', () async {
      final client = MockClient((_) async => http.Response('server error', 500));

      final api = ReadeckApi(
        baseUrl: 'https://readeck.example.com',
        accessToken: 'token-abc',
        client: client,
      );

      await expectLater(
        api.getBookmarkArticle('bm-1'),
        throwsA(
          isA<ReadeckApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });
  });
}
