import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static String baseUrl = _defaultBaseUrl();

  static String _defaultBaseUrl() {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android Studio emulator reaches the computer through 10.0.2.2.
      return 'http://192.168.100.93:3000';
    }

    return 'http://localhost:3000';
  }
}
