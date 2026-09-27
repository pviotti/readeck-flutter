// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class ArticleTextExtractor {
  const ArticleTextExtractor();

  String extractForTts(String html) {
    if (html.trim().isEmpty) {
      return '';
    }

    final document = html_parser.parse(html);
    document.querySelectorAll('script, style, noscript').forEach((element) {
      element.remove();
    });

    for (final element in document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, div, li, br, tr')) {
      element.nodes.add(dom.Text(' '));
    }

    final text = document.body?.text ?? document.documentElement?.text ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}