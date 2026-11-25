import 'package:flutter/services.dart';

/// Owns landscape / portrait transitions for the Chart tab.
///
/// Always restore system UI and orientations on [dispose].
class OrientationController {
  OrientationController();

  bool _landscape = false;
  bool get isLandscape => _landscape;

  Future<void> enterLandscape() async {
    if (_landscape) return;
    _landscape = true;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> enterPortrait() async {
    if (!_landscape) return;
    _landscape = false;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> toggle() =>
      _landscape ? enterPortrait() : enterLandscape();

  /// Must be called from the ChartScreen dispose path.
  Future<void> restore() async {
    _landscape = false;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
