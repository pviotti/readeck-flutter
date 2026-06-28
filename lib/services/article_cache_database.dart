// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/article_tts_state.dart';

class ArticleCacheDatabase {
  static const int ttsStateMaxRows = 50;
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = '${supportDir.path}/bookmark_cache.db';

    if (!Directory(supportDir.path).existsSync()) {
      Directory(supportDir.path).createSync(recursive: true);
    }

    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS article_cache (
        id TEXT PRIMARY KEY,
        html TEXT NOT NULL,
        summary TEXT,
        cached_at TEXT NOT NULL
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_cache_cached_at ON article_cache(cached_at DESC);',
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS article_tts_state (
        article_id TEXT NOT NULL,
        language_code TEXT NOT NULL,
        text TEXT NOT NULL,
        offset INTEGER NOT NULL,
        is_paused INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (article_id, language_code)
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_article_tts_state_updated_at ON article_tts_state(updated_at DESC);',
    );

    _db = db;
  }

  Future<String?> fetchArticleHtml(String id) async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT html
      FROM article_cache
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (rs.isEmpty) {
      return null;
    }

    return rs.first['html'] as String;
  }

  Future<void> upsertArticleHtml(String id, String html) async {
    final db = await _database;
    db.execute(
      '''
      INSERT INTO article_cache (id, html, cached_at)
      VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        html = excluded.html,
        cached_at = excluded.cached_at
      ;
      ''',
      [id, html, DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<String?> fetchArticleSummary(String id) async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT summary
      FROM article_cache
      WHERE id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (rs.isEmpty) {
      return null;
    }

    return rs.first['summary'] as String?;
  }

  Future<void> upsertArticleSummary(String id, String summary) async {
    final db = await _database;
    db.execute(
      '''
      INSERT INTO article_cache (id, html, summary, cached_at)
      VALUES (?, COALESCE((SELECT html FROM article_cache WHERE id = ?), ''), ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        summary = excluded.summary,
        cached_at = excluded.cached_at
      ;
      ''',
      [id, id, summary, DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<void> deleteArticle(String id) async {
    final db = await _database;
    db.execute('DELETE FROM article_cache WHERE id = ?;', [id]);
    db.execute('DELETE FROM article_tts_state WHERE article_id = ?;', [id]);
  }

  Future<void> clearAllArticles() async {
    final db = await _database;
    db.execute('DELETE FROM article_cache;');
    db.execute('DELETE FROM article_tts_state;');
  }

  Future<ArticleTtsState?> fetchArticleTtsState(String articleId, String languageCode) async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT article_id, language_code, text, offset, is_paused, updated_at
      FROM article_tts_state
      WHERE article_id = ? AND language_code = ?
      LIMIT 1
      ''',
      [articleId, languageCode],
    );

    if (rs.isEmpty) {
      return null;
    }

    final row = rs.first;
    return ArticleTtsState(
      articleId: row['article_id'] as String,
      languageCode: row['language_code'] as String,
      text: row['text'] as String,
      offset: row['offset'] as int,
      isPaused: (row['is_paused'] as int) == 1,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Future<void> upsertArticleTtsState({
    required String articleId,
    required String languageCode,
    required String text,
    required int offset,
    required bool isPaused,
  }) async {
    final db = await _database;
    db.execute(
      '''
      INSERT INTO article_tts_state (article_id, language_code, text, offset, is_paused, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(article_id, language_code) DO UPDATE SET
        text = excluded.text,
        offset = excluded.offset,
        is_paused = excluded.is_paused,
        updated_at = excluded.updated_at
      ;
      ''',
      [
        articleId,
        languageCode,
        text,
        offset,
        isPaused ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    db.execute(
      '''
      DELETE FROM article_tts_state
      WHERE (article_id, language_code) NOT IN (
        SELECT article_id, language_code
        FROM article_tts_state
        ORDER BY updated_at DESC
        LIMIT ?
      );
      ''',
      [ttsStateMaxRows],
    );
  }

  Future<void> deleteArticleTtsState(String articleId, String languageCode) async {
    final db = await _database;
    db.execute(
      'DELETE FROM article_tts_state WHERE article_id = ? AND language_code = ?;',
      [articleId, languageCode],
    );
  }

  Future<void> deleteAllArticleTtsStates(String articleId) async {
    final db = await _database;
    db.execute('DELETE FROM article_tts_state WHERE article_id = ?;', [articleId]);
  }

  Future<int> getCachedHtmlBytes() async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT COALESCE(SUM(LENGTH(CAST(html AS BLOB))), 0) AS total_bytes
      FROM article_cache
      ''',
    );

    if (rs.isEmpty) {
      return 0;
    }

    final value = rs.first['total_bytes'];
    if (value is int) {
      return value;
    }

    return 0;
  }

  void dispose() {
    _db?.dispose();
    _db = null;
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }
}
