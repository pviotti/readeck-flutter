import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_session.dart';
import '../models/bookmark.dart';
import '../repositories/bookmark_repository.dart';
import '../services/bookmark_cache_database.dart';
import '../services/readeck_api.dart';

class BookmarksScreen extends StatefulWidget {
  final AuthSession session;
  final Future<void> Function() onSignedOut;
  final Future<void> Function() onSessionExpired;

  const BookmarksScreen({
    super.key,
    required this.session,
    required this.onSignedOut,
    required this.onSessionExpired,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late final ReadeckApi _api;
  late final BookmarkRepository _repository;
  final List<Bookmark> _bookmarks = [];
  int _totalCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _showArchived = false;
  bool _showingCachedData = false;
  String? _error;
  int _loadVersion = 0;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _api = ReadeckApi.fromSession(widget.session);
    _repository = BookmarkRepository(
      api: _api,
      cacheDb: BookmarkCacheDatabase(),
    );
    _loadBookmarks();
  }

  @override
  void dispose() {
    _repository.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final currentLoad = ++_loadVersion;

    setState(() {
      _loading = true;
      _error = null;
      _showingCachedData = false;
    });

    try {
      await _repository
          .streamFirstPage(archived: _showArchived, limit: _pageSize)
          .listen((value) {
            if (!mounted || currentLoad != _loadVersion) return;
            setState(() {
              _bookmarks
                ..clear()
                ..addAll(value.bookmarks);
              _totalCount = value.totalCount;
              _showingCachedData = value.fromCache;
              _error = null;
            });
          })
          .asFuture<void>();
    } catch (e) {
      if (await _handleAuthError(e)) {
        return;
      }
      if (!mounted || currentLoad != _loadVersion) return;
      setState(() => _error = 'Failed to load bookmarks.');
    } finally {
      if (mounted && currentLoad == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _bookmarks.length >= _totalCount) return;

    setState(() => _loadingMore = true);
    try {
      final response = await _repository.fetchPage(
        limit: _pageSize,
        offset: _bookmarks.length,
        archived: _showArchived,
      );
      setState(() {
        _bookmarks.addAll(response.bookmarks);
        _totalCount = response.totalCount;
      });
    } catch (error) {
      if (await _handleAuthError(error)) {
        return;
      }
      // Silently fail on "load more" — user can retry by scrolling again.
    } finally {
      setState(() => _loadingMore = false);
    }
  }

  void _switchView(bool archived) {
    if (_showArchived == archived) return;
    setState(() {
      _showArchived = archived;
      _bookmarks.clear();
      _totalCount = 0;
    });
    _loadBookmarks();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onSignedOut();
  }

  Future<void> _openBookmark(Bookmark bookmark) async {
    final uri = Uri.tryParse(bookmark.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _thumbnailUrl(Bookmark bookmark) {
    if (bookmark.thumbnailSrc == null) return '';
    final src = bookmark.thumbnailSrc!;
    if (src.startsWith('http')) return src;
    return '${widget.session.baseUrl}$src';
  }

  Future<bool> _handleAuthError(Object error) async {
    if (error is ReadeckApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      await widget.onSessionExpired();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_showArchived ? 'Read' : 'Unread')),
      drawer: NavigationDrawer(
        selectedIndex: _showArchived ? 1 : 0,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          _switchView(index == 1);
        },
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text(
              'Bookmarks',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: Text('Unread'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.archive_outlined),
            selectedIcon: Icon(Icons.archive),
            label: Text('Read'),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
            onTap: _logout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadBookmarks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_bookmarks.isEmpty) {
      return const Center(
        child: Text('No unread bookmarks. You\'re all caught up!'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBookmarks,
      child: Column(
        children: [
          if (_showingCachedData)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Showing cached data (offline mode).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount:
                  _bookmarks.length + (_bookmarks.length < _totalCount ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _bookmarks.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _loadMore();
                  });
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final bookmark = _bookmarks[index];
                return Dismissible(
                  key: Key(bookmark.id),
                  direction: _showArchived
                      ? DismissDirection.none
                      : DismissDirection.horizontal,
                  background: Container(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.archive,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Archive',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  secondaryBackground: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Delete',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.delete,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ],
                    ),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.endToStart) {
                      return showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete bookmark'),
                          content: Text('Permanently delete "${bookmark.title}"?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    }
                    return true;
                  },
                  onDismissed: (direction) async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (direction == DismissDirection.endToStart) {
                      try {
                        await _repository.deleteBookmark(bookmark.id);
                        await _loadBookmarks();
                      } catch (error) {
                        if (await _handleAuthError(error)) {
                          return;
                        }
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Failed to delete bookmark.')),
                        );
                        await _loadBookmarks();
                      }
                    } else {
                      try {
                        await _repository.archiveBookmark(bookmark.id);
                        await _loadBookmarks();
                      } catch (error) {
                        if (await _handleAuthError(error)) {
                          return;
                        }
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Failed to archive bookmark.')),
                        );
                        await _loadBookmarks();
                      }
                    }
                  },
                  child: _BookmarkTile(
                    bookmark: bookmark,
                    thumbnailUrl: _thumbnailUrl(bookmark),
                    onTap: () => _openBookmark(bookmark),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final String thumbnailUrl;
  final VoidCallback onTap;

  const _BookmarkTile({
    required this.bookmark,
    required this.thumbnailUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnailUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    thumbnailUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookmark.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (bookmark.siteName.isNotEmpty) bookmark.siteName,
                      if (bookmark.readingTime > 0)
                        '${bookmark.readingTime} min read',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (bookmark.labels.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: bookmark.labels
                          .map(
                            (label) => Chip(
                              label: Text(label),
                              labelStyle: theme.textTheme.labelSmall,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (bookmark.isMarked)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
