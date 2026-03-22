import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class AppPreferences {
  static const _channel = MethodChannel('it.pviotti.readeck/prefs');

  /// Persists credentials for the Android share handler.
  /// No-op on non-Android platforms where the channel is not registered.
  static Future<void> saveCredentials({
    required String baseUrl,
    required String accessToken,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('saveCredentials', {
      'baseUrl': baseUrl,
      'accessToken': accessToken,
    });
  }

  static Future<void> clearCredentials() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('clearCredentials');
  }
}
