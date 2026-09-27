// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/models/bookmark.dart';
import 'package:readeck/repositories/bookmark_repository.dart';
import 'package:readeck/services/article_cache_database.dart';
import 'package:readeck/services/bookmark_cache_database.dart';
import 'package:readeck/services/readeck_api.dart';

// ---------------------------------------------------------------------------
// In-memory stubs
// ---------------------------------------------------------------------------

class InMemoryArticleCacheDatabase extends ArticleCacheDatabase {
  final Map<String, String> _cache = <String, String>{};
  final Map<String, Set<String>> _ttsStates = <String, Set<String>>{};

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
  Future<void> deleteAllArticleTtsStates(String articleId) async {
    _ttsStates.remove(articleId);
  }

  void addTtsState(String articleId, String languageCode) {
    _ttsStates.putIfAbsent(articleId, () => <String>{}).add(languageCode);
  }

  bool contains(String id) => _cache.containsKey(id);
  bool containsTtsState(String articleId, String languageCode) =>
      _ttsStates[articleId]?.contains(languageCode) ?? false;

  @override
  void dispose() {}
}

class InMemoryBookmarkCacheDatabase extends BookmarkCacheDatabase {
  final List<Bookmark> _bookmarks = [];
  final Set<String> _deleted = {};
  final Set<String> _archived = {};

  void addBookmark(Bookmark bookmark) => _bookmarks.add(bookmark);

  @override
  Future<List<Bookmark>> fetchTopBookmarks({
    required bool archived,
    int limit = 30,
  }) async => _bookmarks
      .where((bookmark) => bookmark.isArchived == archived)
      .take(limit)
      .toList();

  @override
  Future<void> replaceTopBookmarks({
    required bool archived,
    required List<Bookmark> bookmarks,
    int limit = 30,
  }) async {
    _bookmarks.removeWhere((bookmark) => bookmark.isArchived == archived);
    _bookmarks.addAll(bookmarks.take(limit));
  }

  @override
  Future<void> deleteBookmark(String id) async {
    _deleted.add(id);
  }

  @override
  Future<void> archiveBookmark(String id) async {
    _archived.add(id);
  }

  bool wasDeleted(String id) => _deleted.contains(id);
  bool wasArchived(String id) => _archived.contains(id);

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BookmarkRepository _makeRepository({
  required http.Client httpClient,
  required ArticleCacheDatabase articleCache,
  required InMemoryBookmarkCacheDatabase bookmarkCache,
}) {
  return BookmarkRepository(
    api: ReadeckApi(
      baseUrl: 'https://readeck.example.com',
      accessToken: 'token',
      client: httpClient,
    ),
    cacheDb: bookmarkCache,
    articleCacheDb: articleCache,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Bookmark _bookmark(String id) => Bookmark(
  id: id,
  title: 'Title',
  url: 'https://example.com/$id',
  siteName: 'Example',
  description: '',
  readingTime: 1,
  readProgress: 0,
  isMarked: false,
  isArchived: false,
  labels: const [],
  thumbnailSrc: null,
  created: DateTime.utc(2026),
  published: null,
);

void main() {
  group('BookmarkRepository.streamFirstPage', () {
    test(
      'does not mark cached data offline while remote request succeeds',
      () async {
        final bookmarkCache = InMemoryBookmarkCacheDatabase()
          ..addBookmark(_bookmark('cached'));
        final repo = _makeRepository(
          httpClient: MockClient(
            (_) async => http.Response(
              '[{"id":"remote","created":"2026-01-01T00:00:00Z"}]',
              200,
              headers: {'total-count': '1'},
            ),
          ),
          articleCache: InMemoryArticleCacheDatabase(),
          bookmarkCache: bookmarkCache,
        );

        final values = await repo.streamFirstPage(archived: false).toList();

        expect(values.map((value) => value.fromCache), [true, false]);
        expect(values.map((value) => value.isOffline), [false, false]);
      },
    );

    test('marks cached data offline after remote request fails', () async {
      final bookmarkCache = InMemoryBookmarkCacheDatabase()
        ..addBookmark(_bookmark('cached'));
      final repo = _makeRepository(
        httpClient: MockClient((_) async => throw Exception('offline')),
        articleCache: InMemoryArticleCacheDatabase(),
        bookmarkCache: bookmarkCache,
      );

      final values = await repo.streamFirstPage(archived: false).toList();

      expect(values.map((value) => value.fromCache), [true, true]);
      expect(values.map((value) => value.isOffline), [false, true]);
    });
  });

  group('BookmarkRepository.deleteBookmark', () {
    test('evicts matching article from article cache', () async {
      const id = 'bm-1';

      final articleCache = InMemoryArticleCacheDatabase();
      await articleCache.upsertArticleHtml(id, '<article>Cached</article>');

      final bookmarkCache = InMemoryBookmarkCacheDatabase();

      final repo = _makeRepository(
        httpClient: MockClient(
          (_) async => http.Response('', 204),
        ),
        articleCache: articleCache,
        bookmarkCache: bookmarkCache,
      );

      await repo.deleteBookmark(id);

      expect(articleCache.contains(id), isFalse);
      expect(bookmarkCache.wasDeleted(id), isTrue);
    });

    test('succeeds even when article cache eviction fails', () async {
      const id = 'bm-1';

      // Article cache that throws on delete
      final faultyArticleCache = _ThrowingArticleCacheDatabase();
      final bookmarkCache = InMemoryBookmarkCacheDatabase();

      final repo = _makeRepository(
        httpClient: MockClient(
          (_) async => http.Response('', 204),
        ),
        articleCache: faultyArticleCache,
        bookmarkCache: bookmarkCache,
      );

      // Should not throw even though article cache eviction fails
      await expectLater(repo.deleteBookmark(id), completes);
      expect(bookmarkCache.wasDeleted(id), isTrue);
    });
  });

  group('BookmarkRepository.archiveBookmark', () {
    test('keeps article cache while archiving bookmark', () async {
      const id = 'bm-1';

      final articleCache = InMemoryArticleCacheDatabase();
      await articleCache.upsertArticleHtml(id, '<article>Cached</article>');
      articleCache.addTtsState(id, 'en-US');
      articleCache.addTtsState(id, 'it-IT');
      articleCache.addTtsState('bm-2', 'en-US');

      final bookmarkCache = InMemoryBookmarkCacheDatabase();

      final repo = _makeRepository(
        httpClient: MockClient(
          (_) async => http.Response('{}', 200),
        ),
        articleCache: articleCache,
        bookmarkCache: bookmarkCache,
      );

      await repo.archiveBookmark(id);

      expect(articleCache.contains(id), isTrue);
      expect(articleCache.containsTtsState(id, 'en-US'), isFalse);
      expect(articleCache.containsTtsState(id, 'it-IT'), isFalse);
      expect(articleCache.containsTtsState('bm-2', 'en-US'), isTrue);
      expect(bookmarkCache.wasArchived(id), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Fault-injection stub
// ---------------------------------------------------------------------------

class _ThrowingArticleCacheDatabase extends ArticleCacheDatabase {
  @override
  Future<String?> fetchArticleHtml(String id) async => null;

  @override
  Future<void> upsertArticleHtml(String id, String html) async {}

  @override
  Future<void> deleteArticle(String id) async {
    throw Exception('Simulated article cache failure');
  }

  @override
  void dispose() {}
}
