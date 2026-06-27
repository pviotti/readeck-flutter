// SPDX-License-Identifier: GPL-3.0-or-later

import '../services/article_cache_database.dart';
import '../services/readeck_api.dart';

class ArticleLoadResult {
  final String html;
  final bool fromCache;

  const ArticleLoadResult({required this.html, required this.fromCache});
}

class ArticleRepository {
  final ReadeckApi _api;
  final ArticleCacheDatabase _cacheDb;

  ArticleRepository({required ReadeckApi api, required ArticleCacheDatabase cacheDb})
    : _api = api,
      _cacheDb = cacheDb;

  Future<ArticleLoadResult> loadArticle(String id) async {
    try {
      final html = await _api.getBookmarkArticle(id);
      await _cacheDb.upsertArticleHtml(id, html);
      return ArticleLoadResult(html: html, fromCache: false);
    } on ReadeckApiException catch (e) {
      if (e.statusCode == 404) {
        rethrow;
      }
      final cachedHtml = await _cacheDb.fetchArticleHtml(id);
      if (cachedHtml != null) {
        return ArticleLoadResult(html: cachedHtml, fromCache: true);
      }
      rethrow;
    } catch (_) {
      final cachedHtml = await _cacheDb.fetchArticleHtml(id);
      if (cachedHtml != null) {
        return ArticleLoadResult(html: cachedHtml, fromCache: true);
      }
      rethrow;
    }
  }
}
