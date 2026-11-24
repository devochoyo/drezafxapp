import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/alarm_state.dart';
import '../models/alert_history.dart';
import '../models/currency_pair.dart';
import '../models/forex_alert.dart';
import '../models/market_connection_status.dart';
import '../models/market_price.dart';
import '../models/monitoring_status.dart';
import 'alarm_audio_service.dart';
import 'alert_evaluation_service.dart';
import 'market_data_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// The monitoring core: connects the market-data service, evaluates every
/// price against the active alerts, and on a crossing records history,
/// notifies and starts the alarm.
///
/// It is plain Dart with injected dependencies, so it runs inside the
/// background-service isolate in production and in unit tests with fakes.
/// It does NOT keep the process alive; that is the job of the Android
/// foreground service (see BackgroundMonitoringService).
class MonitoringEngine {
  MonitoringEngine({
    required StorageService storage,
    required MarketDataService marketData,
    required AlarmAudioService alarm,
    required NotificationService notifications,
    AlertEvaluationService evaluator = const AlertEvaluationService(),
    DateTime Function()? clock,
    Duration retryBaseDelay = const Duration(seconds: 5),
    Duration retryMaxDelay = const Duration(seconds: 60),
  })  : _storage = storage,
        _market = marketData,
        _alarm = alarm,
        _notifications = notifications,
        _evaluator = evaluator,
        _clock = clock ?? DateTime.now,
        _retryBase = retryBaseDelay,
        _retryMax = retryMaxDelay;

  final StorageService _storage;
  final MarketDataService _market;
  final AlarmAudioService _alarm;
  final NotificationService _notifications;
  final AlertEvaluationService _evaluator;
  final DateTime Function() _clock;
  final Duration _retryBase;
  final Duration _retryMax;

  final Map<String, ForexAlert> _alerts = {};
  final Set<CurrencyPair> _extraWatched = {};
  final Set<CurrencyPair> _subscribed = {};

  final _statusCtrl = StreamController<MonitoringStatus>.broadcast();
  final _priceCtrl = StreamController<MarketPrice>.broadcast();
  final _triggerCtrl = StreamController<ForexAlert>.broadcast();
  final _alertsCtrl = StreamController<void>.broadcast();

  StreamSubscription<MarketPrice>? _priceSub;
  StreamSubscription<MarketConnectionStatus>? _statusSub;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _running = false;
  bool _wasConnected = false;
  Future<void> _queue = Future.value();
  MonitoringStatus _status = MonitoringStatus.stopped;

  MonitoringStatus get status => _status;
  Stream<MonitoringStatus> get statusStream => _statusCtrl.stream;

  /// Every valid price received (for dashboards).
  Stream<MarketPrice> get priceStream => _priceCtrl.stream;

  /// Emits an alert right after it triggers.
  Stream<ForexAlert> get alertTriggeredStream => _triggerCtrl.stream;

  /// Emits when stored alerts/history changed because of the engine.
  Stream<void> get alertsChangedStream => _alertsCtrl.stream;

  Stream<AlarmState> get alarmStateStream => _alarm.stateStream;
  AlarmState get alarmState => _alarm.state;

