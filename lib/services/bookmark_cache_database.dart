import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/bookmark.dart';

class BookmarkCacheDatabase {
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
      CREATE TABLE IF NOT EXISTS bookmark_cache (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        site_name TEXT NOT NULL,
        description TEXT NOT NULL,
        reading_time INTEGER NOT NULL,
        read_progress INTEGER NOT NULL,
        is_marked INTEGER NOT NULL,
        is_archived INTEGER NOT NULL,
        labels_json TEXT NOT NULL,
        thumbnail_src TEXT,
        created TEXT NOT NULL,
        published TEXT
      );
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bookmark_cache_archived_created ON bookmark_cache(is_archived, created DESC);',
    );

    _db = db;
  }

  Future<List<Bookmark>> fetchTopBookmarks({
    required bool archived,
    int limit = 30,
  }) async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT *
      FROM bookmark_cache
      WHERE is_archived = ?
      ORDER BY created DESC
      LIMIT ?
      ''',
      [archived ? 1 : 0, limit],
    );

    return rs.map(_rowToBookmark).toList(growable: false);
  }

  Future<void> replaceTopBookmarks({
    required bool archived,
    required List<Bookmark> bookmarks,
    int limit = 30,
  }) async {
    final db = await _database;
    final capped = bookmarks.take(limit).toList(growable: false);

    db.execute('BEGIN TRANSACTION;');
    try {
      db.execute('DELETE FROM bookmark_cache WHERE is_archived = ?;', [
        archived ? 1 : 0,
      ]);
      for (final bookmark in capped) {
        _insertBookmark(db, bookmark);
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Future<void> archiveBookmark(String id) async {
    final db = await _database;
    db.execute('UPDATE bookmark_cache SET is_archived = 1 WHERE id = ?;', [id]);
    await _trimBucket(archived: true);
  }

  void dispose() {
    _db?.dispose();
    _db = null;
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  void _insertBookmark(Database db, Bookmark bookmark) {
    db.execute(
      '''
      INSERT INTO bookmark_cache (
        id,
        title,
        url,
        site_name,
        description,
        reading_time,
        read_progress,
        is_marked,
        is_archived,
        labels_json,
        thumbnail_src,
        created,
        published
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        url = excluded.url,
        site_name = excluded.site_name,
        description = excluded.description,
        reading_time = excluded.reading_time,
        read_progress = excluded.read_progress,
        is_marked = excluded.is_marked,
        is_archived = excluded.is_archived,
        labels_json = excluded.labels_json,
        thumbnail_src = excluded.thumbnail_src,
        created = excluded.created,
        published = excluded.published
      ;
      ''',
      [
        bookmark.id,
        bookmark.title,
        bookmark.url,
        bookmark.siteName,
        bookmark.description,
        bookmark.readingTime,
        bookmark.readProgress,
        bookmark.isMarked ? 1 : 0,
        bookmark.isArchived ? 1 : 0,
        jsonEncode(bookmark.labels),
        bookmark.thumbnailSrc,
        bookmark.created.toIso8601String(),
        bookmark.published?.toIso8601String(),
      ],
    );
  }

  Bookmark _rowToBookmark(Row row) {
    final labelsRaw = row['labels_json'] as String;
    final labelsDecoded = jsonDecode(labelsRaw) as List<dynamic>;

    return Bookmark(
      id: row['id'] as String,
      title: row['title'] as String,
      url: row['url'] as String,
      siteName: row['site_name'] as String,
      description: row['description'] as String,
      readingTime: row['reading_time'] as int,
      readProgress: row['read_progress'] as int,
      isMarked: (row['is_marked'] as int) == 1,
      isArchived: (row['is_archived'] as int) == 1,
      labels: labelsDecoded.map((e) => e as String).toList(growable: false),
      thumbnailSrc: row['thumbnail_src'] as String?,
      created: DateTime.parse(row['created'] as String),
      published: row['published'] != null
          ? DateTime.tryParse(row['published'] as String)
          : null,
    );
  }

  Future<void> _trimBucket({required bool archived, int limit = 30}) async {
    final db = await _database;
    final rs = db.select(
      '''
      SELECT id
      FROM bookmark_cache
      WHERE is_archived = ?
      ORDER BY created DESC
      ''',
      [archived ? 1 : 0],
    );

    if (rs.length <= limit) {
      return;
    }

    for (final row in rs.skip(limit)) {
      db.execute('DELETE FROM bookmark_cache WHERE id = ?;', [row['id']]);
    }
  }
}
