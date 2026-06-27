// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/repositories/article_repository.dart';
import 'package:readeck/services/article_cache_database.dart';
import 'package:readeck/services/readeck_api.dart';

class InMemoryArticleCacheDatabase extends ArticleCacheDatabase {
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<String?> fetchArticleHtml(String id) async => _cache[id];

  @override
  Future<void> upsertArticleHtml(String id, String html) async {
    _cache[id] = html;
  }

  @override
  Future<void> deleteArticle(String id) async {
    _cache.remove(id);
  }

  @override
  void dispose() {}
}

void main() {
  const baseUrl = 'https://readeck.example.com';
  const token = 'token';

  test('returns network article and stores it in cache', () async {
    const articleId = 'abc';
    const html = '<article>Hello</article>';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient((request) async {
        expect(request.method, equals('GET'));
        expect(
          request.url,
          equals(Uri.parse('$baseUrl/api/bookmarks/$articleId/article')),
        );
        expect(request.headers['accept'], equals('text/html'));
        return http.Response(html, 200, headers: {'content-type': 'text/html'});
      }),
    );

    final cache = InMemoryArticleCacheDatabase();
    final repository = ArticleRepository(api: api, cacheDb: cache);

    final result = await repository.loadArticle(articleId);

    expect(result.html, equals(html));
    expect(result.fromCache, isFalse);
    expect(await cache.fetchArticleHtml(articleId), equals(html));
  });

  test('falls back to cached article on server error', () async {
    const articleId = 'abc';
    const cachedHtml = '<article>Cached</article>';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'server'}), 500),
      ),
    );

    final cache = InMemoryArticleCacheDatabase();
    await cache.upsertArticleHtml(articleId, cachedHtml);

    final repository = ArticleRepository(api: api, cacheDb: cache);
    final result = await repository.loadArticle(articleId);

    expect(result.html, equals(cachedHtml));
    expect(result.fromCache, isTrue);
  });

  test('throws when server error and no cached article exists', () async {
    const articleId = 'abc';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'server'}), 500),
      ),
    );

    final cache = InMemoryArticleCacheDatabase();
    final repository = ArticleRepository(api: api, cacheDb: cache);

    await expectLater(
      repository.loadArticle(articleId),
      throwsA(isA<ReadeckApiException>()),
    );
  });

  test('keeps 404 behavior and does not fallback to cache', () async {
    const articleId = 'abc';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'not found'}), 404),
      ),
    );

    final cache = InMemoryArticleCacheDatabase();
    await cache.upsertArticleHtml(articleId, '<article>Old copy</article>');

    final repository = ArticleRepository(api: api, cacheDb: cache);

    await expectLater(
      repository.loadArticle(articleId),
      throwsA(
        isA<ReadeckApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(404),
        ),
      ),
    );
  });
}
