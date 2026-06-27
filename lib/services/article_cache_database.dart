// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class ArticleCacheDatabase {
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
  }

  Future<void> clearAllArticles() async {
    final db = await _database;
    db.execute('DELETE FROM article_cache;');
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
