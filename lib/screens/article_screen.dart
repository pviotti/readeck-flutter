// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_session.dart';
import '../models/bookmark.dart';
import '../repositories/article_repository.dart';
import '../services/article_cache_database.dart';
import '../services/article_summary_service.dart';
import '../services/auth_storage.dart';
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
  late final ArticleSummaryService _summaryService;
  late final AuthStorage _authStorage;
  String? _html;
  bool _loading = true;
  bool _summarizing = false;
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
    _summaryService = ArticleSummaryService();
    _authStorage = const AuthStorage();
    _fetchArticle();
  }

  @override
  void dispose() {
    _summaryService.dispose();
    _articleCacheDb.dispose();
    super.dispose();
  }

  Future<void> _summarizeArticle() async {
    if (_html == null || _html!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No article content available to summarize.')),
      );
      return;
    }

    setState(() => _summarizing = true);

    try {
      final cachedSummary = await _articleCacheDb.fetchArticleSummary(widget.bookmark.id);
      if (cachedSummary != null && cachedSummary.trim().isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Article summary'),
            content: SingleChildScrollView(child: Text(cachedSummary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }

      final endpoint = await _authStorage.readAzureOpenAiEndpoint();
      final apiKey = await _authStorage.readAzureOpenAiKey();

      final trimmedEndpoint = (endpoint ?? '').trim();
      final trimmedApiKey = (apiKey ?? '').trim();
      debugPrint('Summarizing article with Azure OpenAI endpoint=$trimmedEndpoint');
      if (trimmedEndpoint.isEmpty && trimmedApiKey.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Azure OpenAI endpoint and API key are missing. Add them in Settings.',
            ),
          ),
        );
        return;
      }

      final summary = await _summaryService.summarizeWithAzureOpenAi(
        endpoint: trimmedEndpoint,
        apiKey: trimmedApiKey,
        articleHtml: _html!,
      );
      await _articleCacheDb.upsertArticleSummary(widget.bookmark.id, summary);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Article summary'),
          content: SingleChildScrollView(child: Text(summary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on ArticleSummaryException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e, st) {
      debugPrint('Unexpected summarize failure: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to summarize this article.')),
      );
    } finally {
      if (mounted) {
        setState(() => _summarizing = false);
      }
    }
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
            icon: _summarizing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.summarize_outlined),
            tooltip: 'Summarize article',
            onPressed: (_loading || _summarizing) ? null : _summarizeArticle,
          ),
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
