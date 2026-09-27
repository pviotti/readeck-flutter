// SPDX-License-Identifier: GPL-3.0-or-later

import '../services/article_cache_database.dart';
import '../services/article_text_extractor.dart';
import '../services/readeck_api.dart';

class ArticleLoadResult {
  final String html;
  final bool fromCache;

  const ArticleLoadResult({required this.html, required this.fromCache});
}

class ArticleRepository {
  final ReadeckApi _api;
  final ArticleCacheDatabase _cacheDb;
  final ArticleTextExtractor _textExtractor;

  ArticleRepository({
    required ReadeckApi api,
    required ArticleCacheDatabase cacheDb,
    ArticleTextExtractor? textExtractor,
  })
    : _api = api,
      _cacheDb = cacheDb,
      _textExtractor = textExtractor ?? const ArticleTextExtractor();

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

  Future<String> getOrCreateTtsText(String id, {String? htmlHint}) async {
    final html = htmlHint ?? (await _cacheDb.fetchArticleHtml(id)) ?? (await loadArticle(id)).html;
    return _textExtractor.extractForTts(html);
  }

  Future<void> saveTtsState({
    required String id,
    required String languageCode,
    required String text,
    required int offset,
    required bool isPaused,
  }) {
    return _cacheDb.upsertArticleTtsState(
      articleId: id,
      languageCode: languageCode,
      text: text,
      offset: offset,
      isPaused: isPaused,
    );
  }

  Future<int> loadTtsResumeOffset(String id, String languageCode, String currentText) async {
    final state = await _cacheDb.fetchArticleTtsState(id, languageCode);
    if (state == null || state.text != currentText) {
      return 0;
    }
    if (state.offset < 0) {
      return 0;
    }
    if (state.offset > currentText.length) {
      return currentText.length;
    }
    return state.offset;
  }

  Future<void> clearTtsState(String id, String languageCode) {
    return _cacheDb.deleteArticleTtsState(id, languageCode);
  }
}
