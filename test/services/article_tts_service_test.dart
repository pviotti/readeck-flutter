// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:readeck/services/article_tts_service.dart';

class _FakeFlutterTts extends FlutterTts {
  _FakeFlutterTts(this.speakResult);

  final dynamic speakResult;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => speakResult;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports when native speech starts successfully', () async {
    final service = ArticleTtsService(flutterTts: _FakeFlutterTts(1));

    expect(
      await service.speak(languageCode: 'en-US', text: 'Hello'),
      isTrue,
    );
    expect(service.isPlaying, isTrue);
  });

  test('reports when native speech fails to start', () async {
    final service = ArticleTtsService(flutterTts: _FakeFlutterTts(0));

    expect(
      await service.speak(languageCode: 'en-US', text: 'Hello'),
      isFalse,
    );
    expect(service.isPlaying, isFalse);
  });
}