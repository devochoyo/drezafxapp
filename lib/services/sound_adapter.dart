import 'dart:async';

import '../models/alarm_state.dart';
import '../screens/contracts/screen_contracts.dart' as ui;
import 'alarm_audio_service.dart';
import 'screen_mappers.dart';
import 'storage_service.dart';

/// Connects the screens' SoundGateway to the foundation's single
/// AlarmAudioService (AppServices.instance.alarm). It creates no player of
/// its own. AlarmAudioService already stops any earlier preview before
/// starting a new one, so previews cannot overlap.
class SoundAdapter implements ui.SoundGateway {
  SoundAdapter(this._audio, this._storage);

  final AlarmAudioService _audio;
  final StorageService _storage;

  @override
  Future<void> preview(String soundFile) async {
    final sound = soundFromFile(soundFile);
    // The real alarm plays in the background-service isolate. Do not let a
    // preview play on top of it.
    final saved = await _storage.getAlarmState();
    if (saved.isRinging) {
      throw StateError('An alarm is ringing. Stop it before previewing.');
    }
    await _audio.previewSound(sound);
  }

  @override
  Future<void> stopPreview() => _audio.stopPreview();

  /// The file being previewed, or null when nothing is previewing.
  @override
  Stream<String?> get previewingFile async* {
    String? current(AlarmState s) => s.isPreviewing ? s.sound?.fileName : null;
    yield current(_audio.state);
    yield* _audio.stateStream.map(current).distinct();
  }
}
