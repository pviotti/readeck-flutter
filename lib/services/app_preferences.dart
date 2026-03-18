import 'package:flutter/services.dart';

class AppPreferences {
  static const _channel = MethodChannel('it.pviotti.readeck/prefs');

  static Future<void> saveCredentials({
    required String baseUrl,
    required String accessToken,
  }) async {
    await _channel.invokeMethod('saveCredentials', {
      'baseUrl': baseUrl,
      'accessToken': accessToken,
    });
  }

  static Future<void> clearCredentials() async {
    await _channel.invokeMethod('clearCredentials');
  }
}
