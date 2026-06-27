// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

class ArticleSummaryException implements Exception {
  final String message;

  ArticleSummaryException(this.message);

  @override
  String toString() => 'ArticleSummaryException: $message';
}

class ArticleSummaryService {
  final http.Client _client;

  ArticleSummaryService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> summarizeWithAzureOpenAi({
    required String endpoint,
    required String apiKey,
    required String articleHtml,
  }) async {
    final parsedEndpoint = Uri.tryParse(endpoint.trim());
    if (parsedEndpoint == null || !parsedEndpoint.isAbsolute) {
      throw ArticleSummaryException('Invalid Azure OpenAI endpoint URL.');
    }

    final prompt = '''Summarize this article in a few bullet points (less than 10).\n\nArticle content:\n$articleHtml''';

    final response = await _client.post(
      parsedEndpoint,
      headers: {
        'Content-Type': 'application/json',
        'api-key': apiKey,
      },
      body: jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content': 'You summarize web articles into concise bullet points.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'temperature': 0.3,
      }),
    );

    developer.log(
      'Azure OpenAI summarize response status=${response.statusCode} endpoint=${parsedEndpoint.toString()}',
      name: 'ArticleSummaryService',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArticleSummaryException(
        _buildAzureErrorMessage(response.statusCode, response.body),
      );
    }

    final body = _parseJsonMap(response.body);
    if (body == null) {
      throw ArticleSummaryException('Azure OpenAI returned invalid JSON.');
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw ArticleSummaryException('Azure OpenAI response did not include choices.');
    }

    final firstChoice = choices.first as Map<String, dynamic>;
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw ArticleSummaryException('Azure OpenAI response message is missing.');
    }

    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw ArticleSummaryException('Azure OpenAI returned an empty summary.');
    }

    return content.trim();
  }

  String _buildAzureErrorMessage(int statusCode, String responseBody) {
    final parsed = _parseJsonMap(responseBody);
    final error = parsed?['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code']?.toString();
      final message = error['message']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        if (code != null && code.trim().isNotEmpty) {
          return 'Azure OpenAI error ($statusCode, $code): $message';
        }
        return 'Azure OpenAI error ($statusCode): $message';
      }
    }

    final compactBody = responseBody.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compactBody.isNotEmpty) {
      final truncated = compactBody.length > 240
          ? '${compactBody.substring(0, 240)}...'
          : compactBody;
      return 'Azure OpenAI request failed ($statusCode): $truncated';
    }

    return 'Azure OpenAI request failed ($statusCode).';
  }

  Map<String, dynamic>? _parseJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}
