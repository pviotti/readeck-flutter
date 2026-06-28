// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/models/article_tts_state.dart';
import 'package:readeck/repositories/article_repository.dart';
import 'package:readeck/services/article_cache_database.dart';
import 'package:readeck/services/readeck_api.dart';

class InMemoryArticleCacheDatabase extends ArticleCacheDatabase {
  final Map<String, String> _cache = <String, String>{};
  final Map<String, String> _summaries = <String, String>{};
  final Map<String, Map<String, dynamic>> _tts = <String, Map<String, dynamic>>{};

  @override
  Future<String?> fetchArticleHtml(String id) async => _cache[id];

  @override
  Future<void> upsertArticleHtml(String id, String html) async {
    _cache[id] = html;
  }

  @override
  Future<void> deleteArticle(String id) async {
    _cache.remove(id);
    _summaries.remove(id);
  }

  @override
  Future<String?> fetchArticleSummary(String id) async => _summaries[id];

  @override
  Future<void> upsertArticleSummary(String id, String summary) async {
    _summaries[id] = summary;
  }

  @override
  Future<void> upsertArticleTtsState({
    required String articleId,
    required String languageCode,
    required String text,
    required int offset,
    required bool isPaused,
  }) async {
    _tts['$articleId::$languageCode'] = {
      'articleId': articleId,
      'languageCode': languageCode,
      'text': text,
      'offset': offset,
      'isPaused': isPaused,
    };
  }

  @override
  Future<ArticleTtsState?> fetchArticleTtsState(String articleId, String languageCode) async {
    final value = _tts['$articleId::$languageCode'];
    if (value == null) return null;
    return ArticleTtsState(
      articleId: articleId,
      languageCode: languageCode,
      text: value['text'] as String,
      offset: value['offset'] as int,
      isPaused: value['isPaused'] as bool,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deleteArticleTtsState(String articleId, String languageCode) async {
    _tts.remove('$articleId::$languageCode');
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

  test('extracts plain text for TTS', () async {
    const articleId = 'tts-1';
    const html = '<article><h1>Hello</h1><p>world &amp; friends</p></article>';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient((_) async => http.Response(html, 200)),
    );
    final cache = InMemoryArticleCacheDatabase();
    final repository = ArticleRepository(api: api, cacheDb: cache);

    final text = await repository.getOrCreateTtsText(articleId);
    expect(text, equals('Hello world & friends'));
  });

  test('returns resume offset only when text matches state', () async {
    const articleId = 'tts-2';
    const languageCode = 'en-US';
    const text = 'One two three four';

    final api = ReadeckApi(
      baseUrl: baseUrl,
      accessToken: token,
      client: MockClient((_) async => http.Response('<p>$text</p>', 200)),
    );
    final cache = InMemoryArticleCacheDatabase();
    final repository = ArticleRepository(api: api, cacheDb: cache);

    await repository.saveTtsState(
      id: articleId,
      languageCode: languageCode,
      text: text,
      offset: 4,
      isPaused: true,
    );

    final matchedOffset = await repository.loadTtsResumeOffset(articleId, languageCode, text);
    final mismatchOffset = await repository.loadTtsResumeOffset(
      articleId,
      languageCode,
      '$text changed',
    );

    expect(matchedOffset, equals(4));
    expect(mismatchOffset, equals(0));
  });
}
