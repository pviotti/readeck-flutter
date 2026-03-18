import '../models/bookmark.dart';
import '../services/bookmark_cache_database.dart';
import '../services/readeck_api.dart';

class BookmarkStreamValue {
  final List<Bookmark> bookmarks;
  final int totalCount;
  final bool fromCache;

  const BookmarkStreamValue({
    required this.bookmarks,
    required this.totalCount,
    required this.fromCache,
  });
}

class BookmarkRepository {
  final ReadeckApi _api;
  final BookmarkCacheDatabase _cacheDb;

  BookmarkRepository({
    required ReadeckApi api,
    required BookmarkCacheDatabase cacheDb,
  }) : _api = api,
       _cacheDb = cacheDb;

  Stream<BookmarkStreamValue> streamFirstPage({
    required bool archived,
    int limit = 30,
  }) async* {
    final cached = await _cacheDb.fetchTopBookmarks(
      archived: archived,
      limit: limit,
    );

    if (cached.isNotEmpty) {
      yield BookmarkStreamValue(
        bookmarks: cached,
        totalCount: cached.length,
        fromCache: true,
      );
    }

    try {
      final remote = await _api.getBookmarks(
        limit: limit,
        offset: 0,
        archived: archived,
      );

      await _cacheDb.replaceTopBookmarks(
        archived: archived,
        bookmarks: remote.bookmarks,
        limit: limit,
      );

      yield BookmarkStreamValue(
        bookmarks: remote.bookmarks,
        totalCount: remote.totalCount,
        fromCache: false,
      );
    } catch (error) {
      if (cached.isEmpty) {
        rethrow;
      }
    }
  }

  Future<BookmarksResponse> fetchPage({
    required bool archived,
    required int offset,
    int limit = 30,
  }) {
    return _api.getBookmarks(limit: limit, offset: offset, archived: archived);
  }

  Future<BookmarkCreateResponse> createBookmark({
    required String url,
    String? title,
    List<String>? labels,
  }) {
    return _api.createBookmark(url: url, title: title, labels: labels);
  }

  Future<void> archiveBookmark(String id) async {
    await _api.archiveBookmark(id);
    await _cacheDb.archiveBookmark(id);
  }

  Future<void> deleteBookmark(String id) async {
    await _api.deleteBookmark(id);
    await _cacheDb.deleteBookmark(id);
  }

  void dispose() {
    _cacheDb.dispose();
  }
}
