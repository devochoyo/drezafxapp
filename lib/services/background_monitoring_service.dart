import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/alarm_state.dart';
import '../models/currency_pair.dart';
import '../models/market_price.dart';
import '../models/monitoring_status.dart';
import 'alarm_audio_service.dart';
import 'market_data_factory.dart';
import 'monitoring_engine.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Message names exchanged between the UI isolate and the service isolate.
class MonitoringMessages {
  // UI -> service
  static const alertsChanged = 'alertsChanged';
  static const stopAlarm = 'stopAlarm';
  static const watchPair = 'watchPair';
  static const unwatchPair = 'unwatchPair';
  static const requestSnapshot = 'requestSnapshot';
  static const reconnectMarket = 'reconnectMarket';
  static const stopService = 'stopService';
  // service -> UI
  static const status = 'status';
  static const price = 'price';
  static const alarmState = 'alarmState';
  static const alertsUpdated = 'alertsUpdated';
}

/// UI-side controller for the Android foreground service that keeps
/// monitoring alive while the app is minimised or the screen is locked.
///
/// The market connection, alert evaluation and alarm audio run inside the
/// service isolate ([drezaFxMonitoringEntryPoint]). This class starts/stops
/// it and re-exposes its events as streams.
///
/// Status: implemented but NOT verified on a device in Batch 1. See README.
class BackgroundMonitoringService {
  BackgroundMonitoringService(this._storage);

  final StorageService _storage;
  final FlutterBackgroundService _service = FlutterBackgroundService();

  final _statusCtrl = StreamController<MonitoringStatus>.broadcast();
  final _priceCtrl = StreamController<MarketPrice>.broadcast();
  final _alarmCtrl = StreamController<AlarmState>.broadcast();
  final _alertsUpdatedCtrl = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  MonitoringStatus _status = MonitoringStatus.stopped;
  bool _configured = false;

  /// Last status reported by the service (stopped if it is not running).
  MonitoringStatus get currentStatus => _status;

  /// Monitoring status changes.
  Stream<MonitoringStatus> get statusStream => _statusCtrl.stream;

  /// Live prices for watched pairs (only flows while the service runs).
  Stream<MarketPrice> get priceStream => _priceCtrl.stream;

  /// Alarm state changes from the service isolate.
  Stream<AlarmState> get alarmStateStream => _alarmCtrl.stream;

  /// Emits when the service changed stored alerts/history (an alert
  /// triggered, an alarm was acknowledged).
  Stream<void> get alertsUpdatedStream => _alertsUpdatedCtrl.stream;

  /// Configures the service and subscribes to its events. Call once at app
  /// start, after the notification channels exist (see AppServices).
  Future<void> configure() async {
    if (_configured) return;
    _configured = true;
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: drezaFxMonitoringEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: LocalNotificationService.monitoringChannelId,
        initialNotificationTitle: 'DrezaFx',
        initialNotificationContent: 'Starting price monitoring...',
        foregroundServiceNotificationId:
            LocalNotificationService.monitoringNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    _subs.add(_service.on(MonitoringMessages.status).listen((data) {
      if (data == null) return;
      _status = MonitoringStatus.fromJson(data);
      _statusCtrl.add(_status);
    }));
    _subs.add(_service.on(MonitoringMessages.price).listen((data) {
      if (data != null) _priceCtrl.add(MarketPrice.fromJson(data));
    }));
    _subs.add(_service.on(MonitoringMessages.alarmState).listen((data) {
      if (data != null) _alarmCtrl.add(AlarmState.fromJson(data));
    }));
    _subs.add(_service.on(MonitoringMessages.alertsUpdated).listen((_) {
      _alertsUpdatedCtrl.add(null);
    }));

    // If the service survived while the UI was closed, ask it to report.
    if (await isRunning()) _service.invoke(MonitoringMessages.requestSnapshot);
  }

  Future<bool> isRunning() => _service.isRunning();

  /// Starts the foreground service. Must be called while the app is in the
  /// foreground (Android 12+ forbids starting it from the background), after
  /// notification permission was requested on Android 13+.
  Future<void> start() async {
    if (await isRunning()) {
      _service.invoke(MonitoringMessages.alertsChanged);
      return;
    }
    _status = _status.copyWith(serviceState: MonitoringServiceState.starting);
    _statusCtrl.add(_status);
    await _service.startService();
  }

