// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:readeck/services/tts_chunker.dart';

void main() {
  test('splits long text into bounded chunks', () {
    const chunker = TtsChunker(maxChunkLength: 20);
    const text = 'Sentence one. Sentence two is longer. Sentence three.';

    final chunks = chunker.chunk(text);
    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      expect(chunk.text.length <= 20, isTrue);
      expect(chunk.start < chunk.end, isTrue);
    }
    expect(chunks.first.start, equals(0));
    expect(chunks.last.end <= text.length, isTrue);
  });

  test('respects start offset for resume', () {
    const chunker = TtsChunker(maxChunkLength: 15);
    const text = 'Alpha beta gamma delta epsilon zeta eta theta';

    final chunks = chunker.chunk(text, startOffset: 12);
    expect(chunks, isNotEmpty);
    expect(chunks.first.start >= 12, isTrue);
  });
}
