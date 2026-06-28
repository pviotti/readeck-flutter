// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readeck/repositories/bookmark_repository.dart';
import 'package:readeck/services/article_cache_database.dart';
import 'package:readeck/services/bookmark_cache_database.dart';
import 'package:readeck/services/readeck_api.dart';

// ---------------------------------------------------------------------------
// In-memory stubs
// ---------------------------------------------------------------------------

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

  bool contains(String id) => _cache.containsKey(id);

  @override
  void dispose() {}
}

class InMemoryBookmarkCacheDatabase extends BookmarkCacheDatabase {
  final Set<String> _deleted = {};
  final Set<String> _archived = {};

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

void main() {
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
