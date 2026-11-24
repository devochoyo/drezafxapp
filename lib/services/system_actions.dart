import 'package:flutter/services.dart';

/// Small Android-only helper implemented in MainActivity.kt.
/// It is used by the Settings screen in the UI isolate only.
class SystemActions {
  static const MethodChannel _channel = MethodChannel('com.drezafx.app/system');

  /// true = DrezaFx is exempt from battery optimisation,
  /// false = it is optimised, null = could not be determined.
  Future<bool?> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } catch (_) {
      return null;
    }
  }

  /// Opens the Android battery-optimisation settings. Throws on failure.
  Future<void> openBatterySettings() =>
      _channel.invokeMethod<void>('openBatterySettings');

  /// Version name from the installed package (e.g. "1.0.0").
  Future<String> appVersion() async {
    final version = await _channel.invokeMethod<String>('appVersion');
    if (version == null || version.isEmpty) {
      throw StateError('Version not available');
    }
    return version;
  }
}