  /// Stops monitoring. A ringing alarm is NOT stopped; use [stopAlarm].
  Future<void> stop() async {
    if (await isRunning()) _service.invoke(MonitoringMessages.stopService);
    _status = MonitoringStatus.stopped;
    _statusCtrl.add(_status);
  }

  /// Tells the service to reload alerts from storage.
  /// Asks the service to re-open the market-data connection (used after the
  /// credentials change and by the Dashboard "Retry" button). Starts the
  /// service first if it is not running.
  Future<void> reconnectMarket() async {
    if (await isRunning()) {
      _service.invoke(MonitoringMessages.reconnectMarket);
    } else {
      await start();
    }
  }

  void notifyAlertsChanged() {
    _service.invoke(MonitoringMessages.alertsChanged);
  }

  /// Keeps [pair] subscribed (and its prices flowing) without an alert.
  void watchPair(CurrencyPair pair) =>
      _service.invoke(MonitoringMessages.watchPair, {'pair': pair.symbol});

  void unwatchPair(CurrencyPair pair) =>
      _service.invoke(MonitoringMessages.unwatchPair, {'pair': pair.symbol});

  /// Stops the ringing alarm in the service isolate. If the service is not
  /// running, the persisted alarm state is marked stopped instead.
  Future<void> stopAlarm() async {
    if (await isRunning()) {
      _service.invoke(MonitoringMessages.stopAlarm);
      return;
    }
    final saved = await _storage.getAlarmState();
    if (saved.isRinging) {
      final stopped = saved.asStopped(DateTime.now());
      await _storage.saveAlarmState(stopped);
      final historyId = saved.historyId;
      if (historyId != null) {
        await _storage.markHistoryAlarmStopped(historyId, stopped.stoppedAt!);
      }
      _alarmCtrl.add(stopped);
    }
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _statusCtrl.close();
    await _priceCtrl.close();
    await _alarmCtrl.close();
    await _alertsUpdatedCtrl.close();
  }
}

/// Entry point executed inside the foreground service (its own isolate).
/// It builds the engine with real dependencies and bridges it to the UI.
@pragma('vm:entry-point')
Future<void> drezaFxMonitoringEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final storage = StorageService(SharedPreferencesKeyValueStore());
  final notifications = LocalNotificationService();
  await notifications.initialize();

  final market = createMarketDataService(storage);
  final engine = MonitoringEngine(
    storage: storage,
    marketData: market,
    alarm: AudioplayersAlarmAudioService(),
    notifications: notifications,
  );

  // service -> UI bridges
  engine.statusStream.listen((status) {
    service.invoke(MonitoringMessages.status, status.toJson());
    notifications.showMonitoringStatus(status);
  });
  engine.priceStream.listen(
      (price) => service.invoke(MonitoringMessages.price, price.toJson()));
  engine.alarmStateStream.listen((state) =>
      service.invoke(MonitoringMessages.alarmState, state.toJson()));
  engine.alertsChangedStream
      .listen((_) => service.invoke(MonitoringMessages.alertsUpdated));

  // UI -> service commands
  service.on(MonitoringMessages.alertsChanged).listen((_) {
    engine.reloadAlerts();
  });
  service.on(MonitoringMessages.reconnectMarket).listen((_) {
    engine.reconnectMarket();
  });
  service.on(MonitoringMessages.stopAlarm).listen((_) {
    engine.stopAlarm();
  });
  service.on(MonitoringMessages.watchPair).listen((data) {
    final pair = CurrencyPair.tryParse((data?['pair'] as String?) ?? '');
    if (pair != null) engine.watchPair(pair);
  });
  service.on(MonitoringMessages.unwatchPair).listen((data) {
    final pair = CurrencyPair.tryParse((data?['pair'] as String?) ?? '');
    if (pair != null) engine.unwatchPair(pair);
  });
  service.on(MonitoringMessages.requestSnapshot).listen((_) {
    service.invoke(MonitoringMessages.status, engine.status.toJson());
    service.invoke(MonitoringMessages.alarmState, engine.alarmState.toJson());
    // Also hand a freshly opened UI the latest real prices it missed.
    for (final pair in market.subscribedPairs) {
      final latest = market.getLatestPrice(pair);
      if (latest != null) service.invoke(MonitoringMessages.price, latest.toJson());
    }
  });
  service.on(MonitoringMessages.stopService).listen((_) async {
    await engine.stop();
    await engine.dispose();
    await service.stopSelf();
  });

  await engine.start();
}
