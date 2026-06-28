// SPDX-License-Identifier: GPL-3.0-or-later

class ArticleTtsState {
  final String articleId;
  final String languageCode;
  final String text;
  final int offset;
  final bool isPaused;
  final DateTime updatedAt;

  const ArticleTtsState({
    required this.articleId,
    required this.languageCode,
    required this.text,
    required this.offset,
    required this.isPaused,
    required this.updatedAt,
  });
}