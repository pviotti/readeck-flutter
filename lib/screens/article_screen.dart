// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_session.dart';
import '../models/bookmark.dart';
import '../repositories/article_repository.dart';
import '../services/article_cache_database.dart';
import '../services/readeck_api.dart';

class ArticleScreen extends StatefulWidget {
  final AuthSession session;
  final Bookmark bookmark;
  final ReadeckApi api;

  const ArticleScreen({
    super.key,
    required this.session,
    required this.bookmark,
    required this.api,
  });

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final ArticleCacheDatabase _articleCacheDb;
  late final ArticleRepository _articleRepository;
  String? _html;
  bool _loading = true;
  bool _fromCache = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _articleCacheDb = ArticleCacheDatabase();
    _articleRepository = ArticleRepository(
      api: widget.api,
      cacheDb: _articleCacheDb,
    );
    _fetchArticle();
  }

  @override
  void dispose() {
    _articleCacheDb.dispose();
    super.dispose();
  }

  Future<void> _fetchArticle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _articleRepository.loadArticle(widget.bookmark.id);
      if (!mounted) return;
      setState(() {
        _html = result.html;
        _fromCache = result.fromCache;
        _loading = false;
      });
    } on ReadeckApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fromCache = false;
        _error = e.statusCode == 404
            ? 'No article content available for this bookmark.'
            : 'Failed to load article (${e.statusCode}).';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fromCache = false;
        _error = 'Failed to load article.';
        _loading = false;
      });
    }
  }

  Future<void> _openOriginalUrl() async {
    final uri = Uri.tryParse(widget.bookmark.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.bookmark.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open original URL',
            onPressed: _openOriginalUrl,
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _fetchArticle,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_fromCache)
          MaterialBanner(
            content: const Text('Showing offline copy of this article.'),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HtmlWidget(
              _html!,
              baseUrl: Uri.parse(widget.session.baseUrl),
              onTapUrl: (url) async {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                return true;
              },
            ),
          ),
        ),
      ],
    );
  }
}
