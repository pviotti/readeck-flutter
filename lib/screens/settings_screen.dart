// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../services/article_cache_database.dart';
import '../services/auth_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ArticleCacheDatabase _articleCacheDb;
  late final AuthStorage _authStorage;
  final _endpointController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loading = true;
  bool _clearing = false;
  bool _savingAiSettings = false;
  String? _error;
  String? _aiSettingsError;
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _articleCacheDb = ArticleCacheDatabase();
    _authStorage = const AuthStorage();
    _loadCacheSize();
    _loadAiSettings();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _articleCacheDb.dispose();
    super.dispose();
  }

  Future<void> _loadAiSettings() async {
    try {
      final endpoint = await _authStorage.readAzureOpenAiEndpoint() ?? '';
      final apiKey = await _authStorage.readAzureOpenAiKey() ?? '';
      if (!mounted) return;
      _endpointController.text = endpoint;
      _apiKeyController.text = apiKey;
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiSettingsError = 'Failed to load Azure OpenAI settings.');
    }
  }

  Future<void> _saveAiSettings() async {
    final endpoint = _endpointController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    setState(() {
      _savingAiSettings = true;
      _aiSettingsError = null;
    });

    try {
      if (endpoint.isEmpty && apiKey.isEmpty) {
        await _authStorage.clearAzureOpenAiSettings();
      } else {
        final parsedUri = Uri.tryParse(endpoint);
        if (parsedUri == null || !parsedUri.isAbsolute) {
          throw const FormatException('Invalid endpoint URL');
        }
        if (apiKey.isEmpty) {
          throw const FormatException('Missing API key');
        }
        await _authStorage.writeAzureOpenAiSettings(
          endpoint: endpoint,
          apiKey: apiKey,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Azure OpenAI settings saved.')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiSettingsError = e.message == 'Missing API key'
            ? 'Please provide an API key or clear both fields.'
            : 'Please enter a valid endpoint URL.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiSettingsError = 'Failed to save Azure OpenAI settings.');
    } finally {
      if (mounted) {
        setState(() => _savingAiSettings = false);
      }
    }
  }

  Future<void> _loadCacheSize() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bytes = await _articleCacheDb.getCachedHtmlBytes();
      if (!mounted) return;
      setState(() {
        _cacheBytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to read cache size.';
        _loading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';

    const units = ['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    int unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  Future<void> _clearArticleCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear article cache'),
        content: const Text(
          'Delete all offline cached articles? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _clearing = true;
      _error = null;
    });

    try {
      await _articleCacheDb.clearAllArticles();
      await _loadCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Article cache cleared.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to clear cache.');
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RefreshIndicator(
        onRefresh: _loadCacheSize,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Azure OpenAI settings for article summarization',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _endpointController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Endpoint URL',
                        hintText: 'https://<resource>.openai.azure.com/...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API key',
                      ),
                    ),
                    if (_aiSettingsError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _aiSettingsError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _savingAiSettings ? null : _saveAiSettings,
                        icon: _savingAiSettings
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_savingAiSettings ? 'Saving...' : 'Save AI settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.offline_bolt_outlined),
                title: const Text('Article cache size'),
                subtitle: _loading
                    ? const Text('Loading...')
                    : _error != null
                    ? Text(_error!)
                    : Text(_formatBytes(_cacheBytes)),
                trailing: IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _loadCacheSize,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: (_loading || _clearing) ? null : _clearArticleCache,
              icon: _clearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(_clearing ? 'Clearing...' : 'Clear article cache'),
            ),
          ],
        ),
      ),
    );
  }
}
