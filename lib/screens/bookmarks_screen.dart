import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bookmark.dart';
import '../services/readeck_api.dart';
import 'login_screen.dart';

class BookmarksScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const BookmarksScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late final ReadeckApi _api;
  final List<Bookmark> _bookmarks = [];
  int _totalCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _showArchived = false;
  String? _error;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _api = ReadeckApi(baseUrl: widget.baseUrl, token: widget.token);
    _loadBookmarks();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _api.getBookmarks(limit: _pageSize, offset: 0, archived: _showArchived);
      setState(() {
        _bookmarks
          ..clear()
          ..addAll(response.bookmarks);
        _totalCount = response.totalCount;
      });
    } catch (e) {
      setState(() => _error = 'Failed to load bookmarks.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _bookmarks.length >= _totalCount) return;

    setState(() => _loadingMore = true);
    try {
      final response = await _api.getBookmarks(
        limit: _pageSize,
        offset: _bookmarks.length,
        archived: _showArchived,
      );
      setState(() {
        _bookmarks.addAll(response.bookmarks);
        _totalCount = response.totalCount;
      });
    } catch (_) {
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
    final secureStorage = FlutterSecureStorage();
    await secureStorage.delete(key: 'base_url');
    await secureStorage.delete(key: 'token');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _confirmArchive(Bookmark bookmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive bookmark'),
        content: Text('Archive "${bookmark.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.archiveBookmark(bookmark.id);
      _loadBookmarks();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to archive bookmark.')),
      );
    }
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
    return '${widget.baseUrl}$src';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Read' : 'Unread'),
      ),
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
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      child: ListView.builder(
        itemCount: _bookmarks.length + (_bookmarks.length < _totalCount ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _bookmarks.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _BookmarkTile(
            bookmark: _bookmarks[index],
            thumbnailUrl: _thumbnailUrl(_bookmarks[index]),
            onTap: () => _openBookmark(_bookmarks[index]),
            onLongPress: () => _confirmArchive(_bookmarks[index]),
          );
        },
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final String thumbnailUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookmarkTile({
    required this.bookmark,
    required this.thumbnailUrl,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
