// SPDX-License-Identifier: GPL-3.0-or-later

class TtsChunk {
  final int start;
  final int end;
  final String text;

  const TtsChunk({required this.start, required this.end, required this.text});
}

class TtsChunker {
  final int maxChunkLength;

  const TtsChunker({this.maxChunkLength = 400});

  List<TtsChunk> chunk(String text, {int startOffset = 0}) {
    if (text.isEmpty || startOffset >= text.length) {
      return const [];
    }

    final chunks = <TtsChunk>[];
    var cursor = startOffset < 0 ? 0 : startOffset;

    while (cursor < text.length) {
      final remaining = text.length - cursor;
      final span = remaining <= maxChunkLength ? remaining : maxChunkLength;
      var end = cursor + span;

      if (end < text.length) {
        final split = _findSplitPoint(text, cursor, end);
        if (split > cursor) {
          end = split;
        }
      }

      final chunkText = text.substring(cursor, end).trim();
      if (chunkText.isNotEmpty) {
        final realStart = _adjustStartForTrim(text, cursor, end);
        final realEnd = _adjustEndForTrim(text, cursor, end);
        chunks.add(TtsChunk(start: realStart, end: realEnd, text: chunkText));
      }
      cursor = end;
    }

    return chunks;
  }

  int _findSplitPoint(String text, int start, int end) {
    final preferred = RegExp(r'[\.!\?;:]\s|\n');
    for (var i = end - 1; i > start; i--) {
      final segment = text.substring(i - 1, i + 1 > text.length ? text.length : i + 1);
      if (preferred.hasMatch(segment)) {
        return i + 1;
      }
    }

    for (var i = end - 1; i > start; i--) {
      if (text[i] == ' ') {
        return i + 1;
      }
    }
    return end;
  }

  int _adjustStartForTrim(String text, int start, int end) {
    var i = start;
    while (i < end && text[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  int _adjustEndForTrim(String text, int start, int end) {
    var i = end;
    while (i > start && text[i - 1].trim().isEmpty) {
      i--;
    }
    return i;
  }
}