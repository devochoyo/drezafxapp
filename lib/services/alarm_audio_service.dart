import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../models/alarm_sound.dart';
import '../models/alarm_state.dart';

/// Alarm and sound-preview playback.
///
/// The alarm sequence is Bell -> spoken announcement -> Bell -> spoken
/// announcement -> repeat until [stopAlarm]. Each supplied WAV already holds
/// one such cycle starting on the first bell strike, so the alarm loops the
/// file (see [AlarmSound]).
///
/// One instance per isolate. The background monitoring isolate owns the
/// instance that rings real alarms.
abstract class AlarmAudioService {
  AlarmState get state;
  Stream<AlarmState> get stateStream;

  /// Plays one cycle of [sound] once. Ignored while an alarm is ringing.
  /// Starting another preview replaces the current one.
  Future<void> previewSound(AlarmSound sound);

  Future<void> stopPreview();

  /// Starts repeating the alarm described by [alarm] (must have status
  /// `ringing` and a sound). Returns false and changes nothing if an alarm
  /// is already ringing, so sequences never overlap.
  Future<bool> startAlarm(AlarmState alarm);

  /// Stops the alarm immediately. Safe to call when nothing is ringing.
  Future<void> stopAlarm();

  /// Stops audio and releases players.
  Future<void> dispose();
}

/// [AlarmAudioService] implemented with the audioplayers package.
class AudioplayersAlarmAudioService implements AlarmAudioService {
  AudioplayersAlarmAudioService();

  AudioPlayer? _alarmPlayer;
  AudioPlayer? _previewPlayer;
  StreamSubscription<void>? _previewDone;
  final _controller = StreamController<AlarmState>.broadcast();
  AlarmState _state = AlarmState.idle;
  bool _disposed = false;

  /// Incremented by every start/stop so a slow `play()` that finishes after
  /// a stop can detect it was cancelled.
  int _generation = 0;

  /// Plays on the phone's ALARM volume stream and keeps the device awake.
  static final AudioContext _alarmContext = AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: true,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  @override
  AlarmState get state => _state;

  @override
  Stream<AlarmState> get stateStream => _controller.stream;

  void _emit(AlarmState state) {
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<AudioPlayer> _createPlayer(ReleaseMode mode) async {
    final player = AudioPlayer();
    await player.setAudioContext(_alarmContext);
    await player.setReleaseMode(mode);
    return player;
  }

  @override
  Future<void> previewSound(AlarmSound sound) async {
    if (_disposed || _state.isRinging) return;
    final generation = ++_generation;
    await _stopPreviewPlayer();
    final player = await _createPlayer(ReleaseMode.stop);
    if (generation != _generation || _disposed) {
      await player.dispose();
      return;
    }
    _previewPlayer = player;
    _previewDone = player.onPlayerComplete.listen((_) {
      if (_state.isPreviewing) _emit(AlarmState.idle);
    });
    _emit(AlarmState.previewing(sound));
    await player.play(AssetSource(sound.audioSourcePath));
  }

  @override
  Future<void> stopPreview() async {
    _generation++;
    await _stopPreviewPlayer();
    if (_state.isPreviewing) _emit(AlarmState.idle);
  }

  Future<void> _stopPreviewPlayer() async {
    await _previewDone?.cancel();
    _previewDone = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  @override
  Future<bool> startAlarm(AlarmState alarm) async {
    final sound = alarm.sound;
    if (_disposed || _state.isRinging || sound == null || !alarm.isRinging) {
      return false;
    }
    final generation = ++_generation;
    await _stopPreviewPlayer();
    // Mark as ringing BEFORE any await so a second call cannot overlap.
    _emit(alarm);
    try {
      final player = await _createPlayer(ReleaseMode.loop);
      if (generation != _generation || _disposed) {
        await player.dispose();
        return true; // stopped while starting
      }
      _alarmPlayer = player;
      await player.play(AssetSource(sound.audioSourcePath));
      if (generation != _generation) {
        await _stopAlarmPlayer(); // stop arrived while play() was pending
      }
      return true;
    } catch (_) {
      await _stopAlarmPlayer();
      _emit(AlarmState.idle);
      rethrow;
    }
  }

  @override
  Future<void> stopAlarm() async {
    _generation++;
    final previous = _state;
    await _stopAlarmPlayer();
    await _stopPreviewPlayer();
    if (previous.isRinging) {
      _emit(previous.asStopped(DateTime.now()));
    } else if (previous.isPreviewing) {
      _emit(AlarmState.idle);
    }
  }

  Future<void> _stopAlarmPlayer() async {
    final player = _alarmPlayer;
    _alarmPlayer = null;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    await _stopAlarmPlayer();
    await _stopPreviewPlayer();
    await _controller.close();
  }
}