  /// Loads alerts, connects the provider and starts evaluating.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _setStatus(_status.copyWith(
        serviceState: MonitoringServiceState.starting, clearLastError: true));
    _priceSub = _market.priceStream.listen(_enqueuePrice);
    _statusSub = _market.statusStream.listen(_onConnectionStatus);
    await reloadAlerts();
    _setStatus(_status.copyWith(serviceState: MonitoringServiceState.running));
    await _connect();
  }

  /// Stops monitoring and disconnects. Does not stop a ringing alarm.
  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    await _priceSub?.cancel();
    await _statusSub?.cancel();
    _priceSub = null;
    _statusSub = null;
    try {
      await _market.disconnect();
    } catch (_) {}
    _setStatus(_status.copyWith(
        serviceState: MonitoringServiceState.stopped,
        connection: MarketConnectionStatus.disconnected));
  }

  /// Re-reads alerts from storage after the UI changed them. Alerts that
  /// were not edited keep their in-memory crossing reference; new or edited
  /// alerts start without one.
  Future<void> reloadAlerts() => _serialize(reloadAlertsUnqueued);

  /// Keeps [pair] subscribed even without an alert (e.g. to show a price).
  Future<void> watchPair(CurrencyPair pair) async {
    _extraWatched.add(pair);
    await _serialize(_syncSubscriptions);
    _publishStatus();
  }

  Future<void> unwatchPair(CurrencyPair pair) async {
    _extraWatched.remove(pair);
    await _serialize(_syncSubscriptions);
    _publishStatus();
  }

  /// Stops the ringing alarm and records the acknowledgement.
  /// Re-opens the market-data connection now (credentials changed, or the
  /// user pressed Retry). Resets the retry back-off.
  Future<void> reconnectMarket() async {
    if (!_running) return;
    _retryTimer?.cancel();
    _retryAttempt = 0;
    try {
      await _market.disconnect();
    } catch (_) {}
    await _connect();
  }

  Future<void> stopAlarm() async {
    final before = _alarm.state;
    await _alarm.stopAlarm();
    final after = _alarm.state;
    await _storage.saveAlarmState(after);
    if (before.isRinging) {
      final historyId = before.historyId;
      if (historyId != null) {
        await _storage.markHistoryAlarmStopped(historyId, _clock());
        _alertsCtrl.add(null);
      }
      final alertId = before.alertId;
      if (alertId != null) await _notifications.cancelAlertNotification(alertId);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _alarm.dispose();
    await _market.dispose();
    await _statusCtrl.close();
    await _priceCtrl.close();
    await _triggerCtrl.close();
    await _alertsCtrl.close();
  }

  // ------------------------------------------------------------- internals

  Future<void> _connect() async {
    if (!_running) return;
    try {
      await _market.connect();
      _retryAttempt = 0;
    } on MarketDataException catch (e) {
      _setStatus(_status.copyWith(lastError: e.message));
      if (!e.isPermanent) _scheduleRetry();
    } catch (e) {
      _setStatus(_status.copyWith(lastError: e.toString()));
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retryTimer?.cancel();
    final factor = 1 << (_retryAttempt < 6 ? _retryAttempt : 6);
    var delay = _retryBase * factor;
    if (delay > _retryMax) delay = _retryMax;
    _retryAttempt++;
    _retryTimer = Timer(delay, _connect);
  }

  void _onConnectionStatus(MarketConnectionStatus connection) {
    final connected = connection.isConnected;
    if (connected && !_wasConnected) {
      // A reconnect may hide a gap in prices: restart every crossing
      // reference so the first new quote cannot trigger by itself.
      _resetAllReferences();
    }
    _wasConnected = connected;
    _setStatus(_status.copyWith(
      connection: connection,
      lastError: connection.state == MarketConnectionState.error
          ? connection.message
          : null,
      clearLastError: connected,
    ));
    if (connection.state == MarketConnectionState.error && _running) {
      _scheduleRetry();
    }
  }

  void _resetAllReferences() {
    _alerts.updateAll((_, alert) => _evaluator.resetReference(alert));
  }

  Future<void> _syncSubscriptions() async {
    final wanted = <CurrencyPair>{
      ..._alerts.values.map((a) => a.pair),
      ..._extraWatched,
    };
    for (final pair in _subscribed.difference(wanted)) {
      await _market.unsubscribe(pair);
    }
    for (final pair in wanted.difference(_subscribed)) {
      await _market.subscribe(pair);
    }
    _subscribed
      ..clear()
      ..addAll(wanted);
  }

  void _enqueuePrice(MarketPrice price) {
    _serialize(() => _handlePrice(price));
  }

  Future<void> _handlePrice(MarketPrice price) async {
    if (!_running || !price.isValid) return;
    _priceCtrl.add(price);
    _setStatus(_status.copyWith(lastPriceAt: price.timestamp));

    final matching =
        _alerts.values.where((a) => a.pair == price.pair).toList();
    for (final alert in matching) {
      final result = _evaluator.evaluate(alert, price, now: _clock());
      if (!result.triggered) {
        _alerts[alert.id] = result.alert;
        continue;
      }
      await _onTriggered(alert, result.alert);
    }
  }

  Future<void> _onTriggered(ForexAlert before, ForexAlert triggered) async {
    _alerts.remove(before.id);

    // The UI may have edited or deleted this alert in the meantime.
    final stored = await _storage.getAlert(before.id);
    if (stored == null || stored.updatedAt != before.updatedAt) {
      await reloadAlertsUnqueued();
      return;
    }

    await _storage.saveAlert(triggered);
    final history =
        AlertHistory.fromTriggeredAlert(const Uuid().v4(), triggered);
    await _storage.addHistory(history);
    _triggerCtrl.add(triggered);
    _alertsCtrl.add(null);
    _publishStatus();

    final settings = await _storage.getSettings();
    if (settings.notificationsEnabled) {
      try {
        await _notifications.showAlertTriggered(triggered,
            vibrate: settings.vibrationEnabled);
      } catch (_) {/* the alarm must still ring */}
    }

    // If an alarm is already ringing, the new alert is recorded in history
    // and notified, but the running sequence is not overlapped.
    final alarmState = AlarmState.ringingFor(triggered,
        historyId: history.id, startedAt: _clock());
    try {
      final started = await _alarm.startAlarm(alarmState);
      if (started) await _storage.saveAlarmState(alarmState);
    } catch (e) {
      _setStatus(_status.copyWith(lastError: 'Alarm audio failed: $e'));
    }
  }

  /// [reloadAlerts] but called from inside the queue (must not re-enter it).
  Future<void> reloadAlertsUnqueued() async {
    final stored = await _storage.getAlerts(status: AlertStatus.active);
    final next = <String, ForexAlert>{};
    for (final alert in stored) {
      final current = _alerts[alert.id];
      final unchanged = current != null &&
          current.updatedAt == alert.updatedAt &&
          current.pair == alert.pair &&
          current.targetPrice == alert.targetPrice;
      next[alert.id] = unchanged ? current : _evaluator.resetReference(alert);
    }
    _alerts
      ..clear()
      ..addAll(next);
    await _syncSubscriptions();
    _publishStatus();
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((_) {});
    return next;
  }

  void _publishStatus() {
    _setStatus(_status.copyWith(
      activeAlertCount: _alerts.length,
      watchedPairs: (_subscribed.map((p) => p.symbol).toList()..sort()),
    ));
  }

  void _setStatus(MonitoringStatus status) {
    _status = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }
}
