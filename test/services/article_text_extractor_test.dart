// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:readeck/services/article_text_extractor.dart';

void main() {
  const extractor = ArticleTextExtractor();

  test('strips html/script/style and decodes basic entities', () {
    const html = '''
      <html>
        <head>
          <style>.hidden{display:none;}</style>
          <script>console.log('skip');</script>
        </head>
        <body>
          <h1>Title</h1>
          <p>Hello&nbsp;world &amp; everyone</p>
        </body>
      </html>
    ''';

    final text = extractor.extractForTts(html);
    expect(text, equals('Title Hello world & everyone'));
  });
}
