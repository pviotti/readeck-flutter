// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ArticleTtsService {
  final FlutterTts _flutterTts;
  bool _isPlaying = false;
  bool _isPaused = false;

  ArticleTtsService({FlutterTts? flutterTts}) : _flutterTts = flutterTts ?? FlutterTts();

  void _log(String message) {
    debugPrint('[TTS] $message');
  }

  Future<void> init() async {
    _log('init start');
    final sharedResult = await _flutterTts.setSharedInstance(true);
    _log('setSharedInstance(true) -> $sharedResult');
    final speechRateResult = await _flutterTts.setSpeechRate(0.5);
    _log('setSpeechRate(0.5) -> $speechRateResult');
    final volumeResult = await _flutterTts.setVolume(1.0);
    _log('setVolume(1.0) -> $volumeResult');
    final pitchResult = await _flutterTts.setPitch(1.0);
    _log('setPitch(1.0) -> $pitchResult');

    try {
      final engines = await _flutterTts.getEngines;
      _log('getEngines -> $engines');
    } catch (e) {
      _log('getEngines failed: $e');
    }

    try {
      final languages = await _flutterTts.getLanguages;
      _log('getLanguages count=${languages is List ? languages.length : 'unknown'} values=$languages');
    } catch (e) {
      _log('getLanguages failed: $e');
    }

    try {
      final voices = await _flutterTts.getVoices;
      _log('getVoices count=${voices is List ? voices.length : 'unknown'} sample=${voices is List && voices.isNotEmpty ? voices.take(5).toList() : voices}');
    } catch (e) {
      _log('getVoices failed: $e');
    }
    _log('init complete');
  }

  void setCompletionHandler(void Function() onCompleted) {
    _flutterTts.setCompletionHandler(() {
      _log('completion handler triggered');
      _isPlaying = false;
      _isPaused = false;
      onCompleted();
    });
  }

  void setErrorHandler(void Function(String message) onError) {
    _flutterTts.setErrorHandler((message) {
      _log('error handler triggered: $message');
      _isPlaying = false;
      _isPaused = false;
      onError(message);
    });
  }

  Future<void> speak({required String languageCode, required String text}) async {
    _log('speak start language=$languageCode textLength=${text.length}');
    final languageResult = await _flutterTts.setLanguage(languageCode);
    _log('setLanguage($languageCode) -> $languageResult');
    final stopResult = await _flutterTts.stop();
    _log('stop before speak -> $stopResult');
    _isPaused = false;
    final result = await _flutterTts.speak(text);
    _isPlaying = result == 1;
    _log('speak result=$result isPlaying=$_isPlaying');
  }

  Future<void> pause() async {
    _log('pause called');
    final result = await _flutterTts.pause();
    _log('pause result=$result');
    if (result == 1) {
      _isPlaying = false;
      _isPaused = true;
    }
    _log('pause state isPlaying=$_isPlaying isPaused=$_isPaused');
  }

  Future<void> resume({required String languageCode, required String text}) async {
    _log('resume start language=$languageCode textLength=${text.length}');
    final languageResult = await _flutterTts.setLanguage(languageCode);
    _log('setLanguage($languageCode) for resume -> $languageResult');
    final result = await _flutterTts.speak(text);
    _isPlaying = result == 1;
    _isPaused = false;
    _log('resume speak result=$result isPlaying=$_isPlaying isPaused=$_isPaused');
  }

  Future<void> stop() async {
    _log('stop called');
    final result = await _flutterTts.stop();
    _log('stop result=$result');
    _isPlaying = false;
    _isPaused = false;
  }

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
}
