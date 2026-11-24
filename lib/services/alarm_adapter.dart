import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/alarm_state.dart';
import '../screens/contracts/stage2_contracts.dart' as ui;
import 'background_monitoring_service.dart';
import 'screen_mappers.dart';
import 'storage_service.dart';

/// Connects the screens' AlarmGateway to the foundation.
///
/// * The ringing alarm lives in the background-service isolate. Its state
///   reaches the UI through BackgroundMonitoringService.alarmStateStream and
///   is persisted by StorageService, so it can be recovered after the UI was
///   closed.
/// * Stopping goes through [stopAlarmAction] (AppServices.instance.stopAlarm),
///   which stops the real repeating audio. Success is only reported when the
///   persisted alarm state is no longer "ringing".
class AlarmAdapter implements ui.AlarmGateway {
  AlarmAdapter({
    required StorageService storage,
    required BackgroundMonitoringService monitoring,
    required Future<void> Function() stopAlarmAction,
    this.stopTimeout = const Duration(seconds: 5),
  })  : _storage = storage,
        _stopAlarmAction = stopAlarmAction {
    _sub = monitoring.alarmStateStream.listen((state) {
      if (!_changes.isClosed) _changes.add(alarmEventFromState(state));
    });
  }

  final StorageService _storage;
  final Future<void> Function() _stopAlarmAction;
  final Duration stopTimeout;
  final _changes = StreamController<ui.AlarmEvent?>.broadcast();
  StreamSubscription<AlarmState>? _sub;

  Future<ui.AlarmEvent?> _readSaved() async =>
      alarmEventFromState(await _storage.getAlarmState());

  /// Emits the current value first (recovered from storage), then every
  /// change. null = no alarm ringing (idle or stopped).
  @override
  Stream<ui.AlarmEvent?> watchActiveAlarm() {
    late final StreamController<ui.AlarmEvent?> controller;
    StreamSubscription<ui.AlarmEvent?>? changesSub;
    controller = StreamController<ui.AlarmEvent?>(
      onListen: () async {
        changesSub = _changes.stream.listen(controller.add);
        // On a cold start wait for the first frame, so the Navigator exists
        // before the first alarm event is delivered.
        await WidgetsBinding.instance.endOfFrame;
        final saved = await _readSaved();
        if (!controller.isClosed) controller.add(saved);
      },
      onCancel: () async {
        await changesSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Re-reads the persisted alarm state and emits it. Used when the app
  /// resumes or a notification is tapped, so a ringing alarm is shown.
  Future<void> refresh() async {
    final event = await _readSaved();
    if (!_changes.isClosed) _changes.add(event);
  }

  @override
  Future<void> stopAlarm() async {
    // Already stopped or idle: nothing to do (idempotent).
    if (!(await _storage.getAlarmState()).isRinging) return;

    await _stopAlarmAction();

    // The stop command is sent to the service isolate. Only report success
    // once the saved state confirms that the alarm is no longer ringing.
    final deadline = DateTime.now().add(stopTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!(await _storage.getAlarmState()).isRinging) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('The alarm did not confirm that it stopped.');
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _changes.close();
  }
}
